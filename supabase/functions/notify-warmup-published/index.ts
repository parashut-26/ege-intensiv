// Edge Function: notify-warmup-published
//
// Учитель опубликовал новый пост в Разогреве/Дне интенсива (создал или включил
// is_published=true в warmup_blocks) — клиент после успешного INSERT/PATCH
// дёргает эту функцию. Функция:
//   1. Находит всех учеников у которых есть активные push_subscriptions
//   2. Рассылает им Web Push «🔥 Новый пост в [день]»
//
// Принимает JSON:
//   { day_id?: number, intensive_day_ord?: number,
//     day_title?: string, post_title?: string, post_emoji?: string,
//     audience?: 'all' | 'active' }   // active = только ученики со статусом active
//
// АВТОРИЗАЦИЯ: Authorization: Bearer <JWT> учителя.

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import webpush from 'https://esm.sh/web-push@3.6.7';

const SUPABASE_URL      = Deno.env.get('SUPABASE_URL')!;
const SERVICE_ROLE_KEY  = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
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

interface Payload {
  day_id?:            number;
  intensive_day_ord?: number;
  day_title?:         string;
  post_title?:        string;
  post_emoji?:        string;
  audience?:          'all' | 'active';
}

serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  if (req.method !== 'POST') return new Response('Use POST', { status: 405, headers: corsHeaders });

  // === 1. Авторизация: только учитель/куратор ===
  const authHeader = req.headers.get('Authorization') || '';
  const jwt = authHeader.replace(/^Bearer\s+/i, '');
  if (!jwt) return json({ error: 'unauthorized' }, 401);

  let senderId: string | null = null;
  try {
    const parts = jwt.split('.');
    const payload = JSON.parse(atob(parts[1].replace(/-/g, '+').replace(/_/g, '/')));
    senderId = payload.sub || null;
  } catch { return json({ error: 'bad_jwt' }, 401); }
  if (!senderId) return json({ error: 'no_sub' }, 401);

  const { data: sender } = await sbAdmin
    .from('profiles').select('role').eq('id', senderId).maybeSingle();
  if (!sender || (sender.role !== 'teacher' && sender.role !== 'curator')) {
    return json({ error: 'only_teacher_or_curator' }, 403);
  }

  // === 2. Парсинг входа ===
  let body: Payload;
  try { body = await req.json() as Payload; }
  catch { return json({ error: 'bad_json' }, 400); }

  const dayLabel = body.day_title || (body.day_id ? 'разогрева' : 'интенсива');
  const titlePrefix = body.post_emoji ? (body.post_emoji + ' ') : '🔥 ';
  const notifTitle = titlePrefix + 'Новый пост в дне ' + dayLabel;
  const notifBody  = body.post_title
    ? '«' + body.post_title + '» — открой и посмотри'
    : 'Открой Разогрев — там ждёт новое задание';
  const notifUrl = 'https://zebrus.online/?utm_source=push&utm_medium=warmup';

  // === 3. Найти всех учеников ===
  // Колонки статуса в profiles нет (на старте интенсива пусть приходит всем),
  // так что просто берём всех role='student'.
  const { data: students, error: studErr } = await sbAdmin
    .from('profiles')
    .select('id, full_name, role')
    .eq('role', 'student');
  if (studErr) {
    console.error('[notify-warmup] students query failed:', studErr);
    return json({ error: 'students_query_failed', message: studErr.message }, 500);
  }
  const studentIds = (students || []).map(s => s.id);

  if (!studentIds.length) {
    return json({ ok: true, sent: 0, failed: 0, note: 'no_students' });
  }

  // === 4. Подписки этих учеников ===
  const { data: subs, error: subsErr } = await sbAdmin
    .from('push_subscriptions')
    .select('id, user_id, endpoint, p256dh, auth')
    .in('user_id', studentIds);
  if (subsErr) {
    console.error('[notify-warmup] subs query failed:', subsErr);
    return json({ error: 'subs_query_failed', message: subsErr.message }, 500);
  }
  console.log('[notify-warmup] подписок найдено:', subs?.length || 0, '/ учеников:', studentIds.length);
  if (!subs || !subs.length) {
    return json({ ok: true, sent: 0, failed: 0, note: 'no_subscriptions', students_total: studentIds.length });
  }

  // === 5. Рассылка параллельно ===
  const payload = JSON.stringify({
    title: notifTitle,
    body:  notifBody,
    url:   notifUrl,
    tag:   'warmup-' + (body.day_id || body.intensive_day_ord || 'x'),  // одно уведомление перезаписывает старое
  });

  let sent = 0, failed = 0;
  const expired: number[] = [];
  await Promise.all(subs.map(async (s: any) => {
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
      console.warn('[notify-warmup] ✗ id=' + s.id + ' code=' + code + ' apple=' + isApple);
      if (code === 404 || code === 410 || (code === 403 && isApple)) {
        expired.push(s.id);
      }
    }
  }));

  // Удаляем протухшие подписки
  if (expired.length) {
    await sbAdmin.from('push_subscriptions').delete().in('id', expired);
    console.log('[notify-warmup] 🗑️ удалено протухших подписок:', expired.length);
  }

  return json({
    ok: sent > 0,
    sent, failed,
    expired: expired.length,
    subscriptions_total: subs.length,
    students_total: studentIds.length,
    day_label: dayLabel,
  });
});

function json(obj: unknown, status = 200) {
  return new Response(JSON.stringify(obj), {
    status,
    headers: { 'Content-Type': 'application/json', ...corsHeaders },
  });
}
