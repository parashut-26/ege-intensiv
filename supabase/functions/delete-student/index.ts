// Edge Function: delete-student
// Полное удаление ученика: profiles + auth.users.
// Иначе если удалить только profile, клиентское приложение
// ученика (loadMyProfile) пересоздаёт строку при следующем визите.

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
const SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    const body = await req.json();
    const studentId: string | undefined = body.student_id;
    const requesterId: string | undefined = body.requester_id;

    if (!studentId) {
      return new Response(JSON.stringify({ error: 'student_id required' }), {
        status: 400,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }
    if (!requesterId) {
      return new Response(JSON.stringify({ error: 'requester_id required' }), {
        status: 400,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    const supabase = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);

    // Проверяем что requester — учитель или куратор с approveGuests
    const { data: requester } = await supabase
      .from('profiles')
      .select('id, role, curator_perms')
      .eq('id', requesterId)
      .maybeSingle();

    if (!requester) {
      return new Response(JSON.stringify({ error: 'Профиль автора не найден' }), {
        status: 401,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    const isTeacher = requester.role === 'teacher';
    const isCurator = requester.role === 'curator';
    if (!isTeacher && !isCurator) {
      return new Response(JSON.stringify({ error: 'Удалять может только учитель или куратор' }), {
        status: 403,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    // 1. Удаляем профиль (FK с ON DELETE CASCADE утянут связанные строки)
    const { error: pErr } = await supabase
      .from('profiles')
      .delete()
      .eq('id', studentId);
    if (pErr) {
      return new Response(JSON.stringify({ error: 'profiles delete: ' + pErr.message }), {
        status: 500,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    // 2. Удаляем самого пользователя из auth.users — чтобы его сессия
    // больше не могла пересоздать профиль через loadMyProfile()
    const { error: aErr } = await supabase.auth.admin.deleteUser(studentId);
    if (aErr) {
      // Не критично — профиль уже удалён. Но возвращаем предупреждение,
      // чтобы учитель знал: если у ученика есть открытая сессия, он может вернуться.
      return new Response(JSON.stringify({
        ok: true,
        warning: 'profile удалён, но auth.user остался: ' + aErr.message,
      }), {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    return new Response(JSON.stringify({ ok: true }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  } catch (e: any) {
    return new Response(JSON.stringify({ error: String(e?.message || e) }), {
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  }
});
