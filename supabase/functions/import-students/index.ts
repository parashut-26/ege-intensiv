// Edge Function: import-students
// Принимает список учеников {full_name, email} и токен учителя.
// Создаёт auth-пользователей через admin API + обновляет full_name в profiles.
// Возвращает список с результатом по каждому.

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
const SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

interface StudentRow {
  full_name: string;
  email: string;
}

interface ResultRow {
  email: string;
  full_name: string;
  status: 'created' | 'updated' | 'error';
  message?: string;
}

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response(null, { status: 204, headers: corsHeaders });
  }

  try {
    const body = await req.json();
    const students: StudentRow[] = Array.isArray(body.students) ? body.students : [];
    const requesterId: string | undefined = body.requester_id;

    if (!students.length) {
      return new Response(JSON.stringify({ error: 'Нужен непустой список students[]' }), {
        status: 400,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }
    if (!requesterId) {
      return new Response(JSON.stringify({ error: 'Нужен requester_id' }), {
        status: 400,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    const supabase = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);

    // Проверяем, что requester — учитель или куратор
    const { data: requester, error: rErr } = await supabase
      .from('profiles')
      .select('id, role')
      .eq('id', requesterId)
      .maybeSingle();

    if (rErr || !requester) {
      return new Response(JSON.stringify({ error: 'Профиль автора не найден' }), {
        status: 401,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }
    if (requester.role !== 'teacher' && requester.role !== 'curator') {
      return new Response(JSON.stringify({ error: 'Импорт доступен только учителю/куратору' }), {
        status: 403,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    const results: ResultRow[] = [];

    for (const s of students) {
      const email = String(s.email || '').trim().toLowerCase();
      const fullName = String(s.full_name || '').trim();
      if (!email.includes('@') || !fullName) {
        results.push({ email, full_name: fullName, status: 'error', message: 'Неверный email или имя' });
        continue;
      }

      try {
        // Сначала ищем существующий профиль
        const { data: existing } = await supabase
          .from('profiles')
          .select('id, full_name')
          .eq('email', email)
          .maybeSingle();

        if (existing) {
          // Обновляем имя если оно отличается
          if (existing.full_name !== fullName) {
            await supabase.from('profiles').update({ full_name: fullName }).eq('id', existing.id);
          }
          results.push({ email, full_name: fullName, status: 'updated' });
          continue;
        }

        // Создаём auth-пользователя — триггер сам создаст профиль с role='student'
        const { data: newUser, error: createErr } = await supabase.auth.admin.createUser({
          email,
          email_confirm: true,
        });

        if (createErr) {
          if (String(createErr.message || '').toLowerCase().includes('already')) {
            // Юзер есть в auth.users но без профиля — создадим профиль вручную
            const { data: list } = await supabase.auth.admin.listUsers({ page: 1, perPage: 200 });
            const found = list.users.find((u: any) => u.email === email);
            if (found) {
              await supabase.from('profiles').upsert(
                { id: found.id, email, full_name: fullName, role: 'student' },
                { onConflict: 'id' }
              );
              results.push({ email, full_name: fullName, status: 'updated' });
              continue;
            }
          }
          results.push({ email, full_name: fullName, status: 'error', message: createErr.message });
          continue;
        }

        const userId = newUser.user!.id;
        // Обновляем профиль с правильным именем (триггер мог поставить email префикс)
        await supabase.from('profiles').update({ full_name: fullName }).eq('id', userId);

        results.push({ email, full_name: fullName, status: 'created' });
      } catch (e: any) {
        results.push({ email, full_name: fullName, status: 'error', message: String(e?.message || e) });
      }
    }

    const created = results.filter((r) => r.status === 'created').length;
    const updated = results.filter((r) => r.status === 'updated').length;
    const errors = results.filter((r) => r.status === 'error').length;

    return new Response(
      JSON.stringify({
        ok: true,
        summary: { total: students.length, created, updated, errors },
        results,
      }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );
  } catch (e: any) {
    console.error('import-students error:', e);
    return new Response(JSON.stringify({ error: String(e?.message || e) }), {
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  }
});
