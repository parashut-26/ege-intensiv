-- =========================================================
-- Разрешить учителю/куратору вставлять сочинения от имени ученика.
-- Нужно для импорта результатов из Excel (когда работа писалась
-- на CloudText/бумаге, а баллы К1-К10 учитель ведёт вручную).
-- Существующая INSERT-политика проверяла auth.uid() = student_id
-- (только сам ученик мог сдать), и блокировала импорт.
-- =========================================================

-- Расширяем INSERT на essays: ученик (auth.uid() = student_id)
-- ИЛИ учитель / куратор (для импорта и ручного создания)
DROP POLICY IF EXISTS "essays_insert" ON essays;
CREATE POLICY "essays_insert" ON essays FOR INSERT TO authenticated WITH CHECK (
  student_id = auth.uid()
  OR is_teacher()
  OR is_curator()
);

-- На всякий случай — UPDATE тоже разрешаем учителю/куратору
-- (для коррекции импортированных работ).
DROP POLICY IF EXISTS "essays_update" ON essays;
CREATE POLICY "essays_update" ON essays FOR UPDATE TO authenticated USING (
  student_id = auth.uid() OR is_teacher() OR is_curator()
) WITH CHECK (
  student_id = auth.uid() OR is_teacher() OR is_curator()
);

-- essay_reviews — учитель уже может через существующую политику,
-- но на всякий случай явно проверим INSERT/UPDATE.
DROP POLICY IF EXISTS "essay_reviews_insert" ON essay_reviews;
CREATE POLICY "essay_reviews_insert" ON essay_reviews FOR INSERT TO authenticated WITH CHECK (
  is_teacher() OR is_curator()
);

DROP POLICY IF EXISTS "essay_reviews_update" ON essay_reviews;
CREATE POLICY "essay_reviews_update" ON essay_reviews FOR UPDATE TO authenticated USING (
  is_teacher() OR is_curator()
) WITH CHECK (
  is_teacher() OR is_curator()
);

-- Проверка
SELECT 'essays_insert teacher/curator ok' AS status;
