-- Игра №6 серии «гонок за фразеологизмами» — Сафари-гонка.
-- Тема — фразеологизмы об отказе, бесполезности и невозможности, 8 заданий.
-- Запускать после sql/add_games.sql.

INSERT INTO games (slug, title, topic, emoji, description, url, is_published)
VALUES (
  'savannah',
  'Сафари-гонка',
  'Фразеологизмы отказа',
  '🦓',
  'Африканская саванна на закате, 8 заданий. Фразеологизмы об отказе, бесполезности и невозможности. Кликай по словам, чтобы выделить фразеологизм; балл засчитывается за любой полностью найденный.',
  '/games/savannah/',
  FALSE
)
ON CONFLICT (slug) DO UPDATE SET
  title       = EXCLUDED.title,
  topic       = EXCLUDED.topic,
  emoji       = EXCLUDED.emoji,
  description = EXCLUDED.description;

SELECT 'savannah synced' AS status,
  (SELECT COUNT(*) FROM games) AS games_count;
