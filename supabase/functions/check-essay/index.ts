// Edge Function: check-essay
//
// Принимает JSON: { essay_text: string, source_text?: string, student_name?: string }
// Возвращает JSON: { scores: {k1..k10}, comments: {k1..k10}, general: string }
//
// Используется кнопкой «🤖 AI-черновик проверки» в учительском modalEssayReview.
// Учитель видит черновик, может править и сохранить как свою оценку.
//
// Secrets (Supabase Dashboard → Edge Functions → Manage secrets):
//   YANDEX_GPT_API_KEY  — API-ключ сервисного аккаунта Yandex Cloud
//   YANDEX_FOLDER_ID    — folder-id каталога Yandex Cloud

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';

const YGPT_API_KEY  = Deno.env.get('YANDEX_GPT_API_KEY')!;
const YGPT_FOLDER   = Deno.env.get('YANDEX_FOLDER_ID')!;
const YGPT_ENDPOINT = 'https://llm.api.cloud.yandex.net/foundationModels/v1/completion';
const YGPT_MODEL    = 'gpt://' + YGPT_FOLDER + '/yandexgpt/rc';

const corsHeaders = {
  'Access-Control-Allow-Origin':  '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

/* Максимальные баллы по платформе ZebRus (соответствуют K_LIMITS в index.html):
   k1=1, k2=3, k3=2, k4=1, k5=2, k6=1, k7=3, k8=3, k9=3, k10=3 = 22 */
const K_MAX: Record<string, number> = {
  k1: 1, k2: 3, k3: 2, k4: 1, k5: 2, k6: 1, k7: 3, k8: 3, k9: 3, k10: 3,
};

const SYSTEM_PROMPT = `Ты опытный эксперт ЕГЭ по русскому языку, проверяешь сочинения по тексту (задание 27).
Оцени работу по 10 критериям К1-К10 с такими максимумами:

К1 — формулировка проблем исходного текста (макс 1 балл)
К2 — комментарий к проблеме с примерами-иллюстрациями и пояснением (макс 3 балла)
К3 — отражение позиции автора (макс 2 балла)
К4 — отношение к позиции автора и обоснование (макс 1 балл)
К5 — смысловая цельность, речевая связность, последовательность (макс 2 балла)
К6 — точность и выразительность речи (макс 1 балл)
К7 — соблюдение орфографических норм (макс 3 балла)
К8 — соблюдение пунктуационных норм (макс 3 балла)
К9 — соблюдение языковых норм / грамматика (макс 3 балла)
К10 — соблюдение речевых норм (макс 3 балла)

Правила:
— Если К1=0 (проблема не сформулирована или сформулирована неверно), то К2 и К3 = 0 автоматически.
— Если в работе меньше 150 слов — все баллы 0.
— Объём 150-300 слов — К7-К12 действуют со смягчением (модель должна это учесть, но не обнулять).
— Не выходи за границы максимальных баллов.

Верни ОТВЕТ СТРОГО в формате JSON без вступлений, без markdown, без кодовых блоков. Только сам JSON-объект:
{
  "k1": число,
  "k2": число,
  "k3": число,
  "k4": число,
  "k5": число,
  "k6": число,
  "k7": число,
  "k8": число,
  "k9": число,
  "k10": число,
  "comments": {
    "k1": "1-2 предложения: что именно сформулировано или почему ноль",
    "k2": "1-2 предложения: какие примеры приведены, есть ли пояснение и связь",
    "k3": "1-2 предложения: ясна ли авторская позиция",
    "k4": "1-2 предложения: выражено ли отношение и есть ли обоснование",
    "k5": "1-2 предложения: есть ли логические разрывы",
    "k6": "1-2 предложения: разнообразие лексики, точность словоупотребления",
    "k7": "1-2 предложения: примеры орфографических ошибок",
    "k8": "1-2 предложения: примеры пунктуационных ошибок",
    "k9": "1-2 предложения: грамматические ошибки (согласование, управление)",
    "k10": "1-2 предложения: речевые ошибки, тавтологии, плеоназмы"
  },
  "general": "2-4 предложения общего впечатления для ученика — что получилось хорошо, над чем работать."
}

Комментарии — на русском, для ученика 11 класса. Без markdown. В комментариях НЕ ИСПОЛЬЗУЙ кавычки внутри значений (используй апострофы), иначе сломаешь JSON.`;

serve(async (req) => {
  if(req.method === 'OPTIONS'){
    return new Response(null, { status: 204, headers: corsHeaders });
  }

  try {
    if(!YGPT_API_KEY || !YGPT_FOLDER){
      return json({ error: 'YANDEX_GPT_API_KEY / YANDEX_FOLDER_ID не настроены в Supabase Secrets' }, 500);
    }

    const body = await req.json();
    const essayText  = String(body.essay_text  || '').trim();
    const sourceText = String(body.source_text || '').trim();
    const studentName = String(body.student_name || '').trim();

    if(!essayText){
      return json({ error: 'Не передан essay_text' }, 400);
    }

    const userPrompt = [
      studentName ? 'Ученик: ' + studentName : null,
      sourceText
        ? 'ИСХОДНЫЙ ТЕКСТ (по которому написано сочинение):\n' + sourceText
        : 'Исходный текст не передан — оценивай в основном К3-К10. К1, К2 — общая адекватность формулировки.',
      'СОЧИНЕНИЕ УЧЕНИКА:\n' + essayText,
      'Проверь работу по 10 критериям. Верни JSON в указанном выше формате.',
    ].filter(Boolean).join('\n\n');

    const ygptPayload = {
      modelUri: YGPT_MODEL,
      completionOptions: {
        stream: false,
        temperature: 0.2,
        maxTokens: 3000,
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

    let raw: any;
    try { raw = JSON.parse(txt); }
    catch(_){
      return json({ error: 'YandexGPT вернул не-JSON: ' + txt.slice(0, 300) }, 502);
    }

    const alt = raw && raw.result && raw.result.alternatives && raw.result.alternatives[0];
    const modelText = alt && alt.message && alt.message.text ? String(alt.message.text).trim() : '';
    if(!modelText){
      return json({ error: 'Модель не вернула текст', raw }, 502);
    }

    /* Пытаемся выдернуть JSON-объект из ответа (модель иногда оборачивает в ```json) */
    let parsed: any = null;
    try {
      parsed = JSON.parse(modelText);
    } catch(_){
      const m = modelText.match(/\{[\s\S]*\}/);
      if(m){
        try { parsed = JSON.parse(m[0]); } catch(__){}
      }
    }
    if(!parsed || typeof parsed !== 'object'){
      return json({
        error: 'Модель вернула некорректный JSON',
        model_text: modelText.slice(0, 1000),
      }, 502);
    }

    /* Нормализация: обрезаем баллы по максимумам, убеждаемся что числа целые ≥ 0 */
    const scores: Record<string, number> = {};
    const comments: Record<string, string> = {};
    for(const k of Object.keys(K_MAX)){
      const v = Number(parsed[k]);
      const max = K_MAX[k];
      let n = Number.isFinite(v) ? Math.round(v) : 0;
      if(n < 0) n = 0;
      if(n > max) n = max;
      scores[k] = n;
      comments[k] = parsed.comments && typeof parsed.comments[k] === 'string'
        ? String(parsed.comments[k]).trim()
        : '';
    }
    /* К1=0 → К2,К3=0 (по методике) */
    if(scores.k1 === 0){
      scores.k2 = 0;
      scores.k3 = 0;
    }
    const general = typeof parsed.general === 'string' ? String(parsed.general).trim() : '';
    const total = Object.keys(K_MAX).reduce((s, k) => s + scores[k], 0);

    return json({
      scores,
      comments,
      general,
      total,
      max: Object.keys(K_MAX).reduce((s, k) => s + K_MAX[k], 0),
    });
  } catch(e: any){
    console.error('[check-essay] error:', e);
    return json({ error: String(e && e.message || e) }, 500);
  }
});

function json(obj: unknown, status = 200){
  return new Response(JSON.stringify(obj), {
    status, headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}
