// Edge Function: tg-webhook
//
// Принимает обновления от Telegram бота @ZRMoveBot. Telegram POSTит сюда
// на каждое сообщение / нажатие inline-кнопки. Поддерживает:
//
//  • /start <token>  — привязка telegram_id к профилю по link_token,
//                      сгенерированному в кабинете на zebrus.online.
//  • /stop           — выключить уведомления (tg_notify_enabled = false).
//  • /start_notify   — снова включить уведомления.
//  • /help           — короткая справка.
//
// БЕЗОПАСНОСТЬ: webhook URL содержит секретный сегмент, плюс проверяем
// X-Telegram-Bot-Api-Secret-Token. Если совпадение нарушено — 401.

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const SUPABASE_URL       = Deno.env.get('SUPABASE_URL')!;
const SERVICE_ROLE_KEY   = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const TELEGRAM_BOT_TOKEN = Deno.env.get('TELEGRAM_BOT_TOKEN')!;
const TELEGRAM_SECRET    = Deno.env.get('TELEGRAM_WEBHOOK_SECRET') || '';

const TG_API = `https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}`;

const sb = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, {
  auth: { persistSession: false },
});

async function sendMessage(chat_id: number, text: string, opts: Record<string, unknown> = {}) {
  const body = { chat_id, text, parse_mode: 'HTML', disable_web_page_preview: true, ...opts };
  const resp = await fetch(`${TG_API}/sendMessage`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  });
  if (!resp.ok) {
    console.warn('sendMessage упал:', resp.status, await resp.text());
  }
  return resp.ok;
}

serve(async (req) => {
  if (req.method !== 'POST') {
    return new Response('Use POST', { status: 405 });
  }

  // Сверяем секрет в заголовке (его задаём при setWebhook через secret_token)
  if (TELEGRAM_SECRET) {
    const hdr = req.headers.get('X-Telegram-Bot-Api-Secret-Token');
    if (hdr !== TELEGRAM_SECRET) {
      console.warn('Webhook secret mismatch');
      return new Response('Forbidden', { status: 403 });
    }
  }

  let update: any;
  try { update = await req.json(); }
  catch { return new Response('Bad JSON', { status: 400 }); }

  // Нас интересует только message с текстом
  const msg = update.message || update.edited_message;
  if (!msg || !msg.text) return new Response('OK');

  const chatId    = msg.chat?.id;
  const tgUserId  = msg.from?.id;
  const firstName = (msg.from?.first_name || '') as string;
  const username  = (msg.from?.username || '')   as string;
  const text      = String(msg.text || '').trim();

  if (!chatId || !tgUserId) return new Response('OK');

  // === /start <token> — привязка
  if (text.startsWith('/start')) {
    const parts = text.split(/\s+/);
    const token = parts[1] || '';

    if (!token) {
      await sendMessage(chatId,
        '👋 Привет! Я бот ЗебРус.\n\n' +
        'Чтобы получать уведомления, зайди в свой кабинет на ' +
        '<a href="https://zebrus.online">zebrus.online</a> и нажми ' +
        '<b>«🤖 Привязать Telegram»</b>.');
      return new Response('OK');
    }

    // Ищем профиль по токену
    const { data: profile, error } = await sb
      .from('profiles')
      .select('id, full_name')
      .eq('telegram_link_token', token)
      .maybeSingle();

    if (error || !profile) {
      await sendMessage(chatId,
        '⚠ Не нашёл связку. Зайди в кабинет на zebrus.online и нажми ' +
        '<b>«🤖 Привязать Telegram»</b> ещё раз — это сгенерит свежую ссылку.');
      return new Response('OK');
    }

    // Сохраняем telegram_id, имя; токен очищаем — он одноразовый
    const updateRes = await sb.from('profiles').update({
      telegram_id:         tgUserId,
      telegram_name:       (firstName || username || null),
      telegram_link_token: null,
      tg_notify_enabled:   true,
    }).eq('id', profile.id);

    if (updateRes.error) {
      console.warn('UPDATE profile failed:', updateRes.error);
      await sendMessage(chatId, '⚠ Что-то пошло не так на сервере. Попробуй ещё раз через минуту.');
      return new Response('OK');
    }

    await sendMessage(chatId,
      `✅ Готово, <b>${profile.full_name || 'друг'}</b>!\n\n` +
      'Теперь сюда будут приходить:\n' +
      '🐝 уведомления о проверенных сочинениях\n' +
      '💬 сообщения от учителя и кураторов\n' +
      '🎙 напоминания за час до вебинара\n' +
      '📅 открытие новых дней интенсива\n\n' +
      'Чтобы временно отключить — /stop. Включить обратно — /start_notify.');
    return new Response('OK');
  }

  // === /stop — выключить уведомления
  if (text === '/stop' || text === '/stop@ZRMoveBot') {
    const r = await sb.from('profiles').update({ tg_notify_enabled: false }).eq('telegram_id', tgUserId);
    if (r.error) console.warn(r.error);
    await sendMessage(chatId, '🔕 Уведомления выключены. Чтобы включить — /start_notify');
    return new Response('OK');
  }

  // === /start_notify — включить
  if (text === '/start_notify' || text === '/start_notify@ZRMoveBot') {
    const r = await sb.from('profiles').update({ tg_notify_enabled: true }).eq('telegram_id', tgUserId);
    if (r.error) console.warn(r.error);
    await sendMessage(chatId, '🔔 Уведомления снова включены. Удачи на ЕГЭ 🐝');
    return new Response('OK');
  }

  // === /help
  if (text === '/help' || text === '/help@ZRMoveBot') {
    await sendMessage(chatId,
      '<b>Команды бота:</b>\n' +
      '/start &lt;token&gt; — привязка к кабинету\n' +
      '/stop — выключить уведомления\n' +
      '/start_notify — включить уведомления\n' +
      '/help — эта справка\n\n' +
      'Кабинет: <a href="https://zebrus.online">zebrus.online</a>');
    return new Response('OK');
  }

  // Любой другой текст — короткое объяснение
  await sendMessage(chatId,
    'Я слушаю команды, а не свободный текст. Попробуй /help.\n' +
    'Учиться и писать сообщения — в кабинете: https://zebrus.online');

  return new Response('OK');
});
