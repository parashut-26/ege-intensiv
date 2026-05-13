-- =========================================================
-- Гибридная регистрация учеников: коды-приглашения и ссылки-входы.
-- А) Код-приглашение: учитель создаёт код, ученик вводит имя+код,
--    профиль создаётся автоматически и привязывается к группе.
-- Б) Ссылка-вход: учитель пред-создаёт ученика и получает одноразовую
--    ссылку, кидает ему в Telegram/WhatsApp, он по клику входит.
-- =========================================================

-- 1. Коды-приглашения (один код = много учеников могут зарегистрироваться)
CREATE TABLE IF NOT EXISTS invite_codes (
  id           SERIAL PRIMARY KEY,
  code         TEXT NOT NULL UNIQUE,
  title        TEXT,                  -- для удобства учителя «Краш-тест май 2026»
  max_uses     INTEGER,                -- NULL = без лимита
  used_count   INTEGER NOT NULL DEFAULT 0,
  expires_at   TIMESTAMPTZ,            -- NULL = бессрочно (можно отозвать вручную)
  is_active    BOOLEAN NOT NULL DEFAULT TRUE,
  created_by   UUID REFERENCES profiles(id),
  created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS invite_codes_code_idx ON invite_codes(code);
CREATE INDEX IF NOT EXISTS invite_codes_active_idx ON invite_codes(is_active);

-- 2. Одноразовые токены логина (под конкретного существующего ученика)
CREATE TABLE IF NOT EXISTS login_tokens (
  token         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  profile_id    UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  expires_at    TIMESTAMPTZ NOT NULL DEFAULT (NOW() + INTERVAL '14 days'),
  used_at       TIMESTAMPTZ,
  created_by    UUID REFERENCES profiles(id),
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS login_tokens_profile_idx ON login_tokens(profile_id);

-- ---------------------------------------------------------
-- RLS
-- ---------------------------------------------------------
ALTER TABLE invite_codes ENABLE ROW LEVEL SECURITY;
ALTER TABLE login_tokens ENABLE ROW LEVEL SECURITY;

-- invite_codes: учитель/куратор видят и управляют. Edge Function использует
-- service-role и обходит RLS — для самого redeem'а.
DROP POLICY IF EXISTS "ic_teacher" ON invite_codes;
CREATE POLICY "ic_teacher" ON invite_codes FOR ALL TO authenticated
  USING (is_teacher() OR is_curator())
  WITH CHECK (is_teacher() OR is_curator());

-- login_tokens: только учитель/куратор видит и создаёт
DROP POLICY IF EXISTS "lt_teacher" ON login_tokens;
CREATE POLICY "lt_teacher" ON login_tokens FOR ALL TO authenticated
  USING (is_teacher() OR is_curator())
  WITH CHECK (is_teacher() OR is_curator());

-- Проверка
SELECT 'invite_codes & login_tokens ok' AS status;
