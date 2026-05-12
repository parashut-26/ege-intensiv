-- =========================================================
-- Привязка сочинения к попытке варианта.
-- Учитель в сводной может ВРУЧНУЮ выбрать какое сочинение
-- считать «работой 27 в рамках этого варианта». Если NULL —
-- платформа берёт ближайшее по дате финализированное сочинение.
-- =========================================================

ALTER TABLE test_variant_attempts
  ADD COLUMN IF NOT EXISTS essay_id INTEGER REFERENCES essays(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS test_variant_attempts_essay_idx
  ON test_variant_attempts(essay_id) WHERE essay_id IS NOT NULL;

-- Проверка
SELECT 'variant.essay_id ok' AS status;
