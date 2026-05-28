-- =============================================================================
-- 2026-05-28 — оставшиеся collection = NULL → «Авторские»
-- =============================================================================
-- После основной унификации коллекций остались вопросы без collection
-- (нет src, или нестандартный src). По решению Ольги — это её авторские
-- задания. Проставляем им collection = 'Авторские'.
--
-- Затронуто (на момент 28.05.2026): task 9 — 1 шт., task 22 — 30 шт.
-- Идемпотентно: повторный запуск не делает ничего.
-- =============================================================================

UPDATE quiz_bank_overrides
SET questions = (
  SELECT jsonb_agg(
    CASE
      WHEN q->>'collection' IS NULL
        THEN q || jsonb_build_object('collection', 'Авторские')
      ELSE q
    END
    ORDER BY ord
  )
  FROM jsonb_array_elements(questions) WITH ORDINALITY AS x(q, ord)
),
updated_at = now();

-- Проверка
DO $$
DECLARE
  null_left int;
  authorial_cnt int;
BEGIN
  SELECT COUNT(*) INTO null_left
    FROM quiz_bank_overrides, jsonb_array_elements(questions) q
   WHERE q->>'collection' IS NULL;
  SELECT COUNT(*) INTO authorial_cnt
    FROM quiz_bank_overrides, jsonb_array_elements(questions) q
   WHERE q->>'collection' = 'Авторские';
  RAISE NOTICE 'NULL осталось: %, всего в «Авторские»: %', null_left, authorial_cnt;
END $$;

-- Финальная карта коллекций
SELECT task_n, q->>'collection' AS collection, COUNT(*) AS cnt
FROM quiz_bank_overrides, jsonb_array_elements(questions) q
GROUP BY task_n, collection
ORDER BY task_n, collection;
