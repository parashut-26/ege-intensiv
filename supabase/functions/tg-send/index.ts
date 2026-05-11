// Edge Function: tg-send
//
// Универсальная отправка Telegram-уведомления конкретному пользователю.
// Фронт вызывает её после событий: «новое сообщение в ЛС», «сочинение
// проверено», «открыт новый день».
//
// Принимает JSON: { user_id: UUID, text: string, link?: string }
// Опционально к сообщению прицепляется inline-кнопка «Открыть».
//
// АВТОРИЗАЦИЯ: требуется Authorization: Bearer <JWT> текущего пользователя
// (или service role). Если не учитель/куратор — можно слать только себе
// (защита от того, чтобы ученик не слал левые уведомления другим).

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const SUPABASE_URL       = Deno.env.get('SUPABASE_URL')!;
const SERVICE_ROLE_KEY   = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const TELEGRAM_BOT_TOKEN = Deno.env.get('TELEGRAM_BOT_TOKEN')!;

const TG_API = `https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}`;

const corsHeaders = {
  'Access-Control-Allow-Origin':  '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

const sbAdmin = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, {
  auth: { persistSession: false },
});

interface Payload {
  user_id: string;
  text:    string;
  link?:   string;
}

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }
  if (req.method !== 'POST') {
    return new Response('Use POST', { status: 405, headers: corsHeaders });
  }

  // Декодируем JWT отправителя — узнать его id и роль
  const authHeader = req.headers.get('Authorization') || '';
  const jwt = authHeader.replace(/^Bearer\s+/i, '');
  if (!jwt) {
    return json({ error: 'unauthorized' }, 401);
  }

  let senderId: string | null = null;
  let senderRole = 'student';
  try {
    const parts = jwt.split('.');
    const payload = JSON.parse(atob(parts[1].replace(/-/g, '+').replace(/_/g, '/')));
    senderId = payload.sub || null;
  } catch {
    return json({ error: 'bad_jwt' }, 401);
  }
  if (!senderId) return json({ error: 'no_sub' }, 401);

  // Узнаём роль отправителя (учитель/куратор могут слать любому)
  const { data: sender } = await sbAdmin
    .from('profiles').select('role').eq('id', senderId).maybeSingle();
  if (sender?.role) senderRole = sender.role;

  let body: Payload;
  try { body = await req.json() as Payload; }
  catch { return json({ error: 'bad_json' }, 400); }

  if (!body.user_id || !body.text) {
    return json({ error: 'user_id_and_text_required' }, 400);
  }

  // Защита: ученик может слать только сам себе (для тестов).
  // Учитель/куратор — кому угодно.
  if (senderRole === 'student' && body.user_id !== senderId) {
    return json({ error: 'forbidden_other_user' }, 403);
  }

  // Достаём telegram_id адресата
  const { data: target, error } = await sbAdmin
    .from('profiles')
    .select('telegram_id, tg_notify_enabled')
    .eq('id', body.user_id)
    .maybeSingle();

  if (error || !target) {
    return json({ error: 'target_not_found' }, 404);
  }
  if (!target.telegram_id) {
    return json({ ok: false, reason: 'no_telegram_link' });
  }
  if (target.tg_notify_enabled === false) {
    return json({ ok: false, reason: 'notify_disabled' });
  }

  // Опциональная inline-кнопка «Открыть»
  const reply_markup = body.link ? {
    inline_keyboard: [[{ text: 'Открыть', url: body.link }]],
  } : undefined;

  // Шлём
  const resp = await fetch(`${TG_API}/sendMessage`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      chat_id: target.telegram_id,
      text: body.text,
      parse_mode: 'HTML',
      disable_web_page_preview: true,
      reply_markup,
    }),
  });

  if (!resp.ok) {
    const errText = await resp.text();
    // 403 = бот заблокирован пользователем → отключаем уведомления,
    // чтобы не долбить дальше.
    if (resp.status === 403) {
      await sbAdmin.from('profiles')
        .update({ tg_notify_enabled: false })
        .eq('id', body.user_id);
    }
    return json({ ok: false, tg_status: resp.status, tg_error: errText });
  }

  return json({ ok: true });
});

function json(obj: unknown, status = 200) {
  return new Response(JSON.stringify(obj), {
    status,
    headers: { 'Content-Type': 'application/json', ...corsHeaders },
  });
}
