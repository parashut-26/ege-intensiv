// Edge Function: generate-explanation
//
// Принимает JSON: { question_text: string, correct_answer: string, task_num?: number }
// Дёргает YandexGPT-lite и возвращает короткое пояснение для ученика.
//
// Используется кнопкой «🤖 AI» в редакторе варианта и в редакторе тренажёра.
// Учитель может сгенерировать черновик, потом отредактировать и сохранить.
//
// Secrets (выставить через Supabase Dashboard → Edge Functions → Secrets):
//   YANDEX_GPT_API_KEY  — API-ключ сервисного аккаунта Yandex Cloud
//   YANDEX_FOLDER_ID    — folder-id каталога Yandex Cloud (где доступен YandexGPT)

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';

const YGPT_API_KEY  = Deno.env.get('YANDEX_GPT_API_KEY')!;
const YGPT_FOLDER   = Deno.env.get('YANDEX_FOLDER_ID')!;
const YGPT_ENDPOINT = 'https://llm.api.cloud.yandex.net/foundationModels/v1/completion';
/* yandexgpt/rc — release-candidate большой модели (YandexGPT 5.1 Pro).
   Дороже чем -lite, но пояснения для ЕГЭ заметно осмысленнее.
   Если захочется удешевить — поменяй на 'yandexgpt-lite/latest'. */
const YGPT_MODEL    = 'gpt://' + YGPT_FOLDER + '/yandexgpt/rc';

const corsHeaders = {
  'Access-Control-Allow-Origin':  '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

const SYSTEM_PROMPT = [
  'Ты помощник учителя русского языка для ЕГЭ.',
  'Тебе дают формулировку задания и правильный ответ.',
  'Напиши КРАТКОЕ (3-6 предложений) пояснение для ученика 11 класса:',
  'какое правило применяется, как его узнать, почему ответ именно такой.',
  'Пиши простым языком, без воды, без приветствий и без вступлений типа «Конечно, объясню».',
  'Не используй markdown, не используй жирный/курсив, только обычный текст с переносами строк.',
  'Если в задании несколько подпунктов или несколько правильных вариантов — кратко разбери каждый.',
].join(' ');

serve(async (req) => {
  if(req.method === 'OPTIONS'){
    return new Response(null, { status: 204, headers: corsHeaders });
  }

  try {
    if(!YGPT_API_KEY || !YGPT_FOLDER){
      return json({ error: 'YANDEX_GPT_API_KEY / YANDEX_FOLDER_ID не настроены в Supabase Secrets' }, 500);
    }

    const body = await req.json();
    const qText = String(body.question_text || '').trim();
    const ans   = String(body.correct_answer || '').trim();
    const num   = body.task_num != null ? Number(body.task_num) : null;

    if(!qText){
      return json({ error: 'Не передан question_text' }, 400);
    }
    if(!ans){
      return json({ error: 'Не передан correct_answer (без правильного ответа объяснить нечего)' }, 400);
    }

    /* Соберём user-prompt. Номер задания — подсказка модели о теме (например,
       «5» = паронимы, «6» = лексические нормы и т.п.). Без жёсткой раскладки —
       пусть модель сама определяет по контексту, но мы даём шорткат. */
    const userPrompt = (num != null ? '(Задание №' + num + ' ЕГЭ)\n' : '') +
      'Формулировка задания:\n' + qText + '\n\n' +
      'Правильный ответ: ' + ans + '\n\n' +
      'Напиши пояснение для ученика.';

    const ygptPayload = {
      modelUri: YGPT_MODEL,
      completionOptions: {
        stream: false,
        temperature: 0.2,
        maxTokens: 600,
      },
      messages: [
        { role: 'system', text: SYSTEM_PROMPT },
        { role: 'user',   text: userPrompt },
      ],
    };

    const r = await fetch(YGPT_ENDPOINT, {
      method:  'POST',
      headers: {
        'Authorization': 'Api-Key ' + YGPT_API_KEY,
        'Content-Type':  'application/json',
        'x-folder-id':   YGPT_FOLDER,
      },
      body: JSON.stringify(ygptPayload),
    });

    const txt = await r.text();
    if(!r.ok){
      console.error('[ygpt] HTTP', r.status, txt);
      return json({ error: 'YandexGPT вернул ' + r.status + ': ' + txt.slice(0, 500) }, 502);
    }

    let data: any;
    try { data = JSON.parse(txt); }
    catch(_){
      return json({ error: 'YandexGPT вернул не-JSON: ' + txt.slice(0, 300) }, 502);
    }

    const alt = data && data.result && data.result.alternatives && data.result.alternatives[0];
    const text = alt && alt.message && alt.message.text ? String(alt.message.text).trim() : '';
    if(!text){
      return json({ error: 'Модель не вернула текст', raw: data }, 502);
    }

    return json({ explanation: text });
  } catch(e: any){
    console.error('[generate-explanation] error:', e);
    return json({ error: String(e && e.message || e) }, 500);
  }
});

function json(obj: unknown, status = 200){
  return new Response(JSON.stringify(obj), {
    status, headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}
