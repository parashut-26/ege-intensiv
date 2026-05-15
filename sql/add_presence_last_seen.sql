-- =========================================================
-- ОНЛАЙН-ПРИСУТСТВИЕ: profiles.last_seen_at
--
-- Каждые 30 сек залогиненный пользователь PATCHит свою строку
-- (last_seen_at = NOW()). Учитель/куратор каждые 30 сек подтягивают
-- эти значения и показывают зелёную точку у тех, у кого
-- last_seen_at > NOW() - 60 секунд.
--
-- RLS: каждый и так уже может обновлять свою строку
--      (политика profiles_self_update). Дополнительно ничего не надо.
-- =========================================================

ALTER TABLE profiles
  ADD COLUMN IF NOT EXISTS last_seen_at TIMESTAMPTZ;

CREATE INDEX IF NOT EXISTS idx_profiles_last_seen ON profiles(last_seen_at DESC);

SELECT 'profiles.last_seen_at ok' AS status;
