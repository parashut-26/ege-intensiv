-- =========================================================
-- РЕДАКТИРОВАНИЕ СВОИХ СООБЩЕНИЙ В ЧАТЕ
--   1) Колонка edited_at — для отметки «(изм.)» (опц.)
--   2) RLS policy: автор может PATCH body своих сообщений
-- =========================================================

ALTER TABLE chat_messages
  ADD COLUMN IF NOT EXISTS edited_at TIMESTAMPTZ;

-- Удаляем старую msgs_helped, если она ограничивала только UPDATE учителями
-- и заменяем на политику: либо учитель/куратор, либо автор сам.
DROP POLICY IF EXISTS "msgs_helped" ON chat_messages;
CREATE POLICY "msgs_update" ON chat_messages FOR UPDATE TO authenticated
  USING (is_teacher() OR is_curator() OR author_id = auth.uid())
  WITH CHECK (is_teacher() OR is_curator() OR author_id = auth.uid());

SELECT 'chat_messages.edited_at + msgs_update ok' AS status;
