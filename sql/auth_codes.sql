-- ============================================================
-- Таблица одноразовых кодов для входа без VPN
-- (обход блокировки /auth/v1 в РФ)
-- ============================================================

CREATE TABLE IF NOT EXISTS auth_codes (
  email      TEXT NOT NULL,
  code       TEXT NOT NULL,
  expires_at TIMESTAMPTZ NOT NULL,
  used       BOOLEAN DEFAULT FALSE,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_auth_codes_email_created
  ON auth_codes (email, created_at DESC);

-- RLS: только service_role пишет/читает (через Edge Functions)
ALTER TABLE auth_codes ENABLE ROW LEVEL SECURITY;

-- Никаких политик для anon / authenticated — только service_role имеет доступ
-- (service_role игнорирует RLS).
