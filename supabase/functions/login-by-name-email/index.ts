// Edge Function: login-by-name-email
// Простой вход по имени+email для интенсива.
// Если в БД есть профиль с этим email и full_name (без учёта регистра),
// выписываем JWT — точно так же как в verify-login-code.
// БЕЗ кодов, БЕЗ писем — мгновенный вход.

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
    'raw',
    enc.encode(JWT_SECRET),
    { name: 'HMAC', hash: 'SHA-256' },
    false,
    ['sign', 'verify']
  );
}

/* Нормализация имени для сравнения: убираем лишние пробелы, нижний регистр, ё→е */
function norm(s: string): string {
  return String(s || '')
    .trim()
    .toLowerCase()
    .replace(/ё/g, 'е')
    .replace(/\s+/g, ' ');
}

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response(null, { status: 204, headers: corsHeaders });
  }

  try {
    const body = await req.json();
    const email = String(body.email || '').trim().toLowerCase();
    const fullName = String(body.full_name || '').trim();

    if (!email.includes('@') || !fullName) {
      return new Response(JSON.stringify({ error: 'Нужны email и имя' }), {
        status: 400,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    const supabase = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);

    const { data: profile, error: pErr } = await supabase
      .from('profiles')
      .select('id, full_name, role')
      .eq('email', email)
      .maybeSingle();

    if (pErr) throw pErr;

    if (!profile) {
      return new Response(JSON.stringify({
        error: 'Учётная запись с таким e-mail не найдена. Проверьте у учителя, что вас добавили в список интенсива.'
      }), {
        status: 404,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    if (norm(profile.full_name || '') !== norm(fullName)) {
      return new Response(JSON.stringify({
        error: 'Имя не совпадает с тем, что у учителя в списке. Попробуйте ввести как в журнале (без сокращений).'
      }), {
        status: 401,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    // Подписываем JWT
    const key = await getJwtKey();
    const now = Math.floor(Date.now() / 1000);
    const exp = now + 60 * 60 * 24 * 7; // 7 дней
    const accessToken = await createJwt(
      { alg: 'HS256', typ: 'JWT' },
      {
        sub: profile.id,
        email,
        role: 'authenticated',
        aud: 'authenticated',
        iss: SUPABASE_URL + '/auth/v1',
        iat: now,
        exp,
        app_metadata: { provider: 'name-email' },
        user_metadata: { full_name: profile.full_name },
      },
      key
    );

    return new Response(
      JSON.stringify({
        access_token: accessToken,
        token_type: 'bearer',
        expires_in: 60 * 60 * 24 * 7,
        user: { id: profile.id, email, full_name: profile.full_name },
      }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );
  } catch (e: any) {
    console.error('login-by-name-email error:', e);
    return new Response(JSON.stringify({ error: String(e?.message || e) }), {
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  }
});
