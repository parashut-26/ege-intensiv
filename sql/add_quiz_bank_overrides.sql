-- =========================================================
-- Постоянное хранение изменений банка тестовых вопросов.
-- QUIZ_BANK в коде — это «исходный» набор. Когда учитель что-то
-- удаляет/добавляет/редактирует, мы сохраняем здесь финальное
-- состояние массива по задаче (1..26). При следующей загрузке
-- платформа подмешивает эти override'ы поверх hard-coded банка.
-- =========================================================

CREATE TABLE IF NOT EXISTS quiz_bank_overrides (
  task_n      INTEGER PRIMARY KEY CHECK (task_n BETWEEN 1 AND 26),
  questions   JSONB NOT NULL,        -- массив вопросов как в QUIZ_BANK[task_n]
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_by  UUID REFERENCES profiles(id)
);

-- RLS
ALTER TABLE quiz_bank_overrides ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "qbo_read" ON quiz_bank_overrides;
CREATE POLICY "qbo_read" ON quiz_bank_overrides FOR SELECT TO authenticated USING (TRUE);

DROP POLICY IF EXISTS "qbo_write" ON quiz_bank_overrides;
CREATE POLICY "qbo_write" ON quiz_bank_overrides FOR ALL TO authenticated
  USING (is_teacher() OR is_curator())
  WITH CHECK (is_teacher() OR is_curator());

-- Проверка
SELECT 'quiz_bank_overrides ok' AS status;
