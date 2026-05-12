-- =========================================================
-- WEB PUSH ПОДПИСКИ В БРАУЗЕРЕ
-- Один пользователь может иметь несколько подписок (iPhone, ноут, ПК).
-- Endpoint уникален — один браузер = одна подписка.
-- =========================================================

CREATE TABLE IF NOT EXISTS push_subscriptions (
  id           SERIAL PRIMARY KEY,
  user_id      UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  endpoint     TEXT NOT NULL UNIQUE,
  p256dh       TEXT NOT NULL,
  auth         TEXT NOT NULL,
  user_agent   TEXT,
  created_at   TIMESTAMPTZ DEFAULT NOW(),
  last_seen_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS push_subscriptions_user_id_idx ON push_subscriptions(user_id);

ALTER TABLE push_subscriptions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "push_self_select" ON push_subscriptions;
CREATE POLICY "push_self_select" ON push_subscriptions
  FOR SELECT USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "push_self_insert" ON push_subscriptions;
CREATE POLICY "push_self_insert" ON push_subscriptions
  FOR INSERT WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "push_self_delete" ON push_subscriptions;
CREATE POLICY "push_self_delete" ON push_subscriptions
  FOR DELETE USING (auth.uid() = user_id);

-- Проверка
SELECT COUNT(*) AS total_subs FROM push_subscriptions;
