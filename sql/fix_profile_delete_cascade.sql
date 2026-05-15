-- =========================================================
-- ФИКС: DELETE profiles падает на FK chat_rooms / chat_messages.
--
-- Симптом:
--   DELETE /profiles?id=eq.<student_id> → 409
--   "Key is still referenced from table chat_rooms"
--   chat_rooms_participant_b_fkey violation
--
-- Причина:
--   FK chat_rooms.participant_a/b → profiles(id) — БЕЗ ON DELETE.
--   Аналогично chat_messages.author_id, marked_helped_by.
--   PostgreSQL по умолчанию = NO ACTION (запрет удаления).
--
-- Лечение:
--   1) chat_rooms.participant_a/b → ON DELETE CASCADE
--      (удаляем DM-комнату вместе с участником — они и так бесполезны)
--   2) chat_messages.author_id → ON DELETE SET NULL
--      (сохраняем сообщения как «от удалённого пользователя»)
--   3) chat_messages.marked_helped_by → ON DELETE SET NULL
--      (если помогавший удалён — просто очищаем поле)
-- =========================================================

-- chat_rooms: участники DM
ALTER TABLE chat_rooms
  DROP CONSTRAINT IF EXISTS chat_rooms_participant_a_fkey;
ALTER TABLE chat_rooms
  ADD CONSTRAINT chat_rooms_participant_a_fkey
    FOREIGN KEY (participant_a) REFERENCES profiles(id) ON DELETE CASCADE;

ALTER TABLE chat_rooms
  DROP CONSTRAINT IF EXISTS chat_rooms_participant_b_fkey;
ALTER TABLE chat_rooms
  ADD CONSTRAINT chat_rooms_participant_b_fkey
    FOREIGN KEY (participant_b) REFERENCES profiles(id) ON DELETE CASCADE;

-- chat_messages: автор + кто пометил «помогло»
ALTER TABLE chat_messages
  DROP CONSTRAINT IF EXISTS chat_messages_author_id_fkey;
ALTER TABLE chat_messages
  ADD CONSTRAINT chat_messages_author_id_fkey
    FOREIGN KEY (author_id) REFERENCES profiles(id) ON DELETE SET NULL;

ALTER TABLE chat_messages
  DROP CONSTRAINT IF EXISTS chat_messages_marked_helped_by_fkey;
ALTER TABLE chat_messages
  ADD CONSTRAINT chat_messages_marked_helped_by_fkey
    FOREIGN KEY (marked_helped_by) REFERENCES profiles(id) ON DELETE SET NULL;

-- Проверка
SELECT 'profile delete FK fix ok' AS status;
