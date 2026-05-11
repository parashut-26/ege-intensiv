-- =========================================================
-- ПРИВЯЗКА TELEGRAM К ПРОФИЛЯМ + UPDATE-ПОЛИТИКА
-- Прогон руками в Supabase SQL Editor.
-- =========================================================

-- 1) Колонки в profiles
ALTER TABLE profiles
  ADD COLUMN IF NOT EXISTS telegram_id          BIGINT,
  ADD COLUMN IF NOT EXISTS telegram_link_token  TEXT,
  ADD COLUMN IF NOT EXISTS tg_notify_enabled    BOOLEAN NOT NULL DEFAULT TRUE,
  ADD COLUMN IF NOT EXISTS telegram_name        TEXT;

-- 2) Уникальность telegram_id и токена (для быстрых лукапов в webhook)
CREATE UNIQUE INDEX IF NOT EXISTS profiles_telegram_id_uniq
  ON profiles(telegram_id) WHERE telegram_id IS NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS profiles_telegram_link_token_uniq
  ON profiles(telegram_link_token) WHERE telegram_link_token IS NOT NULL;

-- 3) RLS: разрешить пользователю обновлять СВОЁ поле telegram_link_token и tg_notify_enabled.
--    Webhook сам ходит через service_role и не подпадает под RLS — это нормально.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename  = 'profiles'
      AND policyname = 'profiles_self_update_tg'
  ) THEN
    CREATE POLICY profiles_self_update_tg ON profiles
      FOR UPDATE
      USING (auth.uid() = id)
      WITH CHECK (auth.uid() = id);
  END IF;
END $$;

-- 4) Проверка — должна вернуть 4 строки
SELECT column_name, data_type, is_nullable
  FROM information_schema.columns
 WHERE table_schema = 'public'
   AND table_name   = 'profiles'
   AND column_name IN ('telegram_id', 'telegram_link_token', 'tg_notify_enabled', 'telegram_name')
 ORDER BY column_name;
