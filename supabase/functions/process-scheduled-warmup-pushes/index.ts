// Edge Function: process-scheduled-warmup-pushes
//
// Вызывается планировщиком pg_cron каждые 5 минут. Не предназначена для
// прямого вызова из клиента — авторизация только по CRON_SECRET.
//
// Логика:
//   1. Находит все warmup_blocks с is_published=true, publish_at <= now(),
//      push_sent_at IS NULL — это посты, которые «дозрели» и push ещё не уходил.
//   2. Для каждого формирует payload (day_title, post_title, emoji) и шлёт
//      push всем role='student' (как notify-warmup-published).
//   3. Помечает push_sent_at=now() — чтобы не дублировать в следующем тике.
//   4. То же для warmup_days (когда «открывается» весь день целиком).
//
// Безопасность: бэк-эндпойнт. Запрашивающий должен прислать
// Authorization: Bearer <CRON_SECRET>. Это собственный разовый секрет,
// который мы задаём в Supabase Edge Functions → Secrets, и тот же секрет
// прописан в pg_cron функции trigger_warmup_push_cron(). Так не приходится
// таскать service_role по pg_cron-задачам и не зависим от того, какой ключ
// сейчас лежит в Supabase env (legacy JWT vs новый sb_sec_*).
//
// Env vars (нужно установить в Supabase Dashboard → Edge Functions → Secrets):
//   SUPABASE_URL              — стандартный (есть автоматически)
//   SUPABASE_SERVICE_ROLE_KEY — стандартный (есть автоматически)
//   CRON_SECRET               — любая случайная длинная строка, которую
//                                ты сама задашь (например, 40 случайных
//                                символов). Тот же секрет прописан в
//                                pg_cron функции (см. миграцию).
//   VAPID_PUBLIC_KEY          — общий с notify-warmup-published
//   VAPID_PRIVATE_KEY         — общий
//   VAPID_SUBJECT             — mailto:[email protected]

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import webpush from 'https://esm.sh/web-push@3.6.7';

const SUPABASE_URL      = Deno.env.get('SUPABASE_URL')!;
const SERVICE_ROLE_KEY  = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const CRON_SECRET       = Deno.env.get('CRON_SECRET') || '';
const VAPID_PUBLIC_KEY  = Deno.env.get('VAPID_PUBLIC_KEY')!;
const VAPID_PRIVATE_KEY = Deno.env.get('VAPID_PRIVATE_KEY')!;
const VAPID_SUBJECT     = Deno.env.get('VAPID_SUBJECT') || 'mailto:[email protected]';

webpush.setVapidDetails(VAPID_SUBJECT, VAPID_PUBLIC_KEY, VAPID_PRIVATE_KEY);

const sbAdmin = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, {
  auth: { persistSession: false },
});

const corsHeaders = {
  'Access-Control-Allow-Origin':  '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  if (req.method !== 'POST') return new Response('Use POST', { status: 405, headers: corsHeaders });

  // === Авторизация: только cron-секрет ===
  if (!CRON_SECRET) {
    console.error('[scheduled-pushes] CRON_SECRET не задан в env');
    return json({ error: 'cron_secret_not_configured' }, 500);
  }
  const authHeader = req.headers.get('Authorization') || '';
  const token = authHeader.replace(/^Bearer\s+/i, '');
  if (!token || token !== CRON_SECRET) {
    console.warn('[scheduled-pushes] неавторизованный запрос');
    return json({ error: 'unauthorized' }, 401);
  }

  const nowIso = new Date().toISOString();

  // === Найти всех учеников и их подписки один раз ===
  const { data: students, error: studErr } = await sbAdmin
    .from('profiles')
    .select('id')
    .eq('role', 'student');
  if (studErr) {
    console.error('[scheduled-pushes] students query failed:', studErr);
    return json({ error: 'students_query_failed', message: studErr.message }, 500);
  }
  const studentIds = (students || []).map((s: any) => s.id);

  const { data: subs, error: subsErr } = studentIds.length
    ? await sbAdmin
        .from('push_subscriptions')
        .select('id, user_id, endpoint, p256dh, auth')
        .in('user_id', studentIds)
    : { data: [] as any[], error: null };
  if (subsErr) {
    console.error('[scheduled-pushes] subs query failed:', subsErr);
    return json({ error: 'subs_query_failed', message: subsErr.message }, 500);
  }
  const subscriptions = (subs || []) as any[];
  console.log('[scheduled-pushes] подписок:', subscriptions.length, '/ учеников:', studentIds.length);

  // === Найти созревшие посты ===
  const { data: ripeBlocks, error: blocksErr } = await sbAdmin
    .from('warmup_blocks')
    .select('id, day_id, intensive_day_ord, title, emoji, publish_at')
    .eq('is_published', true)
    .lte('publish_at', nowIso)
    .is('push_sent_at', null)
    .not('publish_at', 'is', null);
  if (blocksErr) {
    console.error('[scheduled-pushes] blocks query failed:', blocksErr);
    return json({ error: 'blocks_query_failed', message: blocksErr.message }, 500);
  }

  // Дни warmup, у которых наступило время появления (вся подборка постов разом)
  const { data: ripeDays, error: daysErr } = await sbAdmin
    .from('warmup_days')
    .select('id, ord, title, emoji, publish_at')
    .eq('is_published', true)
    .lte('publish_at', nowIso)
    .is('push_sent_at', null)
    .not('publish_at', 'is', null);
  if (daysErr) {
    console.error('[scheduled-pushes] days query failed:', daysErr);
    return json({ error: 'days_query_failed', message: daysErr.message }, 500);
  }

  const blocks = ripeBlocks || [];
  const days = ripeDays || [];
  console.log('[scheduled-pushes] созревших постов:', blocks.length, ', дней:', days.length);

  if (!blocks.length && !days.length) {
    return json({ ok: true, blocks_processed: 0, days_processed: 0, push_sent: 0 });
  }

  // === Подгрузить заголовки warmup-дней для постов, у которых только day_id ===
  const dayIdsForBlocks = Array.from(new Set(blocks.filter(b => b.day_id).map(b => b.day_id)));
  let warmupDayTitles: Record<number, string> = {};
  if (dayIdsForBlocks.length) {
    const { data: dRows } = await sbAdmin
      .from('warmup_days')
      .select('id, ord, title, emoji')
      .in('id', dayIdsForBlocks);
    (dRows || []).forEach((d: any) => {
      warmupDayTitles[d.id] = (d.emoji ? d.emoji + ' ' : '') + (d.title || ('Разогрев · день ' + d.ord));
    });
  }

  // === Рассылка: один цикл по всем посылкам, чтобы посчитать общую статистику ===
  let totalSent = 0;
  let totalFailed = 0;
  const expiredSubIds = new Set<number>();

  async function sendBatch(payloadObj: any, tagSuffix: string) {
    if (!subscriptions.length) return { sent: 0, failed: 0 };
    const payload = JSON.stringify({
      title: payloadObj.title,
      body:  payloadObj.body,
      url:   payloadObj.url,
      tag:   'warmup-' + tagSuffix,
    });
    let sent = 0, failed = 0;
    await Promise.all(subscriptions.map(async (s: any) => {
      const subscription = {
        endpoint: s.endpoint,
        keys: { p256dh: s.p256dh, auth: s.auth },
      };
      try {
        await webpush.sendNotification(subscription, payload);
        sent++;
      } catch (err: any) {
        failed++;
        const code = err && err.statusCode;
        const isApple = (s.endpoint || '').includes('web.push.apple.com');
        if (code === 404 || code === 410 || (code === 403 && isApple)) {
          expiredSubIds.add(s.id);
        }
      }
    }));
    return { sent, failed };
  }

  const notifUrl = 'https://zebrus.online/?utm_source=push&utm_medium=warmup';

  // --- Сначала дни (более крупная единица) ---
  for (const d of days) {
    const dayLabel = (d.emoji ? d.emoji + ' ' : '') + (d.title || ('Разогрев · день ' + d.ord));
    const stats = await sendBatch({
      title: '🔥 Открылся новый день: ' + dayLabel,
      body:  'Открой Разогрев — там ждут новые задания',
      url:   notifUrl,
    }, 'day-' + d.id);
    totalSent += stats.sent; totalFailed += stats.failed;
    // Помечаем только при успешной отправке хотя бы кому-то ИЛИ при отсутствии подписчиков
    // (чтобы не зацикливаться на дне, если push некому слать).
    const { error: upErr } = await sbAdmin
      .from('warmup_days').update({ push_sent_at: nowIso }).eq('id', d.id);
    if (upErr) console.warn('[scheduled-pushes] mark day failed', d.id, upErr.message);
  }

  // --- Потом отдельные посты ---
  for (const b of blocks) {
    const dayLabel = b.day_id
      ? (warmupDayTitles[b.day_id] || 'разогрева')
      : 'интенсива';
    const titlePrefix = b.emoji ? (b.emoji + ' ') : '🔥 ';
    const notifTitle = titlePrefix + 'Новый пост в дне ' + dayLabel;
    const notifBody  = b.title
      ? '«' + b.title + '» — открой и посмотри'
      : 'Открой Разогрев — там ждёт новое задание';
    const stats = await sendBatch({
      title: notifTitle,
      body:  notifBody,
      url:   notifUrl,
    }, (b.day_id ? 'd' : 'i') + (b.day_id || b.intensive_day_ord || 'x'));
    totalSent += stats.sent; totalFailed += stats.failed;
    const { error: upErr } = await sbAdmin
      .from('warmup_blocks').update({ push_sent_at: nowIso }).eq('id', b.id);
    if (upErr) console.warn('[scheduled-pushes] mark block failed', b.id, upErr.message);
  }

  // Чистим протухшие подписки (как в notify-warmup-published)
  if (expiredSubIds.size) {
    const arr = Array.from(expiredSubIds);
    await sbAdmin.from('push_subscriptions').delete().in('id', arr);
    console.log('[scheduled-pushes] 🗑 удалено протухших подписок:', arr.length);
  }

  return json({
    ok: true,
    blocks_processed: blocks.length,
    days_processed:   days.length,
    push_sent:        totalSent,
    push_failed:      totalFailed,
    expired_subs:     expiredSubIds.size,
    subscriptions_total: subscriptions.length,
  });
});

function json(obj: unknown, status = 200) {
  return new Response(JSON.stringify(obj), {
    status,
    headers: { 'Content-Type': 'application/json', ...corsHeaders },
  });
}
