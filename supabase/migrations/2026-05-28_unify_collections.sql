-- =============================================================================
-- 2026-05-28 — унификация коллекций по всему банку quiz_bank_overrides
-- =============================================================================
-- Прецедент: 28.05.2026 учительница хочет везде видеть чистые коллекции в UI
-- запуска тренажёра (как сделано для задания 16: ОБЗ ФИПИ, Заремская,
-- Баландина-Дудина). У большинства старых вопросов collection пустое или
-- разные написания.
--
-- Правила:
--   1) Существующее имя «ОБЗ ФИПИ» → «ОБЗ ЕГЭ» (одно официальное имя).
--   2) Если collection нет, проставляем по src:
--      • LIKE 'ОБЗ ФИПИ%' / 'ОБЗ ЕГЭ%'  → 'ОБЗ ЕГЭ'
--      • LIKE 'Вариант%'                → 'Баландина-Дудина · ЕГЭ-2025'
--      • LIKE 'Работа №%'               → 'Мегатренажёр · Заремская'
--   3) Уже заполненные коллекции (Приставки, Н и НН, Заремская и т.д.)
--      оставляем как есть.
--
-- Идемпотентно: повторный запуск не сломает данные.
-- =============================================================================

UPDATE quiz_bank_overrides
SET questions = (
  SELECT jsonb_agg(
    CASE
      WHEN q->>'collection' = 'ОБЗ ФИПИ'
        THEN q || jsonb_build_object('collection', 'ОБЗ ЕГЭ')

      WHEN q->>'collection' IS NULL
       AND (q->>'src' LIKE 'ОБЗ ФИПИ%' OR q->>'src' LIKE 'ОБЗ ЕГЭ%')
        THEN q || jsonb_build_object('collection', 'ОБЗ ЕГЭ')

      WHEN q->>'collection' IS NULL
       AND q->>'src' LIKE 'Вариант%'
        THEN q || jsonb_build_object('collection', 'Баландина-Дудина · ЕГЭ-2025')

      WHEN q->>'collection' IS NULL
       AND q->>'src' LIKE 'Работа №%'
        THEN q || jsonb_build_object('collection', 'Мегатренажёр · Заремская')

      ELSE q
    END
    ORDER BY ord
  )
  FROM jsonb_array_elements(questions) WITH ORDINALITY AS x(q, ord)
),
updated_at = now();

-- Проверка: новая карта коллекций
DO $$
DECLARE
  null_cnt int;
BEGIN
  SELECT COUNT(*) INTO null_cnt
    FROM quiz_bank_overrides, jsonb_array_elements(questions) q
   WHERE q->>'collection' IS NULL;
  RAISE NOTICE 'Вопросов без collection осталось: %', null_cnt;
END $$;

SELECT task_n,
       COALESCE(q->>'collection', '⚠ всё ещё NULL') AS collection,
       COUNT(*) AS cnt
FROM quiz_bank_overrides, jsonb_array_elements(questions) q
GROUP BY task_n, collection
ORDER BY task_n, collection NULLS FIRST;
