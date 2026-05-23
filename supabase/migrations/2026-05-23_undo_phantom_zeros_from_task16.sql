-- 2026-05-23 (хотфикс): откат «нулёвок-фантомов» — глобальная санация
-- ВКЛЮЧАЕТ откат фантомов от миграции 2026-05-23_recompute_task16_from_structured.sql
-- + все «пустые» строки test_variant_answers по любому заданию 1-26.
--
-- Проблема: предыдущая миграция апдейтила user_answer + points даже у строк,
-- где structured_state.checks16 был фактически пустой (ученик зашёл в задание,
-- ничего не выбрал, вышел). После пересчёта получалось user_answer=NULL,
-- points=0 — учитель видит зелёный/красный «0» вместо серого «—».
--
-- Это лечение в два шага:
--   1) удалить строки задания 16, где user_answer пуст, points=0,
--      и в structured_state.checks16 нет ни одной реальной запятой
--      (только пустые объекты или _picked=false)
--   2) если есть «безответные» строки 17-20 / 15 — на всякий, идемпотентно
--
-- Безопасно: реальные ответы (с user_answer или points>0) не трогаем.
-- Запуск: Supabase Dashboard → SQL Editor → Run.

-- =====================================================================
-- 1) Удаляем фантомные строки задания 16
-- =====================================================================
DO $$
DECLARE
  rec RECORD;
  sentence_key TEXT;
  gap_key TEXT;
  any_comma BOOL;
  any_picked BOOL;
  deleted_count INT := 0;
  reset_count INT := 0;
BEGIN
  FOR rec IN
    SELECT a.id, a.structured_state, a.user_answer, a.points
    FROM public.test_variant_answers a
    WHERE a.question_num = 16
      AND COALESCE(a.user_answer, '') = ''
      AND COALESCE(a.points, 0) = 0
      AND a.structured_state IS NOT NULL
      AND a.structured_state ? 'checks16'
      AND a.scratch IS NULL
      AND a.student_drawing IS NULL
      AND a.student_note IS NULL
      AND a.teacher_comment IS NULL
      AND a.teacher_scratch IS NULL
      AND a.teacher_drawing IS NULL
  LOOP
    any_comma := false;
    any_picked := false;

    -- Проверяем что в checks16 реально что-то выбрано
    FOR sentence_key IN
      SELECT jsonb_object_keys(rec.structured_state->'checks16')
    LOOP
      FOR gap_key IN
        SELECT jsonb_object_keys(rec.structured_state->'checks16'->sentence_key)
      LOOP
        IF gap_key = '_picked' THEN
          IF rec.structured_state->'checks16'->sentence_key->'_picked' = 'true'::jsonb THEN
            any_picked := true;
          END IF;
        ELSIF gap_key = '_pickedManual' THEN
          NULL;
        ELSE
          IF rec.structured_state->'checks16'->sentence_key->gap_key = 'true'::jsonb THEN
            any_comma := true;
          END IF;
        END IF;
      END LOOP;
    END LOOP;

    -- Реальных тапов нет — фантом
    IF NOT any_comma AND NOT any_picked THEN
      DELETE FROM public.test_variant_answers WHERE id = rec.id;
      deleted_count := deleted_count + 1;
    END IF;
  END LOOP;

  RAISE NOTICE '--- Хотфикс №16 ---';
  RAISE NOTICE 'Удалено фантомных строк: %', deleted_count;
END $$;

-- =====================================================================
-- 2) Профилактика: то же самое для 15 и 17-20 на случай если та миграция
--    тоже была запущена (если нет — этот блок просто ничего не найдёт)
-- =====================================================================
DO $$
DECLARE
  rec RECORD;
  gap_key TEXT;
  raw_val TEXT;
  any_pick BOOL;
  deleted_count INT := 0;
BEGIN
  FOR rec IN
    SELECT a.id, a.question_num, a.structured_state
    FROM public.test_variant_answers a
    WHERE a.question_num IN (15, 17, 18, 19, 20)
      AND COALESCE(a.user_answer, '') = ''
      AND COALESCE(a.points, 0) = 0
      AND a.structured_state IS NOT NULL
      AND a.structured_state ? 'gaps'
      AND a.scratch IS NULL
      AND a.student_drawing IS NULL
      AND a.student_note IS NULL
      AND a.teacher_comment IS NULL
      AND a.teacher_scratch IS NULL
      AND a.teacher_drawing IS NULL
  LOOP
    any_pick := false;
    FOR gap_key IN
      SELECT jsonb_object_keys(rec.structured_state->'gaps')
    LOOP
      raw_val := rec.structured_state->'gaps'->>gap_key;
      IF raw_val IS NOT NULL AND raw_val <> 'false' AND raw_val <> 'null' AND raw_val <> '' THEN
        any_pick := true;
        EXIT;
      END IF;
    END LOOP;

    IF NOT any_pick THEN
      DELETE FROM public.test_variant_answers WHERE id = rec.id;
      deleted_count := deleted_count + 1;
    END IF;
  END LOOP;

  RAISE NOTICE '--- Хотфикс №15/17-20 ---';
  RAISE NOTICE 'Удалено фантомных строк: %', deleted_count;
END $$;

-- =====================================================================
-- 2.5) Глобальная санация — любые задания 1-26 где user_answer пуст,
--      points=0, и нет НИКАКИХ признаков взаимодействия (включая
--      structured_state — должен быть null или пустой)
-- =====================================================================
WITH deleted AS (
  DELETE FROM public.test_variant_answers a
  WHERE a.question_num BETWEEN 1 AND 26
    AND COALESCE(a.user_answer, '') = ''
    AND COALESCE(a.points, 0) = 0
    AND a.scratch IS NULL
    AND a.student_drawing IS NULL
    AND a.student_note IS NULL
    AND a.teacher_comment IS NULL
    AND a.teacher_scratch IS NULL
    AND a.teacher_drawing IS NULL
    AND (
      a.structured_state IS NULL
      OR a.structured_state = '{}'::jsonb
      OR jsonb_typeof(a.structured_state) = 'object' AND (
        SELECT count(*) FROM jsonb_object_keys(a.structured_state)
      ) = 0
    )
  RETURNING id
)
SELECT count(*) AS "глобально удалено фантомов" FROM deleted;

-- =====================================================================
-- 3) Перекатываем total_score / correct_count / percent_correct на
--    попытках где могли поменяться строки (полный пересчёт)
-- =====================================================================
WITH rollup AS (
  SELECT att.id AS attempt_id,
         COALESCE(SUM(CASE WHEN a.question_num < 27
                            AND a.points IS NOT NULL
                            AND a.max_points IS NOT NULL
                            AND a.max_points > 0
                            AND a.points >= a.max_points
                           THEN 1 ELSE 0 END), 0) AS new_correct,
         COALESCE(SUM(CASE WHEN a.question_num < 27 THEN COALESCE(a.points, 0) ELSE 0 END), 0) AS new_total,
         COALESCE(SUM(CASE WHEN a.question_num < 27 THEN COALESCE(a.max_points, 0) ELSE 0 END), 0) AS new_max
  FROM public.test_variant_attempts att
  LEFT JOIN public.test_variant_answers a ON a.attempt_id = att.id
  WHERE att.finished_at IS NOT NULL
  GROUP BY att.id
)
UPDATE public.test_variant_attempts t
SET correct_count   = r.new_correct,
    total_score     = floor(r.new_total),
    percent_correct = CASE WHEN r.new_max > 0
                            THEN round((r.new_total::numeric / r.new_max) * 1000) / 10
                            ELSE 0 END
FROM rollup r
WHERE t.id = r.attempt_id
  AND (t.correct_count   IS DISTINCT FROM r.new_correct
    OR t.total_score     IS DISTINCT FROM floor(r.new_total)
    OR t.percent_correct IS DISTINCT FROM CASE WHEN r.new_max > 0
                                                THEN round((r.new_total::numeric / r.new_max) * 1000) / 10
                                                ELSE 0 END);

-- =====================================================================
-- 4) Контрольный отчёт
-- =====================================================================
SELECT
  question_num                                    AS "№",
  count(*)                                        AS "всего строк",
  count(*) FILTER (WHERE user_answer IS NOT NULL) AS "с ответом",
  count(*) FILTER (WHERE user_answer IS NULL
                    AND points = 0)                AS "фантомов осталось"
FROM public.test_variant_answers
WHERE question_num IN (15, 16, 17, 18, 19, 20)
GROUP BY question_num
ORDER BY question_num;
