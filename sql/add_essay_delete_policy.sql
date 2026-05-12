-- =========================================================
-- УДАЛЕНИЕ СОЧИНЕНИЙ УЧИТЕЛЕМ/КУРАТОРОМ
-- RLS политика DELETE на essays.
-- Только учитель/куратор может удалить (для очистки от тестовых
-- и ошибочно сданных работ). Ученик не может — он может только пересдать.
--
-- CASCADE: связанные essay_reviews и essay_comments удаляются автоматически
-- через FK ON DELETE CASCADE (если эти FK уже стоят; если нет — будут
-- сиротинами, но это уже не критично).
-- =========================================================

DROP POLICY IF EXISTS "essays_delete" ON essays;
CREATE POLICY "essays_delete" ON essays FOR DELETE TO authenticated USING (
  is_teacher() OR is_curator()
);

-- Проверка
SELECT 'essays_delete policy active' AS status;
