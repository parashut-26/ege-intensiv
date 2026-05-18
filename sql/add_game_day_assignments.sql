-- =========================================================
-- 1) Переименование всех игр серии «гонок за фразеологизмами»
--    в одну общую тему «Фразеологизмы». Папка теперь одна на
--    все 9 (потом 12) игр серии. Когда добавим другие темы
--    ЕГЭ (Паронимы, Ударения и т.п.) — будут отдельные папки.
--
-- 2) Создание таблицы game_day_assignments — одна игра может
--    быть прикреплена к нескольким дням интенсива.
-- =========================================================

-- 1. Все игры — в одну папку
UPDATE games SET topic = 'Фразеологизмы'
WHERE slug IN (
  'race-phraseo', 'winter-forest', 'paris-night', 'sakura',
  'underwater', 'savannah', 'greece', 'cosmos', 'egypt'
);

-- 2. Таблица привязок игра ↔ день интенсива (many-to-many)
CREATE TABLE IF NOT EXISTS game_day_assignments (
  id         SERIAL PRIMARY KEY,
  game_id    INTEGER NOT NULL REFERENCES games(id) ON DELETE CASCADE,
  day_id     INTEGER NOT NULL REFERENCES intensive_days(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE(game_id, day_id)
);

CREATE INDEX IF NOT EXISTS gda_game_idx ON game_day_assignments(game_id);
CREATE INDEX IF NOT EXISTS gda_day_idx  ON game_day_assignments(day_id);

ALTER TABLE game_day_assignments ENABLE ROW LEVEL SECURITY;

-- Читать может любой авторизованный (ученики тоже видят, какие игры в дне)
DROP POLICY IF EXISTS "gda_read" ON game_day_assignments;
CREATE POLICY "gda_read" ON game_day_assignments
  FOR SELECT TO authenticated USING (TRUE);

-- Писать/удалять — только учитель и куратор
DROP POLICY IF EXISTS "gda_write" ON game_day_assignments;
CREATE POLICY "gda_write" ON game_day_assignments
  FOR ALL TO authenticated
  USING (is_teacher() OR is_curator())
  WITH CHECK (is_teacher() OR is_curator());

-- Проверка
SELECT 'games_topic_updated' AS status,
  (SELECT COUNT(*) FROM games WHERE topic = 'Фразеологизмы') AS phraseo_count,
  (SELECT COUNT(*) FROM game_day_assignments) AS assignments_count;
