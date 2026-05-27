-- =============================================================================
-- 2026-05-27 — test_progress: разрешить учителю/куратору SELECT всех учеников
-- =============================================================================
-- Прецедент: «Хочу в моменте решения учеником заданий в его личном кабинете
-- видеть Live решение заданий, как у нас это настроено в вариантах»
-- (Ольга, 27.05.2026). Для этого учителю нужен доступ на чтение test_progress
-- всех учеников.
--
-- Существующая политика "tp_select_own" остаётся (ученик читает свой прогресс).
-- Добавляем вторую SELECT-политику с OR-логикой — Postgres объединяет их через
-- OR автоматически.
-- =============================================================================

DROP POLICY IF EXISTS "tp_select_teacher_curator" ON test_progress;

CREATE POLICY "tp_select_teacher_curator" ON test_progress
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM profiles
      WHERE id = auth.uid() AND role IN ('teacher', 'curator')
    )
  );

-- Проверка: вывести все SELECT-политики на test_progress
DO $$
DECLARE
  pnames text;
BEGIN
  SELECT string_agg(polname, ', ') INTO pnames
  FROM pg_policy
  WHERE polrelid = 'test_progress'::regclass
    AND polcmd = 'r';   -- SELECT
  RAISE NOTICE 'SELECT-политики на test_progress: %', COALESCE(pnames, '(нет)');
END $$;
