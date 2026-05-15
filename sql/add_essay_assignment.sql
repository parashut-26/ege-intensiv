-- =========================================================
-- НАЗНАЧЕНИЕ СОЧИНЕНИЯ НА КУРАТОРА-ЭКСПЕРТА
--
-- Сценарий:
--   Учитель работает с внешним экспертом. Эксперт добавлен
--   как куратор с правом «expertMode». Учитель назначает на
--   конкретную работу — эксперт видит только её. После проверки
--   учитель снимает назначение — эксперт теряет доступ.
--
-- 1) Добавляем колонку essays.assigned_curator_id
-- 2) Разрешаем куратору обновлять teacher_comment в профилях
--    учеников (нужно для заметок куратором, see «👁 карточка»)
-- =========================================================

-- 1) Колонка назначения
ALTER TABLE essays
  ADD COLUMN IF NOT EXISTS assigned_curator_id UUID REFERENCES profiles(id) ON DELETE SET NULL;
CREATE INDEX IF NOT EXISTS idx_essays_assigned_curator ON essays(assigned_curator_id);

-- 2) RLS на essays: куратор-эксперт видит только назначенные;
--    обычный куратор — все (как раньше); учитель — все.
DROP POLICY IF EXISTS "essay_read" ON essays;
CREATE POLICY "essay_read" ON essays FOR SELECT TO authenticated USING (
  student_id = auth.uid()
  OR is_teacher()
  OR (is_curator() AND (
    -- expert-куратор видит только назначенное; остальные кураторы — всё
    COALESCE(
      (SELECT (curator_perms ->> 'expertMode')::boolean FROM profiles WHERE id = auth.uid()),
      false
    ) = false
    OR assigned_curator_id = auth.uid()
  ))
);

DROP POLICY IF EXISTS "essay_update" ON essays;
CREATE POLICY "essay_update" ON essays FOR UPDATE TO authenticated USING (
  student_id = auth.uid()
  OR is_teacher()
  OR (is_curator() AND (
    COALESCE(
      (SELECT (curator_perms ->> 'expertMode')::boolean FROM profiles WHERE id = auth.uid()),
      false
    ) = false
    OR assigned_curator_id = auth.uid()
  ))
);

-- 3) RLS на essay_reviews: то же правило (через JOIN на essays)
DROP POLICY IF EXISTS "review_read" ON essay_reviews;
CREATE POLICY "review_read" ON essay_reviews FOR SELECT TO authenticated USING (
  EXISTS(SELECT 1 FROM essays e WHERE e.id = essay_id AND (
    e.student_id = auth.uid()
    OR is_teacher()
    OR (is_curator() AND (
      COALESCE(
        (SELECT (curator_perms ->> 'expertMode')::boolean FROM profiles WHERE id = auth.uid()),
        false
      ) = false
      OR e.assigned_curator_id = auth.uid()
    ))
  ))
);

DROP POLICY IF EXISTS "review_write" ON essay_reviews;
CREATE POLICY "review_write" ON essay_reviews FOR ALL TO authenticated USING (
  is_teacher()
  OR (is_curator() AND EXISTS(SELECT 1 FROM essays e WHERE e.id = essay_id AND (
    COALESCE(
      (SELECT (curator_perms ->> 'expertMode')::boolean FROM profiles WHERE id = auth.uid()),
      false
    ) = false
    OR e.assigned_curator_id = auth.uid()
  )))
) WITH CHECK (
  is_teacher()
  OR (is_curator() AND EXISTS(SELECT 1 FROM essays e WHERE e.id = essay_id AND (
    COALESCE(
      (SELECT (curator_perms ->> 'expertMode')::boolean FROM profiles WHERE id = auth.uid()),
      false
    ) = false
    OR e.assigned_curator_id = auth.uid()
  )))
);

-- 4) Куратор может обновлять teacher_comment / s_status у учеников
--    (для заметок в карточке ученика «👁»)
DROP POLICY IF EXISTS "profiles_curator_update_students" ON profiles;
CREATE POLICY "profiles_curator_update_students" ON profiles FOR UPDATE TO authenticated
  USING (is_curator() AND role = 'student')
  WITH CHECK (is_curator() AND role = 'student');

SELECT 'essay assignment + curator notes RLS ok' AS status;
