-- =========================================================
-- «Чемодан без ручки» — личный банк слов/вопросов, на которых
-- ученик ошибся. Из него можно повторять, пока всё не отработает.
-- Сейчас работает для letterGap-тренажёра; легко расширяется
-- на text-тренажёр и другие типы.
-- =========================================================

CREATE TABLE IF NOT EXISTS student_mistake_bank (
  id              BIGSERIAL PRIMARY KEY,
  student_id      UUID        NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  task_n          INTEGER     NOT NULL,                -- номер задания ЕГЭ (4, 9, 10, ...)
  kind            TEXT        NOT NULL DEFAULT 'letterGap',
  question_text   TEXT,                                 -- формулировка (опц.)
  word            TEXT,                                 -- слово с пропуском "_" (для letterGap)
  correct_answer  TEXT        NOT NULL,
  explanation     TEXT,                                 -- пояснение (если есть в банке)
  mistakes_count  INTEGER     NOT NULL DEFAULT 1,
  correct_streak  INTEGER     NOT NULL DEFAULT 0,
  is_mastered     BOOLEAN     NOT NULL DEFAULT FALSE,
  added_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  last_seen_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  mastered_at     TIMESTAMPTZ
);

-- Уникальность: одно слово на одного ученика для одного задания не дублируем
CREATE UNIQUE INDEX IF NOT EXISTS uq_mistake_bank_student_task_word
  ON student_mistake_bank(student_id, task_n, COALESCE(word, ''), correct_answer);

-- Часто фильтруем: «мои неосвоенные»
CREATE INDEX IF NOT EXISTS idx_mistake_bank_open
  ON student_mistake_bank(student_id, is_mastered, task_n);

-- =========================================================
-- RLS
-- =========================================================

ALTER TABLE student_mistake_bank ENABLE ROW LEVEL SECURITY;

-- Ученик видит свои строки
DROP POLICY IF EXISTS "mistake_bank student select" ON student_mistake_bank;
CREATE POLICY "mistake_bank student select"
  ON student_mistake_bank FOR SELECT TO authenticated
  USING (student_id = auth.uid());

-- Ученик добавляет свои
DROP POLICY IF EXISTS "mistake_bank student insert" ON student_mistake_bank;
CREATE POLICY "mistake_bank student insert"
  ON student_mistake_bank FOR INSERT TO authenticated
  WITH CHECK (student_id = auth.uid());

-- Ученик обновляет свои (счётчики, mastered)
DROP POLICY IF EXISTS "mistake_bank student update" ON student_mistake_bank;
CREATE POLICY "mistake_bank student update"
  ON student_mistake_bank FOR UPDATE TO authenticated
  USING (student_id = auth.uid())
  WITH CHECK (student_id = auth.uid());

-- Ученик удаляет свои (если хочет почистить)
DROP POLICY IF EXISTS "mistake_bank student delete" ON student_mistake_bank;
CREATE POLICY "mistake_bank student delete"
  ON student_mistake_bank FOR DELETE TO authenticated
  USING (student_id = auth.uid());

-- Учитель/куратор видит чемоданы всех учеников
DROP POLICY IF EXISTS "mistake_bank staff select" ON student_mistake_bank;
CREATE POLICY "mistake_bank staff select"
  ON student_mistake_bank FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM profiles p
       WHERE p.id = auth.uid()
         AND p.role IN ('teacher', 'curator')
    )
  );

-- Поле для spaced repetition: дата последнего правильного ответа (YYYY-MM-DD).
-- streak растёт только если дата изменилась — нужны 3 РАЗНЫХ дня для освобождения.
ALTER TABLE student_mistake_bank
  ADD COLUMN IF NOT EXISTS last_correct_date DATE;

-- Проверка
SELECT 'student_mistake_bank ok' AS status;
