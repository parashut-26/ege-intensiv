-- Игра №3 серии «гонок за фразеологизмами» — Парижская гонка.
-- Тема — фразеологизмы об общении и разговоре, 15 заданий.
-- Запускать после sql/add_games.sql.

INSERT INTO games (slug, title, topic, emoji, description, url, is_published)
VALUES (
  'paris-night',
  'Парижская гонка',
  'Фразеологизмы общения',
  '🚕',
  'Ночные бульвары Парижа, 15 заданий. Фразеологизмы об общении и разговоре. Кликай по словам, чтобы выделить фразеологизм; балл засчитывается за любой полностью найденный.',
  '/games/paris-night/',
  FALSE
)
ON CONFLICT (slug) DO UPDATE SET
  title       = EXCLUDED.title,
  topic       = EXCLUDED.topic,
  emoji       = EXCLUDED.emoji,
  description = EXCLUDED.description;

SELECT 'paris-night synced' AS status,
  (SELECT COUNT(*) FROM games) AS games_count;
