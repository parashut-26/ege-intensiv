// Edge Function: redeem-login-token
//
// Принимает JSON: { token: string (UUID) }
// Валидирует одноразовый токен и возвращает JWT для соответствующего profile_id.
// Токен помечается как использованный (used_at = NOW()).

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { create as createJwt } from 'https://deno.land/x/djwt@v3.0.1/mod.ts';

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
const SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const JWT_SECRET = Deno.env.get('PROJECT_JWT_SECRET')!;

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

async function getJwtKey(): Promise<CryptoKey> {
  const enc = new TextEncoder();
  return await crypto.subtle.importKey(
    'raw', enc.encode(JWT_SECRET),
    { name: 'HMAC', hash: 'SHA-256' },
    false, ['sign', 'verify']
  );
}

serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response(null, { status: 204, headers: corsHeaders });

  try {
    const body = await req.json();
    const token = String(body.token || '').trim();
    if (!/^[0-9a-f-]{36}$/i.test(token)) {
      return json({ error: 'Невалидная ссылка-вход' }, 400);
    }

    const sb = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);

    // 1. Найти токен (без embedded select — у login_tokens две FK к profiles,
    //    PostgREST не может выбрать сам). Загрузим профиль отдельным запросом.
    const { data: tok, error: tErr } = await sb
      .from('login_tokens')
      .select('*')
      .eq('token', token)
      .maybeSingle();
    if (tErr) throw tErr;
    if (!tok) return json({ error: 'Ссылка не найдена. Возможно, учитель её отозвал.' }, 404);
    if (tok.used_at) return json({ error: 'Эта ссылка уже использована. Попроси учителя сгенерировать новую.' }, 403);
    if (tok.expires_at && new Date(tok.expires_at) < new Date()) {
      return json({ error: 'Срок ссылки истёк. Попроси учителя новую.' }, 403);
    }
    const { data: profile, error: pErr } = await sb
      .from('profiles')
      .select('id, email, full_name, role')
      .eq('id', tok.profile_id)
      .maybeSingle();
    if (pErr) throw pErr;
    if (!profile) return json({ error: 'Ученик удалён' }, 404);

    // 2. Помечаем как использованный
    await sb.from('login_tokens')
      .update({ used_at: new Date().toISOString() })
      .eq('token', token);

    // 3. Выписываем JWT
    const key = await getJwtKey();
    const now = Math.floor(Date.now() / 1000);
    const exp = now + 60 * 60 * 24 * 7;
    const access = await createJwt(
      { alg: 'HS256', typ: 'JWT' },
      {
        sub: profile.id, email: profile.email || '',
        role: 'authenticated', aud: 'authenticated',
        iss: SUPABASE_URL + '/auth/v1', iat: now, exp,
        app_metadata: { provider: 'login-token' },
        user_metadata: { full_name: profile.full_name },
      }, key
    );

    return json({
      access_token: access, token_type: 'bearer',
      expires_in: 60 * 60 * 24 * 7,
      user: { id: profile.id, email: profile.email, full_name: profile.full_name }
    });
  } catch (e: any) {
    console.error('redeem-login-token error:', e);
    return json({ error: String(e?.message || e) }, 500);
  }
});

function json(obj: unknown, status = 200) {
  return new Response(JSON.stringify(obj), {
    status, headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}
