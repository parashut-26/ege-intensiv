-- =============================================================================
-- 2026-05-25 — fix: добавить UNIQUE CONSTRAINTS в warmup_views для ON CONFLICT
-- =============================================================================
-- Прецедент: после первой миграции warmup_views логирование падало с
--   REST POST /warmup_views?on_conflict=user_id,day_id → 400:
--   {"code":"42P10","message":"there is no unique or exclusion constraint
--    matching the ON CONFLICT specification"}
--
-- Причина: в первой миграции я создала CREATE UNIQUE INDEX (partial, WHERE
-- day_id IS NOT NULL). PostgREST для on_conflict требует именно UNIQUE
-- CONSTRAINT, а не unique index. Это разные сущности в PostgreSQL — индекс
-- обеспечивает уникальность, но on_conflict.* команды ищут constraint
-- по имени или по списку колонок.
--
-- Решение: добавить полноценные UNIQUE constraints. NULL в (user_id, day_id)
-- при block_id != NULL не мешает — PostgreSQL трактует NULL как «не равно
-- ничему», поэтому несколько строк с (X, NULL, block_id=Y) разрешены, и наш
-- CHECK (day_id XOR block_id) продолжает работать.
--
-- Старые partial-индексы можно удалить (дублируют constraint), но они не
-- мешают и могут пригодиться для производительности — оставляем.
-- =============================================================================

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'warmup_views_user_day_uniq'
      AND conrelid = 'warmup_views'::regclass
  ) THEN
    ALTER TABLE warmup_views
      ADD CONSTRAINT warmup_views_user_day_uniq UNIQUE (user_id, day_id);
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'warmup_views_user_block_uniq'
      AND conrelid = 'warmup_views'::regclass
  ) THEN
    ALTER TABLE warmup_views
      ADD CONSTRAINT warmup_views_user_block_uniq UNIQUE (user_id, block_id);
  END IF;
END $$;

-- Проверка: вывести существующие constraints для warmup_views
DO $$
DECLARE
  cnames text;
BEGIN
  SELECT string_agg(conname, ', ') INTO cnames
  FROM pg_constraint
  WHERE conrelid = 'warmup_views'::regclass
    AND contype = 'u';
  RAISE NOTICE 'UNIQUE constraints на warmup_views: %', COALESCE(cnames, '(нет)');
END $$;
