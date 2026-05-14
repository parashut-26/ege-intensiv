-- =========================================================
-- Привязка исходного текста к сочинению.
-- Ученик при сдаче выбирает: из варианта пробника или вписывает свой текст.
-- AI-проверка использует это, чтобы оценивать К1 (проблема) и К2 (комментарий).
-- =========================================================

ALTER TABLE essays
  ADD COLUMN IF NOT EXISTS source_text       TEXT,
  ADD COLUMN IF NOT EXISTS source_problem    TEXT,
  ADD COLUMN IF NOT EXISTS source_variant_id INTEGER REFERENCES test_variants(id) ON DELETE SET NULL;

-- Индекс на variant_id — пригодится при выборке всех сочинений по варианту
CREATE INDEX IF NOT EXISTS idx_essays_source_variant_id ON essays(source_variant_id);

-- Проверка
SELECT 'essays.source_* ok' AS status;
