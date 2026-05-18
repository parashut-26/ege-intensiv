-- Игра №4 серии «гонок за фразеологизмами» — Японская гонка.
-- Тема — фразеологизмы о силе воли, действии и эмоциях в трудный
-- момент, 16 заданий (в № 11 — два фразеологизма).
-- Запускать после sql/add_games.sql.

INSERT INTO games (slug, title, topic, emoji, description, url, is_published)
VALUES (
  'sakura',
  'Японская гонка',
  'Фразеологизмы действия',
  '🌸',
  'Сад сакуры, 16 заданий. Фразеологизмы о силе воли, эмоциях и действии в трудный момент. Кликай по словам, чтобы выделить фразеологизм; балл засчитывается за любой полностью найденный.',
  '/games/sakura/',
  FALSE
)
ON CONFLICT (slug) DO UPDATE SET
  title       = EXCLUDED.title,
  topic       = EXCLUDED.topic,
  emoji       = EXCLUDED.emoji,
  description = EXCLUDED.description;

SELECT 'sakura synced' AS status,
  (SELECT COUNT(*) FROM games) AS games_count;
