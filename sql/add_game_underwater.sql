-- Игра №5 серии «гонок за фразеологизмами» — Подводная гонка.
-- Тема — фразеологизмы о бессилии, упадке и истощении, 12 заданий
-- (в № 9 — два фразеологизма: всё равно + нет дела).
-- Запускать после sql/add_games.sql.

INSERT INTO games (slug, title, topic, emoji, description, url, is_published)
VALUES (
  'underwater',
  'Подводная гонка',
  'Фразеологизмы бессилия',
  '🐢',
  'Коралловый риф, 12 заданий. Фразеологизмы о бессилии, упадке и истощении. Кликай по словам, чтобы выделить фразеологизм; балл засчитывается за любой полностью найденный.',
  '/games/underwater/',
  FALSE
)
ON CONFLICT (slug) DO UPDATE SET
  title       = EXCLUDED.title,
  topic       = EXCLUDED.topic,
  emoji       = EXCLUDED.emoji,
  description = EXCLUDED.description;

SELECT 'underwater synced' AS status,
  (SELECT COUNT(*) FROM games) AS games_count;
