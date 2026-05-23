-- 2026-05-23 (хотфикс №2): глубокая чистка фантомов test_variant_answers
--
-- Контекст: предыдущий хотфикс (2026-05-23_undo_phantom_zeros_from_task16.sql)
-- удалял строки только если structured_state был null или {} (верхний
-- уровень). Но для задания 21 фантомы выглядят как
--   {"dropdowns21": {"1": [], "2": [], "3": [], "4": [], "5": []}}
-- — верхний ключ есть, поэтому строка оставалась. Учитель видит «0» в
-- ячейке 21 у каждого ученика который просто открыл задание.
--
-- Эта миграция рекурсивно проверяет structured_state: если ВНУТРИ нет
-- ни одного «реального» значения (true / непустой строки / числа !=0 /
-- непустого массива) — удаляем строку.
--
-- Безопасно: пропускаются строки с user_answer, points>0, scratch,
-- drawing, student_note, teacher_comment, teacher_scratch, teacher_drawing.
--
-- Запуск: Supabase Dashboard → SQL Editor → New query → Run.

-- =====================================================================
-- 1) Функция-помощник: есть ли в JSONB-значении хоть один «реальный» атом
-- =====================================================================
CREATE OR REPLACE FUNCTION pg_temp.has_meaningful_value(v jsonb)
RETURNS boolean LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE
  k TEXT;
  el jsonb;
BEGIN
  IF v IS NULL THEN RETURN false; END IF;
  CASE jsonb_typeof(v)
    WHEN 'null'    THEN RETURN false;
    WHEN 'boolean' THEN RETURN v = 'true'::jsonb;
    WHEN 'string'  THEN RETURN v::text <> '""' AND length(v::text) > 2;
    WHEN 'number'  THEN RETURN (v::text)::numeric <> 0;
    WHEN 'array'   THEN
      FOR el IN SELECT jsonb_array_elements(v) LOOP
        IF pg_temp.has_meaningful_value(el) THEN RETURN true; END IF;
      END LOOP;
      RETURN false;
    WHEN 'object'  THEN
      FOR k IN SELECT jsonb_object_keys(v) LOOP
        -- служебные ключи _picked/_pickedManual не считаем «реальными»
        -- если они false; но если true — это значимо
        IF pg_temp.has_meaningful_value(v->k) THEN RETURN true; END IF;
      END LOOP;
      RETURN false;
  END CASE;
  RETURN false;
END $$;

-- =====================================================================
-- 2) Удаляем все фантомы: пусто всё, и в structured_state ничего реального
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
      OR NOT pg_temp.has_meaningful_value(a.structured_state)
    )
  RETURNING id, question_num
)
SELECT
  question_num                          AS "№",
  count(*)                              AS "удалено фантомов"
FROM deleted
GROUP BY question_num
ORDER BY question_num;

-- =====================================================================
-- 3) Перекатываем total_score / correct_count / percent_correct
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
-- 4) Контрольный отчёт: сколько «нулёвок» осталось по каждому заданию
-- =====================================================================
SELECT
  question_num                                    AS "№",
  count(*)                                        AS "всего",
  count(*) FILTER (WHERE user_answer IS NULL
                    AND points = 0)               AS "фантомов осталось"
FROM public.test_variant_answers
WHERE question_num BETWEEN 1 AND 26
GROUP BY question_num
HAVING count(*) FILTER (WHERE user_answer IS NULL AND points = 0) > 0
ORDER BY question_num;
