-- =========================================================
-- ТАБЛИЦА ПРЕДЛОЖЕНИЙ ОТ TG-БОТА ОБ ОПЛАТЕ
--
-- Сценарий:
--   1. Учитель пересылает уведомление от Т-банка из Telegram
--      в @ZebrusPayBot (или настраивает автопересылку).
--   2. Edge Function tg-payment-webhook парсит сообщение
--      (сумма, ФИО, дата), ищет ученика в profiles по ФИО.
--   3. Создаёт строку в payment_suggestions с status='pending'.
--   4. Учитель на дашборде видит список предложений, жмёт
--      ☑ — запись копируется в payments, suggestion помечается 'applied'.
--   ✕ — suggestion 'dismissed' (не создавая платёж).
-- =========================================================

CREATE TABLE IF NOT EXISTS payment_suggestions (
  id            BIGSERIAL PRIMARY KEY,
  -- Сырое сообщение из Telegram (для проверки/дебага)
  raw_message   TEXT NOT NULL,
  -- Распарсенные поля
  amount        INTEGER NOT NULL,        -- в рублях
  payer_name    TEXT,                    -- что распарсилось из «от ...»
  payment_date  TIMESTAMPTZ,             -- дата операции (если есть в сообщении)
  -- Кому из БД может соответствовать (NULL = не нашлось совпадений)
  matched_student_id  UUID REFERENCES profiles(id) ON DELETE SET NULL,
  -- Альтернативные кандидаты (если совпали несколько по фамилии)
  candidates    JSONB DEFAULT '[]'::jsonb,
  status        TEXT NOT NULL DEFAULT 'pending'
                CHECK (status IN ('pending', 'applied', 'dismissed')),
  -- Кто и когда применил/отклонил
  resolved_by   UUID REFERENCES profiles(id) ON DELETE SET NULL,
  resolved_at   TIMESTAMPTZ,
  -- Если применили — id созданной записи в payments
  applied_payment_id  INTEGER,
  -- Когда пришло
  received_at   TIMESTAMPTZ DEFAULT NOW(),
  -- Источник
  source        TEXT DEFAULT 'telegram' CHECK (source IN ('telegram', 'email', 'manual'))
);

CREATE INDEX IF NOT EXISTS idx_pay_sugg_pending  ON payment_suggestions(status, received_at DESC);
CREATE INDEX IF NOT EXISTS idx_pay_sugg_student  ON payment_suggestions(matched_student_id);

-- RLS — только учитель/куратор видит и обрабатывает
ALTER TABLE payment_suggestions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "paysugg_staff_all" ON payment_suggestions;
CREATE POLICY "paysugg_staff_all" ON payment_suggestions
  FOR ALL TO authenticated
  USING (is_teacher() OR is_curator())
  WITH CHECK (is_teacher() OR is_curator());

SELECT 'payment_suggestions ok' AS status;
