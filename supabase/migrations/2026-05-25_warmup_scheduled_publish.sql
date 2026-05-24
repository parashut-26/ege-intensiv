-- Отложенная публикация постов «Разогрев» и дней интенсива.
--
-- До этой миграции учитель открывал/закрывал дни и посты только бинарным
-- флагом is_published. Чтобы новый материал автоматически появлялся у
-- учеников в назначенное время (например утром в 8:00), вводим колонку
-- publish_at:
--   NULL  → опубликовать сразу при is_published = true (поведение как было)
--   timestamptz → не показывать ученику пока now() < publish_at, даже
--                  если is_published = true.
--
-- Фильтрация — на клиенте (helper isWarmupVisibleToStudent в index.html).
-- Сделано клиентским фильтром, чтобы учитель в своём кабинете видел всё
-- (включая запланированное) и мог планировать наперёд.

ALTER TABLE warmup_days
  ADD COLUMN IF NOT EXISTS publish_at timestamptz NULL;

ALTER TABLE warmup_blocks
  ADD COLUMN IF NOT EXISTS publish_at timestamptz NULL;

COMMENT ON COLUMN warmup_days.publish_at IS
  'Отложенная публикация: NULL = сразу при is_published; иначе не раньше этого момента';

COMMENT ON COLUMN warmup_blocks.publish_at IS
  'Отложенная публикация: NULL = сразу при is_published; иначе не раньше этого момента';

-- Индекс для будущей серверной фильтрации (на случай если перейдём
-- с клиентского фильтра на view-level). Сейчас не используется, но
-- дешёвый — пусть будет.
CREATE INDEX IF NOT EXISTS idx_warmup_days_publish_at
  ON warmup_days(publish_at) WHERE publish_at IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_warmup_blocks_publish_at
  ON warmup_blocks(publish_at) WHERE publish_at IS NOT NULL;
