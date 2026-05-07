// Edge Function: verify-login-code
// Принимает email + код, проверяет в auth_codes, создаёт пользователя/профиль (если нет),
// генерирует JWT (HS256) с тем же секретом, что Supabase Auth.
// Возвращает access_token, который PostgREST принимает.

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { create as createJwt } from 'https://deno.land/x/djwt@v3.0.1/mod.ts';

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
const SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const JWT_SECRET = Deno.env.get('PROJECT_JWT_SECRET')!; // нужно вручную добавить в Secrets

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

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    const body = await req.json();
    const email = String(body.email || '').trim().toLowerCase();
    const code = String(body.code || '').trim();

    if (!email || !code) {
      return new Response(JSON.stringify({ error: 'Нужны email и код' }), {
        status: 400,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    const supabase = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);

    // 1. Проверяем код
    const { data: codes, error: codeErr } = await supabase
      .from('auth_codes')
      .select('*')
      .eq('email', email)
      .eq('code', code)
      .eq('used', false)
      .gte('expires_at', new Date().toISOString())
      .order('created_at', { ascending: false })
      .limit(1);

    if (codeErr) throw codeErr;
    if (!codes || !codes.length) {
      return new Response(JSON.stringify({ error: 'Неверный или просроченный код' }), {
        status: 401,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    // 2. Помечаем код использованным
    await supabase
      .from('auth_codes')
      .update({ used: true })
      .eq('email', email)
      .eq('code', code);

    // 3. Ищем профиль по email
    let userId: string;
    const { data: existingProfile } = await supabase
      .from('profiles')
      .select('id, role')
      .eq('email', email)
      .maybeSingle();

    if (existingProfile) {
      userId = existingProfile.id;
    } else {
      // Создаём auth-пользователя. Триггер trg_auth_user_created автоматически
      // создаст соответствующий profile (role='student').
      const { data: newUser, error: createErr } = await supabase.auth.admin.createUser({
        email,
        email_confirm: true,
      });

      if (createErr) {
        // Возможно пользователь уже есть в auth.users без profile.
        // Попробуем найти его через admin API.
        if (String(createErr.message || '').toLowerCase().includes('already')) {
          const { data: list } = await supabase.auth.admin.listUsers({ page: 1, perPage: 200 });
          const found = list.users.find((u: any) => u.email === email);
          if (!found) throw createErr;
          userId = found.id;
        } else {
          console.error('createUser error:', createErr);
          throw createErr;
        }
      } else {
        userId = newUser.user!.id;
      }

      // На случай, если триггер не сработал — пробуем upsert профиля.
      // Не перетираем существующий (ignoreDuplicates).
      await supabase.from('profiles').upsert(
        {
          id: userId,
          email,
          full_name: email.split('@')[0],
          role: 'student',
        },
        { onConflict: 'id', ignoreDuplicates: true }
      );
    }

    // 4. Подписываем JWT (как Supabase Auth)
    const key = await getJwtKey();
    const now = Math.floor(Date.now() / 1000);
    const exp = now + 60 * 60 * 24 * 7; // 7 дней
    const accessToken = await createJwt(
      { alg: 'HS256', typ: 'JWT' },
      {
        sub: userId,
        email,
        role: 'authenticated',
        aud: 'authenticated',
        iss: SUPABASE_URL + '/auth/v1',
        iat: now,
        exp,
        app_metadata: { provider: 'email' },
        user_metadata: {},
      },
      key
    );

    return new Response(
      JSON.stringify({
        access_token: accessToken,
        token_type: 'bearer',
        expires_in: 60 * 60 * 24 * 7,
        user: { id: userId, email },
      }),
      {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      }
    );
  } catch (e: any) {
    console.error('verify error:', e);
    return new Response(JSON.stringify({ error: String(e?.message || e) }), {
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  }
});
