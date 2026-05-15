// Edge Function: upload-essay-photo
// Принимает base64-картинку и кладёт в Storage essays/<user_id>/<filename>.
// Используется как fallback на мобиле в РФ, где:
//   1) прямой *.supabase.co заблокирован РКН
//   2) PHP-прокси на reg.ru не поддерживает /storage/v1 нормально
// Edge Function ходит к Storage напрямую через Deno-рантайм Supabase.

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
    const requesterId: string | undefined = body.requester_id;
    const filename: string = String(body.filename || 'photo.jpg');
    const contentType: string = String(body.content_type || 'image/jpeg');
    const base64: string = String(body.base64 || '');

    if (!requesterId) {
      return new Response(JSON.stringify({ error: 'requester_id required' }), {
        status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }
    if (!base64) {
      return new Response(JSON.stringify({ error: 'base64 пустой' }), {
        status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    // Декодируем base64
    const bin = atob(base64);
    const bytes = new Uint8Array(bin.length);
    for (let i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i);

    // Лимит 8 МБ — больше Supabase Edge Function всё равно не примет в JSON-боди
    if (bytes.length > 8 * 1024 * 1024) {
      return new Response(JSON.stringify({ error: 'Файл больше 8 МБ' }), {
        status: 413, headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    const supabase = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);

    // Проверяем, что requester существует (любой залогиненный)
    const { data: requester } = await supabase
      .from('profiles')
      .select('id, role')
      .eq('id', requesterId)
      .maybeSingle();

    if (!requester) {
      return new Response(JSON.stringify({ error: 'Профиль автора не найден' }), {
        status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    // Готовим путь и заливаем
    const ext = (filename.match(/\.([a-zA-Z0-9]{1,10})$/) || ['', 'jpg'])[1].toLowerCase();
    const path = requesterId + '/' + Date.now() + '_' +
      Math.random().toString(36).slice(2, 8) + '.' + ext;

    const { error: upErr } = await supabase.storage
      .from('essays')
      .upload(path, bytes, { contentType, upsert: true });

    if (upErr) {
      return new Response(JSON.stringify({ error: 'Storage: ' + upErr.message }), {
        status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    const publicUrl = SUPABASE_URL + '/storage/v1/object/public/essays/' + path;

    return new Response(JSON.stringify({ ok: true, url: publicUrl, path }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  } catch (e: any) {
    return new Response(JSON.stringify({ error: String(e?.message || e) }), {
      status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  }
});
