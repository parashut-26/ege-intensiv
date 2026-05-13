-- =========================================================
-- Привязка варианта-пробника к конкретному дню интенсива.
-- Учитель может указать, что вариант «принадлежит» дню N
-- (например, «Вариант 1 ждёт учеников 30 мая»). Ученик в
-- расписании дня увидит баннер «Сегодня решаем Вариант N».
-- =========================================================

ALTER TABLE test_variants
  ADD COLUMN IF NOT EXISTS day_id INTEGER;  -- id дня интенсива (1..N)

CREATE INDEX IF NOT EXISTS test_variants_day_idx
  ON test_variants(day_id) WHERE day_id IS NOT NULL;

-- Проверка
SELECT 'variant.day_id ok' AS status;
