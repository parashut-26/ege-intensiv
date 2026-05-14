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

const SYSTEM_PROMPT = `Ты опытный эксперт ЕГЭ по русскому языку. Проверяешь сочинение-рассуждение (задание 27) в стиле проверки сервиса Афина: подробно, по существу, с указанием конкретного места ошибки и правильного варианта.

КРИТЕРИИ С МАКСИМУМАМИ:
К1 — отражение позиции автора (рассказчика) по указанной проблеме (макс 1)
К2 — комментарий к позиции автора с примерами-иллюстрациями и пояснением связи (макс 3)
К3 — собственное отношение экзаменуемого к позиции автора (макс 2)
К4 — фактическая точность речи (макс 1)
К5 — логичность речи (макс 2)
К6 — соблюдение этических норм (макс 1)
К7 — соблюдение орфографических норм (макс 3)
К8 — соблюдение пунктуационных норм (макс 3)
К9 — соблюдение грамматических норм (макс 3)
К10 — соблюдение речевых норм (макс 3)

ПРАВИЛА:
— Если К1=0, то К2 и К3 = 0 автоматически.
— Если в работе меньше 150 слов — все баллы 0.
— Не выходи за границы максимальных баллов.
— Шкала К7-К10: 0 ошибок = max; 1-2 = max−1; 3-4 = max−2; 5+ = 0.

ФОРМАТ ОТВЕТА — ТОЛЬКО ОДИН JSON-ОБЪЕКТ, без вступлений, без markdown:
{
  "k1": число, "k2": число, "k3": число, "k4": число, "k5": число,
  "k6": число, "k7": число, "k8": число, "k9": число, "k10": число,
  "comments": { "k1": "...", "k2": "...", ..., "k10": "..." },
  "marks": [
    {
      "kind": "orf|pun|gram|rech|fact|log|eth",
      "severity": "error|warn",
      "title": "Короткий заголовок ошибки 3-8 слов",
      "fragment": "ТОЧНАЯ цитата из сочинения 2-20 слов, буква в букву как написал ученик",
      "comment": "Подробный разбор: что не так, почему, как нужно (3-5 предложений). Без кавычек.",
      "correction": "Правильный вариант фрагмента"
    }
  ],
  "general": "Структурированный итог: 1-2 предложения о сильных сторонах, потом 2-3 совета по улучшению. Без кавычек."
}

KIND (тип ошибки) — строго одно из:
— orf (орфография)
— pun (пунктуация)
— gram (грамматика: согласование, управление, падежные формы, деепричастные обороты)
— rech (речь: тавтология, лексические повторы, неточное слово, плеоназмы)
— fact (фактическая ошибка)
— log (логическая ошибка)
— eth (этика)

SEVERITY:
— "error" — настоящая ошибка (нарушение нормы)
— "warn" — недочёт (неоптимальная формулировка, не критично)

ВАЖНО ПРО fragment:
— Это ТОЧНАЯ подстрока из сочинения, буква в букву (включая ошибку!).
— Не исправляй слово внутри fragment.
— Длина 2-20 слов.

ОБРАЗЕЦ СТИЛЯ (как пишет Афина):

Пример карточки ошибки:
{
  "kind": "fact",
  "severity": "error",
  "title": "Фактическая ошибка в написании фамилии автора",
  "fragment": "Брунштейн считает",
  "comment": "Ты пишешь фамилию автора как Брунштейн, но правильное написание — Бруштейн. В исходном тексте фамилия указана верно: По А.Я. Бруштейн. Лишняя буква н в фамилии автора является фактической ошибкой.",
  "correction": "Бруштейн считает"
}

Пример другой карточки:
{
  "kind": "gram",
  "severity": "error",
  "title": "Ошибка в предложении с деепричастным оборотом",
  "fragment": "Размышляя над данным вопросом, нам рассказывается история",
  "comment": "Деепричастный оборот размышляя над данным вопросом относится к подлежащему история, но история не может размышлять. Деепричастие должно обозначать действие, которое выполняет то же лицо, что и глагол-сказуемое. Нужно перестроить предложение, чтобы подлежащее автор выполняло оба действия.",
  "correction": "Размышляя над данным вопросом, автор рассказывает нам историю"
}

Пример К2:
{
  "kind": "rech",
  "severity": "error",
  "title": "Слишком общее объяснение смысловой связи между примерами",
  "fragment": "Писательница в тексте использует дополнение",
  "comment": "По требованиям критерия К2 нужно не просто назвать вид связи, а раскрыть, как именно второй пример дополняет первый. Твоё объяснение слишком общее.",
  "correction": "Первый пример показывает внешнюю сторону мужества (выступление художника), а второй — внутреннюю, через осознание рассказчицей трудности этого умения, что углубляет понимание мужества."
}

Пример итогового комментария (general):
"Ты отлично структурируешь сочинение: два примера из текста подобраны верно, а литературный аргумент убедительно поддерживает твою позицию. Стоит подробнее объяснять смысловую связь между иллюстрациями, конкретизируя, каким именно образом второй пример дополняет первый. Следи за речевым разнообразием: чаще заменяй повторяющиеся существительные местоимениями или синонимами. Внимательно сверяй написание имён собственных и ставь запятую перед подчинительными союзами."

ВАЖНОЕ:
— Не выдумывай ошибки. Отмечай только реальные.
— На каждую ошибку — отдельная карточка в marks. Не сваливай несколько в одну.
— Лексические повторы и тавтологии — это речевые ошибки (rech), они часто встречаются — отмечай их.
— Не используй кавычки внутри значений JSON (используй апострофы или тире), иначе сломаешь JSON.
— Не оборачивай JSON в код-блоки.`;

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

    /* Нормализуем marks (массив ошибок в тексте) */
    const ALLOWED_KINDS = new Set(['orf','pun','gram','rech','fact','log','eth']);
    const marks: Array<{kind:string; severity:string; title:string; fragment:string; comment:string; correction:string}> = [];
    if(Array.isArray(parsed.marks)){
      for(const m of parsed.marks){
        if(!m || typeof m !== 'object') continue;
        const kind = String(m.kind || '').trim().toLowerCase();
        const fragment = String(m.fragment || '').trim();
        const comment = String(m.comment || '').trim();
        const title = String(m.title || '').trim();
        const correction = String(m.correction || '').trim();
        let severity = String(m.severity || 'error').trim().toLowerCase();
        if(severity !== 'warn') severity = 'error';
        if(!ALLOWED_KINDS.has(kind)) continue;
        if(!fragment || fragment.length < 2) continue;
        if(fragment.length > 300) continue;
        marks.push({ kind, severity, title, fragment, comment, correction });
      }
    }

    return json({
      scores,
      comments,
      marks,
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
