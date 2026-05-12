-- =========================================================
-- ВАРИАНТЫ-ПРОБНИКИ (импорт из Online Test Pad — этап 1)
-- Три таблицы для хранения результатов пробника с заполнением
-- из загруженного учителем .xlsx-экспорта OTP.
-- Этап 2 (решалка внутри ZebRus) добавит сюда же:
--   - test_variant_questions (текст + ключ)
--   - source='platform' и UI прохождения
-- =========================================================

-- 1. Сам вариант (Вариант 32 2026 и т.д.)
CREATE TABLE IF NOT EXISTS test_variants (
  id              SERIAL PRIMARY KEY,
  title           TEXT NOT NULL,
  source          TEXT NOT NULL DEFAULT 'otp_import',  -- otp_import | pdf_import | platform
  questions_count INTEGER NOT NULL DEFAULT 27,
  total_max_score INTEGER,  -- максимум первичных баллов (для нормировки)
  created_by      UUID REFERENCES profiles(id),
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  notes           TEXT
);

CREATE INDEX IF NOT EXISTS test_variants_created_at_idx ON test_variants(created_at DESC);

-- 2. Попытка ученика по варианту (одна строка из xlsx OTP)
CREATE TABLE IF NOT EXISTS test_variant_attempts (
  id                    SERIAL PRIMARY KEY,
  variant_id            INTEGER NOT NULL REFERENCES test_variants(id) ON DELETE CASCADE,
  profile_id            UUID REFERENCES profiles(id) ON DELETE SET NULL,  -- nullable если не привязали
  otp_user              TEXT,                -- "Ульяна О" из колонки «Пользователь»
  otp_full_name         TEXT,                -- "Ульяна Филатова" из колонки «Имя и фамилия»
  otp_ip                TEXT,
  finished_at           TIMESTAMPTZ,
  time_spent_seconds    INTEGER,             -- из «Потрачено времени» 00:49:28 → 2968
  correct_count         NUMERIC(5,2),        -- 13.5 (бывают полу-баллы)
  percent_correct       NUMERIC(5,2),        -- 48.21
  total_score           INTEGER,             -- 39 (первичный балл)
  imported_at           TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS test_variant_attempts_variant_idx ON test_variant_attempts(variant_id);
CREATE INDEX IF NOT EXISTS test_variant_attempts_profile_idx ON test_variant_attempts(profile_id);

-- 3. Ответ ученика на одно задание варианта (1..27)
CREATE TABLE IF NOT EXISTS test_variant_answers (
  id              SERIAL PRIMARY KEY,
  attempt_id      INTEGER NOT NULL REFERENCES test_variant_attempts(id) ON DELETE CASCADE,
  question_num    INTEGER NOT NULL,                   -- 1..27
  user_answer     TEXT,                                -- что написал ученик
  points          NUMERIC(4,2) NOT NULL DEFAULT 0,    -- баллы (0, 0.5, 1, 1.5, 2)
  max_points      NUMERIC(4,2) NOT NULL DEFAULT 1,
  is_correct      BOOLEAN GENERATED ALWAYS AS (points >= max_points AND max_points > 0) STORED,
  UNIQUE(attempt_id, question_num)
);

CREATE INDEX IF NOT EXISTS test_variant_answers_attempt_idx ON test_variant_answers(attempt_id);

-- ---------------------------------------------------------
-- RLS
-- ---------------------------------------------------------
ALTER TABLE test_variants ENABLE ROW LEVEL SECURITY;
ALTER TABLE test_variant_attempts ENABLE ROW LEVEL SECURITY;
ALTER TABLE test_variant_answers ENABLE ROW LEVEL SECURITY;

-- Учитель / куратор видит и управляет всем.
-- Ученик: видит сам вариант (заголовок) и только СВОИ попытки и ответы.

-- test_variants
DROP POLICY IF EXISTS "tv_read" ON test_variants;
CREATE POLICY "tv_read" ON test_variants FOR SELECT TO authenticated USING (TRUE);

DROP POLICY IF EXISTS "tv_write" ON test_variants;
CREATE POLICY "tv_write" ON test_variants FOR ALL TO authenticated
  USING (is_teacher() OR is_curator())
  WITH CHECK (is_teacher() OR is_curator());

-- test_variant_attempts
DROP POLICY IF EXISTS "tva_read" ON test_variant_attempts;
CREATE POLICY "tva_read" ON test_variant_attempts FOR SELECT TO authenticated USING (
  is_teacher() OR is_curator() OR profile_id = auth.uid()
);

DROP POLICY IF EXISTS "tva_write" ON test_variant_attempts;
CREATE POLICY "tva_write" ON test_variant_attempts FOR ALL TO authenticated
  USING (is_teacher() OR is_curator())
  WITH CHECK (is_teacher() OR is_curator());

-- test_variant_answers — следуем правам родительской попытки
DROP POLICY IF EXISTS "tvans_read" ON test_variant_answers;
CREATE POLICY "tvans_read" ON test_variant_answers FOR SELECT TO authenticated USING (
  is_teacher() OR is_curator()
  OR EXISTS (
    SELECT 1 FROM test_variant_attempts a
    WHERE a.id = test_variant_answers.attempt_id AND a.profile_id = auth.uid()
  )
);

DROP POLICY IF EXISTS "tvans_write" ON test_variant_answers;
CREATE POLICY "tvans_write" ON test_variant_answers FOR ALL TO authenticated
  USING (is_teacher() OR is_curator())
  WITH CHECK (is_teacher() OR is_curator());

-- Проверка
SELECT 'test_variants ok' AS status,
  (SELECT COUNT(*) FROM test_variants) AS variants_count;
