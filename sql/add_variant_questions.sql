-- =========================================================
-- ВАРИАНТЫ ВНУТРИ ZEBRUS — Этап 2.
-- Учитель загружает PDF варианта + PDF ключей, платформа парсит
-- и сохраняет 26 заданий с их правильными ответами в БД.
-- Ученик решает прямо на платформе, автопроверка по нормализованному
-- сравнению строк, поддержка «веера» альтернатив через слэш.
-- =========================================================

-- 1. Тексты заданий + правильные ответы
CREATE TABLE IF NOT EXISTS test_variant_questions (
  id              SERIAL PRIMARY KEY,
  variant_id      INTEGER NOT NULL REFERENCES test_variants(id) ON DELETE CASCADE,
  num             INTEGER NOT NULL,                    -- 1..27
  question_text   TEXT NOT NULL,
  correct_answer  TEXT,                                -- может быть NULL для №27 (сочинение)
  max_points      NUMERIC(4,2) NOT NULL DEFAULT 1,
  source_kind     TEXT,                                -- 'shared_1_3' | 'shared_22_26' | 'standalone' | NULL
  UNIQUE(variant_id, num)
);
CREATE INDEX IF NOT EXISTS test_variant_questions_variant_idx ON test_variant_questions(variant_id);

-- 2. Общий исходный текст (один на вариант, для группы заданий)
CREATE TABLE IF NOT EXISTS test_variant_source_texts (
  id              SERIAL PRIMARY KEY,
  variant_id      INTEGER NOT NULL REFERENCES test_variants(id) ON DELETE CASCADE,
  kind            TEXT NOT NULL,                       -- 'text_1_3' | 'text_22_26' | 'essay_text'
  body            TEXT NOT NULL,
  UNIQUE(variant_id, kind)
);
CREATE INDEX IF NOT EXISTS test_variant_source_texts_variant_idx ON test_variant_source_texts(variant_id);

-- 3. Расширяем test_variant_attempts полем parent_attempt_id для пересдачи-работы-над-ошибками
ALTER TABLE test_variant_attempts
  ADD COLUMN IF NOT EXISTS parent_attempt_id INTEGER REFERENCES test_variant_attempts(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS attempt_no INTEGER NOT NULL DEFAULT 1,
  ADD COLUMN IF NOT EXISTS started_at TIMESTAMPTZ;
CREATE INDEX IF NOT EXISTS test_variant_attempts_parent_idx
  ON test_variant_attempts(parent_attempt_id) WHERE parent_attempt_id IS NOT NULL;

-- ---------------------------------------------------------
-- RLS
-- ---------------------------------------------------------
ALTER TABLE test_variant_questions ENABLE ROW LEVEL SECURITY;
ALTER TABLE test_variant_source_texts ENABLE ROW LEVEL SECURITY;

-- Все авторизованные читают (нужно для решалки у ученика)
DROP POLICY IF EXISTS "tvq_read" ON test_variant_questions;
CREATE POLICY "tvq_read" ON test_variant_questions FOR SELECT TO authenticated USING (TRUE);

DROP POLICY IF EXISTS "tvq_write" ON test_variant_questions;
CREATE POLICY "tvq_write" ON test_variant_questions FOR ALL TO authenticated
  USING (is_teacher() OR is_curator())
  WITH CHECK (is_teacher() OR is_curator());

DROP POLICY IF EXISTS "tvst_read" ON test_variant_source_texts;
CREATE POLICY "tvst_read" ON test_variant_source_texts FOR SELECT TO authenticated USING (TRUE);

DROP POLICY IF EXISTS "tvst_write" ON test_variant_source_texts;
CREATE POLICY "tvst_write" ON test_variant_source_texts FOR ALL TO authenticated
  USING (is_teacher() OR is_curator())
  WITH CHECK (is_teacher() OR is_curator());

-- Дополнительная политика для attempts — ученик может ВСТАВЛЯТЬ
-- свою попытку (когда решает вариант в платформе).
DROP POLICY IF EXISTS "tva_self_insert" ON test_variant_attempts;
CREATE POLICY "tva_self_insert" ON test_variant_attempts FOR INSERT TO authenticated
  WITH CHECK (
    profile_id = auth.uid()
    OR is_teacher() OR is_curator()
  );

DROP POLICY IF EXISTS "tva_self_update" ON test_variant_attempts;
CREATE POLICY "tva_self_update" ON test_variant_attempts FOR UPDATE TO authenticated
  USING (profile_id = auth.uid() OR is_teacher() OR is_curator())
  WITH CHECK (profile_id = auth.uid() OR is_teacher() OR is_curator());

-- Аналогично для answers — ученик может вставлять свои ответы
DROP POLICY IF EXISTS "tvans_self_insert" ON test_variant_answers;
CREATE POLICY "tvans_self_insert" ON test_variant_answers FOR INSERT TO authenticated
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM test_variant_attempts a
      WHERE a.id = attempt_id
        AND (a.profile_id = auth.uid() OR is_teacher() OR is_curator())
    )
  );

-- Проверка
SELECT 'test_variant_questions ok' AS status,
  (SELECT COUNT(*) FROM test_variant_questions) AS qs;
