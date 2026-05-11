// Edge Function: tg-cron
//
// Дёргается раз в минуту из pg_cron (cron-задание в БД). Делает две вещи:
//
//   1. Напоминание за час до вебинара — находит активности kind='webinar',
//      время старта которых попадает в окно [now+55min, now+65min],
//      у которых webinar_reminded_at = NULL. Шлёт всем enrolled ученикам
//      TG-уведомление, помечает reminded_at.
//
//   2. Открытие нового дня — находит intensive_days с day_date=сегодня,
//      open_notified_at=NULL, time-of-day ≥ DAY_OPEN_HOUR. Шлёт всем
//      enrolled ученикам, помечает.
//
// БЕЗОПАСНОСТЬ: X-Cron-Secret в header. Verify JWT в Supabase = OFF.

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const SUPABASE_URL       = Deno.env.get('SUPABASE_URL')!;
const SERVICE_ROLE_KEY   = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const TELEGRAM_BOT_TOKEN = Deno.env.get('TELEGRAM_BOT_TOKEN')!;
const TG_CRON_SECRET     = Deno.env.get('TG_CRON_SECRET') || '';

const DAY_OPEN_HOUR = 9;  // час «открытия» дня по интенсивному расписанию
const TG_API = `https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}`;

const sb = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, {
  auth: { persistSession: false },
});

async function sendTg(chatId: number, text: string, link?: string) {
  const reply_markup = link
    ? { inline_keyboard: [[{ text: 'Открыть', url: link }]] }
    : undefined;
  const r = await fetch(`${TG_API}/sendMessage`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      chat_id: chatId, text,
      parse_mode: 'HTML',
      disable_web_page_preview: true,
      reply_markup,
    }),
  });
  if (r.status === 403) {
    // Бот заблокирован — отключим уведомления для этого юзера
    await sb.from('profiles').update({ tg_notify_enabled: false })
      .eq('telegram_id', chatId);
  }
  return r.ok;
}

/** Получить telegram_id всех enrolled учеников + активных учителей/кураторов
 *  с подключённым и не-выключенным Telegram. */
async function recipientsForIntensive(intensiveId: number, alsoTeacherCurator = false): Promise<number[]> {
  const ids: number[] = [];

  // ученики из enrollments
  const { data: enr } = await sb
    .from('enrollments')
    .select('student:profiles!enrollments_student_id_fkey(telegram_id, tg_notify_enabled)')
    .eq('intensive_id', intensiveId);
  if (Array.isArray(enr)) {
    for (const row of enr) {
      const s = (row as any).student;
      if (s && s.telegram_id && s.tg_notify_enabled !== false) ids.push(s.telegram_id);
    }
  }

  if (alsoTeacherCurator) {
    const { data: tc } = await sb
      .from('profiles')
      .select('telegram_id, tg_notify_enabled')
      .in('role', ['teacher', 'curator']);
    if (Array.isArray(tc)) {
      for (const p of tc) {
        if (p.telegram_id && p.tg_notify_enabled !== false) ids.push(p.telegram_id);
      }
    }
  }
  return ids;
}

serve(async (req) => {
  if (req.method !== 'POST') return new Response('Use POST', { status: 405 });

  // Защита крон-секретом
  if (TG_CRON_SECRET) {
    const hdr = req.headers.get('X-Cron-Secret');
    if (hdr !== TG_CRON_SECRET) return new Response('Forbidden', { status: 403 });
  }

  const result: any = { webinars_notified: 0, days_notified: 0, errors: [] };
  const nowIso = new Date().toISOString();

  // === 1. Напоминание о вебинаре за час ===
  try {
    // Берём активности с kind=webinar, без reminded_at. Им нужно знать
    // day_date (из intensive_days) и start_at (из day_activities), плюс intensive_id.
    const { data: webinars, error: e1 } = await sb
      .from('day_activities')
      .select(`
        id, day_id, start_at, title,
        day:intensive_days!day_activities_day_id_fkey(id, day_date, intensive_id, title)
      `)
      .eq('kind', 'webinar')
      .is('webinar_reminded_at', null);
    if (e1) throw e1;

    console.log('[CRON] webinars без reminded_at:', (webinars || []).length);
    for (const w of (webinars || []) as any[]) {
      const day = w.day;
      if (!day || !day.day_date || !w.start_at){
        console.log('[CRON] webinar skip — нет day/start_at', { id: w.id, day });
        continue;
      }
      const startTs = new Date(day.day_date + 'T' + w.start_at + '+03:00').getTime();
      const now = Date.now();
      const deltaMin = (startTs - now) / 60000;
      console.log('[CRON] webinar', { id: w.id, day_date: day.day_date, start_at: w.start_at, deltaMin });
      if (deltaMin < 55 || deltaMin > 65) continue;
      const ids = await recipientsForIntensive(day.intensive_id, false);
      console.log('[CRON] webinar получателей:', ids.length, 'intensive_id:', day.intensive_id);
      const text = '🎙 <b>Вебинар через час!</b>\n\n' +
                   '📅 ' + day.day_date + ', начало в ' + w.start_at.slice(0, 5) + '\n' +
                   '📚 ' + (w.title || day.title || 'Урок интенсива');
      for (const tgId of ids) {
        const ok = await sendTg(tgId, text, 'https://zebrus.online');
        console.log('[CRON] sendTg', tgId, ok ? 'OK' : 'FAIL');
      }
      await sb.from('day_activities').update({ webinar_reminded_at: nowIso }).eq('id', w.id);
      result.webinars_notified++;
    }
  } catch (e) {
    result.errors.push('webinar: ' + (e as Error).message);
  }

  // === 2. Открытие нового дня ===
  try {
    const today = new Date().toISOString().slice(0, 10); // YYYY-MM-DD UTC; для МСК сдвиг учтём в условии часа
    const nowMsk = new Date(Date.now() + 3 * 60 * 60 * 1000); // примерно МСК
    const hour = nowMsk.getUTCHours();

    if (hour >= DAY_OPEN_HOUR) {
      const { data: days, error: e2 } = await sb
        .from('intensive_days')
        .select('id, intensive_id, ord, title, day_date')
        .eq('day_date', today)
        .is('open_notified_at', null);
      if (e2) throw e2;

      for (const d of (days || []) as any[]) {
        const ids = await recipientsForIntensive(d.intensive_id, false);
        const text = '📅 <b>Открыт День ' + (d.ord ?? '?') + '!</b>\n\n' +
                     (d.title ? '📚 ' + d.title + '\n' : '') +
                     'Заходи в кабинет, поехали 🐝';
        for (const tgId of ids) {
          await sendTg(tgId, text, 'https://zebrus.online');
        }
        await sb.from('intensive_days').update({ open_notified_at: nowIso }).eq('id', d.id);
        result.days_notified++;
      }
    }
  } catch (e) {
    result.errors.push('day_open: ' + (e as Error).message);
  }

  return new Response(JSON.stringify(result), {
    headers: { 'Content-Type': 'application/json' },
  });
});
