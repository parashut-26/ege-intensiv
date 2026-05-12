// Edge Function: push-send
//
// Отправляет Web Push уведомления конкретному user_id.
// Подходит для тех же триггеров что и tg-send (новое ЛС, проверенное сочинение).
// Использует VAPID-подпись через стандартный Web Push.
//
// Принимает JSON: { user_id: UUID, title: string, body: string, url?: string }
// АВТОРИЗАЦИЯ: Authorization: Bearer <JWT>. JWT декодируется внутри.
// (Verify JWT в Supabase выключен.)

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
  user_id: string;
  title:   string;
  body:    string;
  url?:    string;
}

serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  if (req.method !== 'POST') return new Response('Use POST', { status: 405, headers: corsHeaders });

  // Декод JWT отправителя
  const authHeader = req.headers.get('Authorization') || '';
  const jwt = authHeader.replace(/^Bearer\s+/i, '');
  if (!jwt) return json({ error: 'unauthorized' }, 401);

  let senderId: string | null = null;
  let senderRole = 'student';
  try {
    const parts = jwt.split('.');
    const payload = JSON.parse(atob(parts[1].replace(/-/g, '+').replace(/_/g, '/')));
    senderId = payload.sub || null;
  } catch { return json({ error: 'bad_jwt' }, 401); }
  if (!senderId) return json({ error: 'no_sub' }, 401);

  const { data: sender } = await sbAdmin
    .from('profiles').select('role').eq('id', senderId).maybeSingle();
  if (sender?.role) senderRole = sender.role;

  let body: Payload;
  try { body = await req.json() as Payload; }
  catch { return json({ error: 'bad_json' }, 400); }

  if (!body.user_id || !body.title) {
    return json({ error: 'user_id_and_title_required' }, 400);
  }

  // Проверка прав (как в tg-send)
  const { data: target } = await sbAdmin
    .from('profiles').select('role').eq('id', body.user_id).maybeSingle();
  if (!target) return json({ error: 'target_not_found' }, 404);
  if (senderRole === 'student' && body.user_id !== senderId) {
    if (target.role !== 'teacher' && target.role !== 'curator') {
      return json({ error: 'forbidden_other_user' }, 403);
    }
  }

  console.log('[push-send] sender=' + senderId + ' role=' + senderRole + ' → target=' + body.user_id);

  // Достаём все активные подписки этого юзера
  const { data: subs, error: subsErr } = await sbAdmin
    .from('push_subscriptions')
    .select('id, endpoint, p256dh, auth')
    .eq('user_id', body.user_id);

  if (subsErr) {
    console.error('[push-send] subs query error:', subsErr);
    return json({ ok: false, reason: 'subs_query_error', error: subsErr.message });
  }
  console.log('[push-send] подписок найдено:', subs ? subs.length : 0);
  if (!subs || !subs.length) return json({ ok: false, reason: 'no_subscriptions' });

  // Шлём по всем подпискам параллельно. Если 410/404 — подписка протухла, удаляем.
  const payload = JSON.stringify({
    title: body.title,
    body:  body.body,
    url:   body.url || 'https://zebrus.online',
  });

  let sent = 0, failed = 0;
  const errors: string[] = [];
  await Promise.all(subs.map(async (s) => {
    const subscription = {
      endpoint: s.endpoint,
      keys: { p256dh: s.p256dh, auth: s.auth },
    };
    try {
      await webpush.sendNotification(subscription, payload);
      console.log('[push-send] ✓ доставлено для подписки id=' + s.id);
      sent++;
    } catch (err: any) {
      failed++;
      const msg = err && (err.message || err.body || String(err)) || 'unknown';
      const code = err && err.statusCode;
      console.error('[push-send] ✗ ошибка для подписки id=' + s.id + ' code=' + code + ' msg=' + msg);
      errors.push('id=' + s.id + ': ' + (code ? code + ' ' : '') + msg);
      if (code === 404 || code === 410) {
        await sbAdmin.from('push_subscriptions').delete().eq('id', s.id);
      }
    }
  }));

  return json({ ok: sent > 0, sent, failed, errors });
});

function json(obj: unknown, status = 200) {
  return new Response(JSON.stringify(obj), {
    status,
    headers: { 'Content-Type': 'application/json', ...corsHeaders },
  });
}
