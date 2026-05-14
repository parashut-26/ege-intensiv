-- =========================================================
-- Поле «Пояснение ученика к ответу» в test_variant_answers.
-- Ученик заполняет на странице результата варианта (РНО —
-- работа над ошибками). Учитель видит это в drill-down ячейки.
-- =========================================================

ALTER TABLE test_variant_answers
  ADD COLUMN IF NOT EXISTS student_note TEXT;

-- RLS: ученик уже должен иметь UPDATE на свои ответы.
-- Если такой политики нет — добавим, иначе пропустим.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
     WHERE schemaname = 'public'
       AND tablename = 'test_variant_answers'
       AND policyname = 'tva student update own'
  ) THEN
    EXECUTE $POL$
      CREATE POLICY "tva student update own"
        ON test_variant_answers FOR UPDATE TO authenticated
        USING (
          EXISTS (
            SELECT 1 FROM test_variant_attempts a
             WHERE a.id = test_variant_answers.attempt_id
               AND a.profile_id = auth.uid()
          )
        )
        WITH CHECK (
          EXISTS (
            SELECT 1 FROM test_variant_attempts a
             WHERE a.id = test_variant_answers.attempt_id
               AND a.profile_id = auth.uid()
          )
        )
    $POL$;
  END IF;
END $$;

-- Проверка
SELECT 'test_variant_answers.student_note ok' AS status;
