-- =============================================================================
-- 2026-05-30 — посты для прогулочных дней
-- =============================================================================
-- Прецедент: 30.05.2026 учительница хочет, чтобы в прогулочные дни (walk1/
-- walk2/walk3 между Днями интенсива) можно было постить контент в том же
-- формате, что и в Разогреве и в Днях интенсива — текст + картинки + видео +
-- игры. Сейчас walks работают через старую отдельную систему walk_materials
-- (аудио/картинка/текст/ссылка) — менее гибкую.
--
-- Решение: переиспользуем существующую таблицу warmup_blocks, добавив третий
-- «таргет»: walk_id (text). До этого было только day_id (для разогрева) и
-- intensive_day_ord (для Дней 1/2/3).
--
-- walk_id будет принимать значения 'walk1', 'walk2', 'walk3' (как DAYS.id
-- прогулочных дней на клиенте). Один из трёх таргетов должен быть заполнен.
-- =============================================================================

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'warmup_blocks'
      AND column_name = 'walk_id'
  ) THEN
    ALTER TABLE warmup_blocks
      ADD COLUMN walk_id text;
    CREATE INDEX warmup_blocks_walk_id_idx
      ON warmup_blocks(walk_id) WHERE walk_id IS NOT NULL;
  END IF;
END $$;

COMMENT ON COLUMN warmup_blocks.walk_id IS
  'ID прогулочного дня (walk1/walk2/walk3). Заполняется только для постов в прогулочных днях. Взаимоисключающе с day_id (разогрев) и intensive_day_ord (Дни интенсива).';

-- Проверка
DO $$
DECLARE
  c int;
BEGIN
  SELECT COUNT(*) INTO c FROM warmup_blocks WHERE walk_id IS NOT NULL;
  RAISE NOTICE 'warmup_blocks: записей с walk_id = %', c;
END $$;
