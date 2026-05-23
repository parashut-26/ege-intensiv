-- 2026-05-23: Ретро-пересчёт балла по заданиям 15 и 17-20 из structured_state
--
-- Контекст: у этих заданий ученик тапает по цифрам (1)(2)(3)(4) в формулировке,
-- а user_answer заполняется автоматически — НО только если включён глобальный
-- тумблер «авто-запись цифр в поле ответа» (STATE.solverAutoFillDigits).
-- Тумблер сохранялся в localStorage; у кого-то оказался выключен (случайно
-- или из предыдущего экспериментального режима), и user_answer оставался
-- пустой при том, что тапы корректно сохранялись в structured_state.gaps.
--
-- С 23 мая 2026 на фронте тумблер принудительно ВКЛ для всех — выключить
-- нельзя. Эта миграция применяет ту же логику к уже сохранённым попыткам:
-- для №15 «в ответ идут НН-позиции», для №17-20 «в ответ идут позиции с
-- запятой».
--
-- Безопасно: апдейтим только если user_answer был пуст ИЛИ пересчёт даёт
-- большее число баллов. Снижать балл (если ученик отдельно типизировал
-- правильный ответ руками, а structured_state неполный) — не должны.
--
-- Запуск: Supabase Dashboard → SQL Editor → New query → Run.

-- =====================================================================
-- 1) Пересчёт user_answer + points для заданий 15, 17-20
-- =====================================================================
DO $$
DECLARE
  rec RECORD;
  gap_key TEXT;
  raw_val TEXT;
  matched INT[];
  new_answer TEXT;
  norm_new TEXT;
  norm_correct_one TEXT;
  alt TEXT;
  new_points INT;
  effective_max INT;
  updated_count INT := 0;
  unchanged_count INT := 0;
  task_n INT;
BEGIN
  FOR rec IN
    SELECT a.id,
           a.question_num,
           a.user_answer,
           a.points,
           a.max_points,
           a.structured_state,
           q.correct_answer,
           q.max_points AS q_max_points
    FROM public.test_variant_answers a
    JOIN public.test_variant_attempts att ON att.id = a.attempt_id
    JOIN public.test_variant_questions q
      ON q.variant_id = att.variant_id AND q.num = a.question_num
    WHERE a.question_num IN (15, 17, 18, 19, 20)
      AND a.structured_state IS NOT NULL
      AND a.structured_state ? 'gaps'
  LOOP
    matched := ARRAY[]::INT[];
    task_n := rec.question_num;

    -- Перебираем все ключи gaps
    FOR gap_key IN
      SELECT jsonb_object_keys(rec.structured_state->'gaps')
    LOOP
      -- raw_val: текстовое представление значения (для bool true → 'true',
      -- для строки "НН" → 'НН')
      raw_val := rec.structured_state->'gaps'->>gap_key;

      IF task_n = 15 THEN
        -- В ответ идут НН-позиции (или legacy true=НН).
        -- 'Н' (просто одна Н) НЕ идёт.
        IF raw_val = 'НН' OR raw_val = 'true' THEN
          BEGIN
            matched := matched || gap_key::INT;
          EXCEPTION WHEN OTHERS THEN
            NULL;
          END;
        END IF;
      ELSE
        -- 17-20: любая позиция со значением true (запятая выбрана)
        IF raw_val = 'true' THEN
          BEGIN
            matched := matched || gap_key::INT;
          EXCEPTION WHEN OTHERS THEN
            NULL;
          END;
        END IF;
      END IF;
    END LOOP;

    matched := ARRAY(SELECT unnest(matched) ORDER BY 1);
    new_answer := array_to_string(matched, '');

    -- Нормализация ровно как в normalizeAnswer() на фронте
    norm_new := lower(regexp_replace(COALESCE(new_answer, ''), '[\s,\.]', '', 'g'));
    norm_new := replace(norm_new, 'ё', 'е');

    -- Сверяем с correct_answer
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

    -- Защита: НЕ снижаем балл. Если у ученика уже был непустой user_answer
    -- И там было больше баллов — не трогаем (он мог дозаполнить руками).
    IF COALESCE(rec.user_answer, '') <> '' AND COALESCE(rec.points, 0) >= new_points THEN
      unchanged_count := unchanged_count + 1;
      CONTINUE;
    END IF;

    IF COALESCE(rec.user_answer, '') IS DISTINCT FROM NULLIF(new_answer, '')
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

  RAISE NOTICE '--- Задания 15 + 17-20: пересчёт ---';
  RAISE NOTICE 'Обновлено строк: %', updated_count;
  RAISE NOTICE 'Без изменений: %', unchanged_count;
END $$;

-- =====================================================================
-- 2) Перекатываем total_score / correct_count / percent_correct на
--    затронутых попытках (полный пересчёт по test_variant_answers).
-- =====================================================================
WITH affected AS (
  SELECT DISTINCT att.id AS attempt_id
  FROM public.test_variant_attempts att
  JOIN public.test_variant_answers a ON a.attempt_id = att.id
  WHERE a.question_num IN (15, 17, 18, 19, 20)
    AND a.structured_state IS NOT NULL
    AND a.structured_state ? 'gaps'
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
-- 3) Контрольный отчёт по каждому из четырёх заданий
-- =====================================================================
SELECT
  question_num                                   AS "№",
  count(*)                                       AS "всего",
  count(*) FILTER (WHERE user_answer IS NOT NULL) AS "с ответом",
  count(*) FILTER (WHERE points > 0)              AS "с баллом",
  round(avg(points)::numeric, 2)                  AS "средний"
FROM public.test_variant_answers
WHERE question_num IN (15, 17, 18, 19, 20)
GROUP BY question_num
ORDER BY question_num;
