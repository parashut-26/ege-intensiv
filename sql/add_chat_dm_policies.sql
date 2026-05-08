-- ============================================================
-- Миграция: разрешения для личных сообщений (DM)
-- Запустить однократно в Supabase SQL Editor (после add_chat_policies.sql).
--
-- Что добавляет:
--   1. Расширяет INSERT-политику chat_rooms — ученик может создать
--      DM, в котором он сам один из участников (a или b). Это позволяет
--      ребёнку начать переписку с учителем/куратором без вмешательства
--      учителя.
--   2. Уникальный индекс на пары участников DM — предотвращает
--      создание дублирующих комнат для одной и той же пары.
-- ============================================================

-- 1. Разрешаем создавать DM, если ты сам в нём участник
DROP POLICY IF EXISTS "rooms_insert" ON chat_rooms;
CREATE POLICY "rooms_insert" ON chat_rooms FOR INSERT TO authenticated
  WITH CHECK (
    is_teacher()
    OR (kind = 'dm' AND (participant_a = auth.uid() OR participant_b = auth.uid()))
  );

-- 2. Уникальная пара участников для DM (independent от порядка a/b).
--    Используем least/greatest — чтобы (A,B) и (B,A) считались одной парой.
CREATE UNIQUE INDEX IF NOT EXISTS chat_rooms_dm_unique_pair
  ON chat_rooms (
    kind,
    LEAST(participant_a, participant_b),
    GREATEST(participant_a, participant_b)
  )
  WHERE kind = 'dm';

-- Проверка
SELECT 'rooms_insert policy active' AS status;
