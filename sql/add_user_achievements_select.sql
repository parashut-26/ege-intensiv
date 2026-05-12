-- =========================================================
-- Разрешить ученику видеть свои разблокированные достижения.
-- INSERT работал (триггеры a1/a5/b2 успешно создавали записи),
-- а SELECT блокировался — поэтому в кабинете ничего не горело,
-- хотя в БД у Вероники есть 3 записи: a1, b2, a5.
-- =========================================================

DROP POLICY IF EXISTS "user_achievements_self_select" ON user_achievements;
CREATE POLICY "user_achievements_self_select" ON user_achievements
  FOR SELECT TO authenticated USING (
    student_id = auth.uid()
    OR is_teacher()
    OR is_curator()
  );

-- На всякий случай — INSERT (уже работает, но фиксируем явно)
DROP POLICY IF EXISTS "user_achievements_self_insert" ON user_achievements;
CREATE POLICY "user_achievements_self_insert" ON user_achievements
  FOR INSERT TO authenticated WITH CHECK (
    student_id = auth.uid()
    OR is_teacher()
    OR is_curator()
  );

-- Проверка
SELECT 'user_achievements policies ok' AS status,
  (SELECT COUNT(*) FROM user_achievements) AS total;
