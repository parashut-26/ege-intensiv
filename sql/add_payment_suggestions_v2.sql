-- =========================================================
-- V2: расширяем payment_suggestions полями из формата tb.ru
-- (email, телефон, номер операции, описание заказа)
-- + UNIQUE на operation_id для дедупа повторных пересылок
-- =========================================================

ALTER TABLE payment_suggestions
  ADD COLUMN IF NOT EXISTS payer_email      TEXT,
  ADD COLUMN IF NOT EXISTS payer_phone      TEXT,
  ADD COLUMN IF NOT EXISTS operation_id     TEXT,
  ADD COLUMN IF NOT EXISTS order_description TEXT;

-- Дедуп: один и тот же платёж нельзя засунуть дважды.
-- NULL не считается равным NULL в UNIQUE — это нам подходит:
-- старые записи (без operation_id) не блокируются.
CREATE UNIQUE INDEX IF NOT EXISTS idx_pay_sugg_operation
  ON payment_suggestions(operation_id)
  WHERE operation_id IS NOT NULL;

-- Поиск по email для UI (когда учитель ищет «по почте»)
CREATE INDEX IF NOT EXISTS idx_pay_sugg_email
  ON payment_suggestions(payer_email)
  WHERE payer_email IS NOT NULL;

SELECT 'payment_suggestions v2 ok' AS status;
