// Edge Function: check-essay
//
// Принимает JSON: {
//   essay_text: string,
//   source_text?: string,
//   student_name?: string,
//   teacher_marks?: [{ kind, criterion, label, fragment, comment, where }]
// }
// Возвращает JSON: { scores: {k1..k10}, comments: {k1..k10}, general: string, marks: [...] }
//
// Используется кнопкой «🤖 AI-черновик проверки» в учительском modalEssayReview.
// Учитель видит черновик, может править и сохранить как свою оценку.
//
// Если переданы teacher_marks (отметки учителя из essay_comments), AI:
//  — учитывает их в баллах К1-К10;
//  — НЕ дублирует в своих marks (возвращает только дополнительные пропущенные ошибки);
//  — упоминает в general («учитель отметил X, я нашёл дополнительно Y»).
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

const SYSTEM_PROMPT = `Ты опытный педагог, эксперт по проверке письменных работ ЕГЭ по русскому языку. Проверяешь сочинение-рассуждение (задание 27) подробно, по существу, с указанием конкретного места ошибки и правильного варианта.

ВАЖНО — ГОЛОС И ОБРАЩЕНИЕ:
— Пиши от лица педагога-эксперта, напрямую к ученику.
— Обращайся на «ты» (не «вы», не «ученик», не безличные конструкции).
— НЕ упоминай «нейросеть», «AI», «робот», «модель», «программа» — ты выступаешь как преподаватель.
— НЕ упоминай «учитель» или «учитель отметил» — даже если в данных переданы предварительные отметки. Пиши единым голосом, как будто это твой собственный анализ.
— Тон: профессиональный, доброжелательный, конкретный. Без снисходительности, без сарказма, без чрезмерной похвалы.

КРИТИЧЕСКОЕ ПРАВИЛО — НИКАКИХ ГАЛЛЮЦИНАЦИЙ И ВЫДУМАННЫХ НЕСООТВЕТСТВИЙ:
— Опирайся СТРОГО на то, что реально передано в инпуте.
— ПРАВИЛО ИМЁН: разрешено упоминать ТОЛЬКО те фамилии, имена, отчества, названия произведений и героев, которые БУКВАЛЬНО присутствуют в инпуте «ИСХОДНЫЙ ТЕКСТ» или «СОЧИНЕНИЕ УЧЕНИКА». Перед тем как написать любую фамилию автора, литературного героя или название произведения — мысленно ПЕРЕЧИТАЙ инпут и убедись, что эта строка там есть. Если её там нет — замени на нейтральное «автор», «автор исходного текста», «писатель», «герой», «произведение». Никаких исключений: даже самые известные классики (любые) запрещены, если их нет в инпуте.
— ОСОБЫЙ ЗАПРЕТ: запрещено утверждать, что ученик «пишет о другом авторе», «о другом произведении», «работа не соответствует заданию», «ты ушёл от темы», «ты разбираешь не тот текст», «приведённый литературный аргумент относится к произведению X». Эти конструкции — индикатор галлюцинации; их не должно быть в ответе никогда.
— Если в инпуте указан ОДИН автор (в исходном тексте), и в сочинении ученика упоминается ТА ЖЕ фамилия — значит ученик пишет по нужному тексту. Не пытайся найти противоречие там, где его нет.
— Если в инпуте есть «ПРЕДВАРИТЕЛЬНЫЕ ОТМЕТКИ» от учителя — это перечень РЕАЛЬНЫХ ошибок, выявленных в работе ученика. Используй ТОЛЬКО эти типы ошибок для выставления баллов К1-К10. Не додумывай дополнительные «несоответствия теме» и т.п. — учитель уже всё разметил.
— По умолчанию исходи из того, что ученик писал по предложенному исходному тексту и в целом справился. Если у тебя нет конкретных доказательств обратного из инпута — НЕ пиши про несоответствие, тему, другого автора.
— Если контекста почти нет, но переданы ПРЕДВАРИТЕЛЬНЫЕ ОТМЕТКИ — пиши общий комментарий на основе именно их (типов и категорий ошибок), без выдуманного содержания.
— Если совсем нечего проверять — лучше верни короткий honest-ответ в general («Для подробной проверки нужен текст сочинения или хотя бы несколько отметок ошибок»), чем сочинять.
— ПРОВЕРКА ПЕРЕД ОТВЕТОМ: прежде чем вернуть JSON, мысленно пробеги по полю general и comments. Для каждой названной фамилии или произведения — найди её в инпуте. Не нашёл — удали или замени на «автор».

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

Пример карточки ошибки (имена-заполнители «Иванов» — не воспринимай как реальные):
{
  "kind": "fact",
  "severity": "error",
  "title": "Фактическая ошибка в написании фамилии автора",
  "fragment": "Иваннов считает",
  "comment": "Ты пишешь фамилию автора как Иваннов, но правильное написание — Иванов. Лишняя буква н в фамилии автора является фактической ошибкой.",
  "correction": "Иванов считает"
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
    /* teacher_marks: массив отметок учителя по этому сочинению. AI должен
       учитывать их в баллах К1-К10, не дублировать в своих marks, упоминать
       в общем комментарии. Формат:
       [{ kind, criterion, label, fragment, comment, where }, ...] */
    const teacherMarks: Array<any> = Array.isArray(body.teacher_marks) ? body.teacher_marks : [];

    /* Режим «по отметкам учителя без текста»: фото-работа, текст не доступен,
       но учитель уже выделил ошибки рамками на фото. AI должен:
       — выставить баллы К1-К10 на основе списка ошибок;
       — НЕ возвращать новые marks (нет текста, чтобы привязать fragment);
       — в general написать связный комментарий ученику от лица педагога.

       Условие: считаем "нет текста" если строка содержит < 80 значимых символов
       (отсекает «(Ученик заявил проблему: ...)\n\n» который раньше включал
       режим). И требуем хоть одной учительской отметки. */
    const cleanEssayText = essayText
      .replace(/^\s*\(Ученик заявил проблему:[\s\S]*?\)\s*/i, '')
      .trim();
    const photoOnlyMode = cleanEssayText.length < 80 && teacherMarks.length > 0;
    if(!essayText && !photoOnlyMode){
      return json({ error: 'Не передан essay_text и нет teacher_marks' }, 400);
    }
    /* === КРИТИЧНО: защита от галлюцинаций при пустом контексте ===
       Прецедент 26.05.2026: у Яны Шелевер фото-сочинение, в БД пусто
       (body_text=0, source_text=0). photoOnlyMode не сработал из-за обёртки
       «(Ученик заявил проблему: …)», AI получил пустоту и придумал шаблонный
       ответ про «службу в армии (К.Я.Ваншенкин)» — топовый эталон из его
       обучающих данных. Защита: если реального текста нет и нет teacher_marks —
       отказываемся работать, не позволяем AI выдумывать. */
    if(cleanEssayText.length < 80 && teacherMarks.length === 0){
      return json({
        error: 'Нечего проверять: текст сочинения не передан, и нет ни одной отметки учителя. Сначала выдели ошибки рамками/выделениями на работе — AI напишет отчёт по ним.'
      }, 400);
    }

    /* Форматируем учительские отметки в читаемый для модели блок.
       ВАЖНО: для ученика это должно выглядеть как единый отчёт педагога —
       без упоминания «учитель отметил», «эта часть уже была», «здесь
       добавляю своё». Поэтому называем блок нейтрально «ПРЕДВАРИТЕЛЬНЫЕ
       ОТМЕТКИ» и явно требуем не упоминать их источник. */
    let teacherBlock = '';
    if(teacherMarks.length){
      const lines = teacherMarks.map((m, i) => {
        const parts = [
          '#' + (i + 1),
          m.criterion ? '[' + m.criterion + ']' : null,
          m.label ? m.label : null,
        ].filter(Boolean).join(' ');
        const where = m.fragment
          ? '«' + String(m.fragment).slice(0, 100) + '»'
          : (m.where || 'без точной привязки');
        const cmt = m.comment ? ' — ' + String(m.comment).slice(0, 300) : '';
        return '  ' + parts + ' · ' + where + cmt;
      }).join('\n');
      teacherBlock =
        'ПРЕДВАРИТЕЛЬНЫЕ ОТМЕТКИ (уже выявлено ' + teacherMarks.length + ' ошибок/недочётов):\n' + lines +
        '\n\nКАК ИХ ИСПОЛЬЗОВАТЬ:\n' +
        '— Учитывай эти ошибки при выставлении баллов К1-К10 (например, пунктуационная ошибка влияет на К8).\n' +
        '— НЕ ДУБЛИРУЙ их в своём массиве marks — они уже зафиксированы и будут показаны ученику отдельно.\n' +
        '— В поле marks возвращай ТОЛЬКО НОВЫЕ ошибки, которых нет в списке выше.\n' +
        '— В поле general пиши единый связный комментарий ученику (на «ты», от лица педагога). НЕ говори «эти ошибки уже отмечены», «учитель отметил», «я нашёл дополнительно» — для ученика это всё ТВОЙ комментарий. Опирайся на все ошибки (и эти, и новые) при формулировке советов: «обрати внимание на пунктуацию перед союзом «а», у тебя это встречается несколько раз», «следи за повторами», и т.п.';
    }

    const userPrompt = [
      studentName ? 'Ученик: ' + studentName : null,
      sourceText
        ? 'ИСХОДНЫЙ ТЕКСТ (по которому написано сочинение):\n' + sourceText
        : 'Исходный текст не передан — оценивай в основном К3-К10. К1, К2 — общая адекватность формулировки.',
      photoOnlyMode
        ? 'РАБОТА УЧЕНИКА В ФОРМАТЕ ФОТО — текст сочинения не распознан, для оценки опирайся ТОЛЬКО на список отмеченных ошибок ниже.'
        : 'СОЧИНЕНИЕ УЧЕНИКА:\n' + essayText,
      teacherBlock || null,
      photoOnlyMode
        ? 'Так как текста сочинения у тебя нет, верни:\n' +
          '— scores (К1-К10) — рассчитай по списку отмеченных ошибок (например 3+ орфографических → К7=0; 1-2 пунктуационных → К8=2; и т.д.);\n' +
          '— comments по К1-К10 — кратко поясни каждый балл (одно предложение);\n' +
          '— marks: ВСЕГДА пустой массив [] — fragment привязать не к чему;\n' +
          '— general — связный комментарий ученику от лица педагога, на «ты», обобщающий все отмеченные ошибки и дающий 2-3 совета по улучшению.'
        : 'Проверь работу по 10 критериям. Верни JSON в указанном выше формате.',
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

    /* === ПОСТ-ОБРАБОТКА ПРОТИВ ГАЛЛЮЦИНАЦИЙ ИМЁН ===
       Прецедент 26.05.2026 (повторяющийся): YandexGPT при любом сочинении
       короче среднего автоматически выдаёт шаблон «о службе в армии (К.Я.
       Ваншенкин)» / «В.Г.Распутин» / «А.Я.Бруштейн» — это запечатлённые
       в обучающих данных топовые эталоны сочинений ЕГЭ. Никакой промпт
       это не лечит — модель упорно их пишет. Поэтому фильтруем выход:
       любую конструкцию вида «И.О. Фамилия», которой НЕТ в инпуте, режем
       и заменяем на нейтральное «автор». */
    const inputCorpus = (sourceText + ' ' + essayText + ' ' + studentName).toLowerCase();
    function scrubHallucinatedNames(text: string): string {
      if(!text || typeof text !== 'string') return text;
      // Шаблон: 1-3 инициала + фамилия (с пробелами или без). Примеры:
      //   "В.Г. Распутин", "К. Я. Ваншенкин", "А.Я.Бруштейн", "Ф.М.Достоевского"
      let out = text.replace(
        /(?:[А-ЯЁ]\.\s*){1,3}[А-ЯЁ][а-яё]{2,}(?:а|ой|у|ом|е|ы)?/g,
        (match) => {
          const parts = match.trim().split(/[\s.]+/).filter(Boolean);
          const surname = parts[parts.length - 1] || '';
          // Основа фамилии — первые 5 символов в нижнем регистре, чтобы
          // покрыть склонения (Распутин/Распутина/Распутину).
          const stem = surname.toLowerCase().slice(0, Math.min(5, surname.length));
          if(stem.length >= 3 && inputCorpus.includes(stem)) return match;
          return 'автор';
        }
      );
      // Также чистим одиночные «классические» фамилии после слова «автор/автора/
      // авторе/автору/автором/о», если их нет в инпуте. Список известных
      // галлюцинаций YandexGPT по сочинениям ЕГЭ:
      const KNOWN_HALLUCINATIONS = [
        'Ваншенкин','Ваншенкина','Ваншенкину','Ваншенкиным','Ваншенкине',
        'Бруштейн','Бруштейна','Бруштейну','Бруштейном','Бруштейне',
        'Распутин','Распутина','Распутину','Распутиным','Распутине',
        'Шолохов','Шолохова','Шолохову','Шолоховым','Шолохове',
        'Астафьев','Астафьева','Астафьеву','Астафьевым','Астафьеве',
        'Паустовский','Паустовского','Паустовскому','Паустовским','Паустовском',
      ];
      for(const name of KNOWN_HALLUCINATIONS){
        const stem = name.toLowerCase().slice(0, 6);
        if(inputCorpus.includes(stem)) continue; // имя реально присутствует — не трогаем
        // ВНИМАНИЕ: \b в JS не работает с кириллицей — используем lookaround
        // по русским/латинским буквам.
        const re = new RegExp('(?<![А-Яа-яёЁA-Za-z])' + name + '(?![А-Яа-яёЁA-Za-z])', 'g');
        out = out.replace(re, 'автор');
      }
      return out;
    }

    /* Применяем фильтр к general и ко всем comments */
    const rawGeneral = typeof parsed.general === 'string' ? String(parsed.general).trim() : '';
    const rawCommentsSample = (comments.k1 || comments.k2 || '').slice(0, 200);
    console.log('[scrub] inputCorpus.length =', inputCorpus.length,
      '| corpus.includes("ванше") =', inputCorpus.includes('ванше'),
      '| corpus.includes("распу") =', inputCorpus.includes('распу'));
    console.log('[scrub] sourceText.length =', sourceText.length,
      '| essayText.length =', essayText.length,
      '| teacherMarks.length =', teacherMarks.length);
    /* Если «ванше» нашлось — выводим контекст ±80 символов вокруг каждого
       вхождения, чтобы понять где именно. Поможет диагностировать варианты:
       — упоминание в исходном тексте,
       — фантомные данные из старых записей,
       — нечитаемое попадание в любое поле. */
    if(inputCorpus.includes('ванше')){
      const sources = [
        { name: 'sourceText', txt: sourceText.toLowerCase() },
        { name: 'essayText',  txt: essayText.toLowerCase() },
        { name: 'studentName', txt: studentName.toLowerCase() },
      ];
      for(const s of sources){
        let idx = 0;
        while((idx = s.txt.indexOf('ванше', idx)) !== -1){
          const ctxStart = Math.max(0, idx - 80);
          const ctxEnd = Math.min(s.txt.length, idx + 80);
          console.log('[scrub] «ванше» в ' + s.name + ' @' + idx + ': «' +
            s.txt.slice(ctxStart, ctxEnd).replace(/\s+/g, ' ') + '»');
          idx += 5;
        }
      }
    }
    /* Также логируем учительские отметки — вдруг там кто-то упомянул Ваншенкина */
    if(teacherMarks.length){
      const marksDump = JSON.stringify(teacherMarks).slice(0, 800);
      console.log('[scrub] teacherMarks sample:', marksDump);
    }
    console.log('[scrub] raw general:', rawGeneral.slice(0, 200));
    console.log('[scrub] raw comments.k1:', rawCommentsSample);
    try {
      for(const k of Object.keys(comments)){
        const before = comments[k];
        comments[k] = scrubHallucinatedNames(comments[k]);
        if(before !== comments[k]){
          console.log('[scrub] ' + k + ' changed (was/now):',
            before.slice(0, 150), '|||', comments[k].slice(0, 150));
        }
      }
    } catch(e) {
      console.error('[scrub] error in comments:', e);
    }
    let general = rawGeneral;
    try {
      general = scrubHallucinatedNames(rawGeneral);
      if(rawGeneral !== general){
        console.log('[scrub] general changed (was/now):',
          rawGeneral.slice(0, 150), '|||', general.slice(0, 150));
      } else {
        console.log('[scrub] general NOT changed');
      }
    } catch(e) {
      console.error('[scrub] error in general:', e);
    }
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
