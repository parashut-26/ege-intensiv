-- 2026-05-23: Ретро-пересчёт балла по заданию 16 из structured_state
--
-- Контекст: до этого фикса в задании 16 user_answer собирался ТОЛЬКО по
-- ручной отметке ☑ (_picked). Дети, расставив запятые между словами но
-- забыв нажать ☑, получали пустой user_answer и 0 баллов — хотя
-- структурный стейт (где и сколько запятых) сохранялся корректно.
--
-- Новая логика на фронте (см. makeTask16Field): предложение попадает в
-- ответ если ровно 1 запятая ИЛИ ручной _picked=true. Эта миграция
-- применяет ту же логику к уже сохранённым попыткам.
--
-- Безопасно: пересчёт идёт только там, где есть structured_state.checks16.
-- Если user_answer уже совпадает с новым — UPDATE не делается.
--
-- Запуск: Supabase Dashboard → SQL Editor → New query → Run.

-- =====================================================================
-- 1) Пересчёт user_answer + points для каждой строки test_variant_answers
--    с question_num=16 и непустым structured_state.checks16
-- =====================================================================
DO $$
DECLARE
  rec RECORD;
  sentence_key TEXT;
  gap_key TEXT;
  cnt INT;
  picked BOOL;
  matched INT[];
  new_answer TEXT;
  norm_new TEXT;
  norm_correct_one TEXT;
  alt TEXT;
  new_points INT;
  effective_max INT;
  updated_count INT := 0;
  unchanged_count INT := 0;
  no_checks_count INT := 0;
BEGIN
  FOR rec IN
    SELECT a.id,
           a.user_answer,
           a.points,
           a.max_points,
           a.structured_state,
           q.correct_answer,
           q.max_points AS q_max_points
    FROM public.test_variant_answers a
    JOIN public.test_variant_attempts att ON att.id = a.attempt_id
    JOIN public.test_variant_questions q
      ON q.variant_id = att.variant_id AND q.num = 16
    WHERE a.question_num = 16
      AND a.structured_state IS NOT NULL
      AND a.structured_state ? 'checks16'
  LOOP
    matched := ARRAY[]::INT[];

    -- Перебираем номера предложений (ключи checks16)
    FOR sentence_key IN
      SELECT jsonb_object_keys(rec.structured_state->'checks16')
    LOOP
      cnt := 0;
      picked := false;

      -- Считаем запятые (любые true-ключи кроме _picked / _pickedManual)
      -- и ловим ручную отметку
      FOR gap_key IN
        SELECT jsonb_object_keys(rec.structured_state->'checks16'->sentence_key)
      LOOP
        IF gap_key = '_picked' THEN
          IF rec.structured_state->'checks16'->sentence_key->'_picked' = 'true'::jsonb THEN
            picked := true;
          END IF;
        ELSIF gap_key = '_pickedManual' THEN
          -- служебный флаг, не считаем
          NULL;
        ELSE
          IF rec.structured_state->'checks16'->sentence_key->gap_key = 'true'::jsonb THEN
            cnt := cnt + 1;
          END IF;
        END IF;
      END LOOP;

      -- Новое правило: ровно 1 запятая ИЛИ ручная отметка
      IF picked OR cnt = 1 THEN
        BEGIN
          matched := matched || sentence_key::INT;
        EXCEPTION WHEN OTHERS THEN
          -- ключ не число — игнорируем (не должно быть, но на всякий)
          NULL;
        END;
      END IF;
    END LOOP;

    -- Сортируем и склеиваем в строку («125»)
    matched := ARRAY(SELECT unnest(matched) ORDER BY 1);
    new_answer := array_to_string(matched, '');

    -- Нормализация ровно как в normalizeAnswer() на фронте
    norm_new := lower(regexp_replace(COALESCE(new_answer, ''), '[\s,\.]', '', 'g'));
    norm_new := replace(norm_new, 'ё', 'е');

    -- Сверяем с correct_answer (разделители /)
    effective_max := COALESCE(rec.q_max_points, rec.max_points, 1);
    new_points := 0;
    IF length(norm_new) > 0 AND rec.correct_answer IS NOT NULL THEN
      FOREACH alt IN ARRAY string_to_array(rec.correct_answer, '/') LOOP
        norm_correct_one := lower(regexp_replace(alt, '[\s,\.]', '', 'g'));
        norm_correct_one := replace(norm_correct_one, 'ё', 'е');
        IF norm_correct_one <> '' AND norm_correct_one = norm_new THEN
          new_points := effective_max;
          EXIT;
        END IF;
      END LOOP;
    END IF;

    -- Апдейтим только если что-то реально поменялось
    IF COALESCE(rec.user_answer, '') IS DISTINCT FROM NULLIF(new_answer, '')
       OR COALESCE(rec.user_answer, '') IS DISTINCT FROM new_answer
       OR COALESCE(rec.points, -1) IS DISTINCT FROM new_points
       OR COALESCE(rec.max_points, -1) IS DISTINCT FROM effective_max THEN
      UPDATE public.test_variant_answers
      SET user_answer = NULLIF(new_answer, ''),
          points      = new_points,
          max_points  = effective_max
      WHERE id = rec.id;
      updated_count := updated_count + 1;
    ELSE
      unchanged_count := unchanged_count + 1;
    END IF;
  END LOOP;

  -- Дополнительно: счётчик попыток у которых вообще не было checks16
  SELECT count(*) INTO no_checks_count
  FROM public.test_variant_answers a
  WHERE a.question_num = 16
    AND (a.structured_state IS NULL OR NOT (a.structured_state ? 'checks16'));

  RAISE NOTICE '--- Задание 16: пересчёт ---';
  RAISE NOTICE 'Обновлено строк: %', updated_count;
  RAISE NOTICE 'Без изменений (уже совпадало): %', unchanged_count;
  RAISE NOTICE 'Без structured.checks16 (не трогали): %', no_checks_count;
END $$;

-- =====================================================================
-- 2) Перекатываем total_score / correct_count / percent_correct на
--    попытках, у которых хотя бы один ответ на задание 16 был обновлён.
--    Безопасно для остальных заданий — пересчёт идёт по всем строкам
--    test_variant_answers этой попытки.
-- =====================================================================
WITH affected AS (
  SELECT DISTINCT att.id AS attempt_id
  FROM public.test_variant_attempts att
  JOIN public.test_variant_answers a ON a.attempt_id = att.id
  WHERE a.question_num = 16
    AND a.structured_state IS NOT NULL
    AND a.structured_state ? 'checks16'
),
rollup AS (
  SELECT att.id AS attempt_id,
         COALESCE(SUM(CASE WHEN a.question_num < 27
                            AND a.points IS NOT NULL
                            AND a.max_points IS NOT NULL
                            AND a.max_points > 0
                            AND a.points >= a.max_points
                           THEN 1 ELSE 0 END), 0) AS new_correct,
         COALESCE(SUM(CASE WHEN a.question_num < 27 THEN COALESCE(a.points, 0) ELSE 0 END), 0) AS new_total,
         COALESCE(SUM(CASE WHEN a.question_num < 27 THEN COALESCE(a.max_points, 0) ELSE 0 END), 0) AS new_max
  FROM affected af
  JOIN public.test_variant_attempts att ON att.id = af.attempt_id
  LEFT JOIN public.test_variant_answers a ON a.attempt_id = att.id
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
-- 3) Контрольный отчёт: сколько ненулевых баллов в задании 16 теперь
-- =====================================================================
SELECT
  count(*)                                       AS total_task16_rows,
  count(*) FILTER (WHERE user_answer IS NOT NULL) AS with_answer,
  count(*) FILTER (WHERE points > 0)              AS scored_positive,
  round(avg(points)::numeric, 2)                  AS avg_points
FROM public.test_variant_answers
WHERE question_num = 16;
