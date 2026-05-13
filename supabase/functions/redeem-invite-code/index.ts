// Edge Function: redeem-invite-code
//
// Принимает JSON: { code: string, full_name: string }
// 1. Проверяет валидность кода (активен, не просрочен, не превышен лимит)
// 2. Создаёт auth.users + profile (через service-role API в обход RLS)
// 3. Инкрементирует used_count
// 4. Возвращает JWT для немедленного логина
//
// Поведение анти-дубль: если в этом коде уже есть профиль с таким же
// full_name — возвращаем существующий (ученик пересоздал сессию, не плодим).

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

function norm(s: string): string {
  return String(s || '').trim().toLowerCase().replace(/ё/g, 'е').replace(/\s+/g, ' ');
}

serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response(null, { status: 204, headers: corsHeaders });

  try {
    const body = await req.json();
    const code = String(body.code || '').trim().toUpperCase();
    const fullName = String(body.full_name || '').trim();

    if (!code) return json({ error: 'Введи код приглашения' }, 400);
    if (!fullName) return json({ error: 'Введи своё имя' }, 400);

    const sb = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);

    // 1. Найти и провалидировать код
    const { data: invite, error: iErr } = await sb
      .from('invite_codes')
      .select('*')
      .eq('code', code)
      .eq('is_active', true)
      .maybeSingle();
    if (iErr) throw iErr;
    if (!invite) return json({ error: 'Код не найден или отозван' }, 404);
    if (invite.expires_at && new Date(invite.expires_at) < new Date()) {
      return json({ error: 'Срок действия кода истёк' }, 403);
    }
    if (invite.max_uses != null && invite.used_count >= invite.max_uses) {
      return json({ error: 'Все места по коду уже заняты' }, 403);
    }

    // 2. Дубликат? Ищем профиль с этим именем (без регистра, ё/е)
    const fullNameNorm = norm(fullName);
    const { data: existing } = await sb
      .from('profiles')
      .select('id, full_name, role')
      .eq('role', 'student')
      .ilike('full_name', fullName);
    let profileId: string | null = null;
    if (existing && existing.length) {
      for (const p of existing) {
        if (norm(p.full_name || '') === fullNameNorm) { profileId = p.id; break; }
      }
    }

    // 3. Создать профиль если новый
    if (!profileId) {
      const fakeEmail = `invite-${crypto.randomUUID()}@invite.zebrus.online`;
      const { data: authUser, error: aErr } = await sb.auth.admin.createUser({
        email: fakeEmail,
        email_confirm: true,
      });
      if (aErr) throw aErr;
      const uid = authUser.user.id;
      const { error: pErr } = await sb.from('profiles').insert({
        id: uid,
        email: fakeEmail,
        full_name: fullName,
        role: 'student',
        s_type: 'гость',
        s_status: 'active',
      });
      if (pErr) throw pErr;
      profileId = uid;
      // Инкремент used_count
      await sb.from('invite_codes')
        .update({ used_count: (invite.used_count || 0) + 1 })
        .eq('id', invite.id);
    }

    // 4. Выписываем JWT
    const key = await getJwtKey();
    const now = Math.floor(Date.now() / 1000);
    const exp = now + 60 * 60 * 24 * 7;
    const access = await createJwt(
      { alg: 'HS256', typ: 'JWT' },
      {
        sub: profileId, email: '',
        role: 'authenticated', aud: 'authenticated',
        iss: SUPABASE_URL + '/auth/v1', iat: now, exp,
        app_metadata: { provider: 'invite-code' },
        user_metadata: { full_name: fullName, invite_code: code },
      }, key
    );

    return json({
      access_token: access, token_type: 'bearer',
      expires_in: 60 * 60 * 24 * 7,
      user: { id: profileId, full_name: fullName }
    });
  } catch (e: any) {
    console.error('redeem-invite-code error:', e);
    return json({ error: String(e?.message || e) }, 500);
  }
});

function json(obj: unknown, status = 200) {
  return new Response(JSON.stringify(obj), {
    status, headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}
