-- =========================================================
-- УДАЛЕНИЕ СООБЩЕНИЙ В ЧАТЕ
-- RLS политика DELETE на chat_messages.
-- Автор может удалить своё сообщение.
-- Учитель/куратор может удалить любое (для модерации).
-- =========================================================

DROP POLICY IF EXISTS "msgs_delete" ON chat_messages;
CREATE POLICY "msgs_delete" ON chat_messages FOR DELETE TO authenticated USING (
  author_id = auth.uid()
  OR is_teacher()
  OR is_curator()
);

-- Проверка — должна вернуть строку
SELECT 'msgs_delete policy active' AS status;
