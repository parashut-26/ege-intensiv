-- ============================================================
-- Миграция: разрешения для чата
-- Запустить однократно в Supabase SQL Editor.
--
-- Что добавляет:
--   1. INSERT-политику на chat_rooms — учитель может создать комнату.
--   2. Послабляет SELECT на chat_rooms — любой авторизованный видит общие
--      group-комнаты (потому что enrollments может быть пустым для тестовых
--      аккаунтов и гостей; на интенсиве это ок — там все участники доверенные).
--   3. Создаёт ОДНУ группу-комнату для общего чата интенсива.
-- ============================================================

-- 1. Учитель может создавать комнаты
DROP POLICY IF EXISTS "rooms_insert" ON chat_rooms;
CREATE POLICY "rooms_insert" ON chat_rooms FOR INSERT TO authenticated
  WITH CHECK (is_teacher());

-- 2. Чтение комнат: переписываем — group-комнаты видят все авторизованные,
--    dm-комнаты — только участники и учитель/куратор.
DROP POLICY IF EXISTS "rooms_read" ON chat_rooms;
CREATE POLICY "rooms_read" ON chat_rooms FOR SELECT TO authenticated USING (
  kind = 'group'
  OR is_teacher() OR is_curator()
  OR participant_a = auth.uid() OR participant_b = auth.uid()
);

-- 3. Чтение сообщений — соответственно тоже послабляем для group
DROP POLICY IF EXISTS "msgs_read" ON chat_messages;
CREATE POLICY "msgs_read" ON chat_messages FOR SELECT TO authenticated USING (
  EXISTS(SELECT 1 FROM chat_rooms r WHERE r.id = room_id AND (
    r.kind = 'group'
    OR is_teacher() OR is_curator()
    OR r.participant_a = auth.uid() OR r.participant_b = auth.uid()
  ))
);

-- 4. Создаём общую комнату, если её ещё нет
INSERT INTO chat_rooms (kind, intensive_id)
SELECT 'group', NULL
WHERE NOT EXISTS (
  SELECT 1 FROM chat_rooms WHERE kind = 'group' AND intensive_id IS NULL
);

-- 5. Проверка — должна вернуть 1 строку
SELECT id, kind, intensive_id, created_at FROM chat_rooms WHERE kind = 'group';
