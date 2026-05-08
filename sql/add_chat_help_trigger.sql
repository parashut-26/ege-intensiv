-- ============================================================
-- Миграция: триггер, начисляющий пчёлки при INSERT в bee_transactions
-- с source_kind = 'chat_help'.
--
-- Зачем триггер, а не PATCH profiles.bee из клиента:
--   1. У куратора нет прав на UPDATE чужих profiles по RLS, а на
--      INSERT в bee_transactions — есть. Триггер использует
--      SECURITY DEFINER и обходит RLS.
--   2. Атомарность: INSERT и UPDATE происходят в одной транзакции.
--   3. Никакой race condition между параллельными INSERT'ами.
--
-- Запустить однократно в Supabase SQL Editor.
-- ============================================================

CREATE OR REPLACE FUNCTION on_chat_help_insert() RETURNS TRIGGER AS $$
BEGIN
  IF NEW.source_kind = 'chat_help' AND NEW.amount > 0 THEN
    UPDATE profiles
       SET bee = COALESCE(bee, 0) + NEW.amount
     WHERE id = NEW.student_id;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trg_chat_help_insert ON bee_transactions;
CREATE TRIGGER trg_chat_help_insert
  AFTER INSERT ON bee_transactions
  FOR EACH ROW EXECUTE FUNCTION on_chat_help_insert();

-- Проверка
SELECT 'Триггер trg_chat_help_insert создан' AS status;
