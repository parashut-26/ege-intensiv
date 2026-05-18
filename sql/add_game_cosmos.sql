-- Игра №8 серии «гонок за фразеологизмами» — Космическая гонка.
-- Тема — фразеологизмы о пространстве, движении и расположении,
-- 14 заданий (в № 6 — два фразеологизма: шаг в шаг + бок о бок).
-- Запускать после sql/add_games.sql.

INSERT INTO games (slug, title, topic, emoji, description, url, is_published)
VALUES (
  'cosmos',
  'Космическая гонка',
  'Фразеологизмы пространства',
  '🚀',
  'Гиперпрыжок к далёкой планете, 14 заданий. Фразеологизмы о пространстве, движении и расположении. Кликай по словам, чтобы выделить фразеологизм; балл засчитывается за любой полностью найденный.',
  '/games/cosmos/',
  FALSE
)
ON CONFLICT (slug) DO UPDATE SET
  title       = EXCLUDED.title,
  topic       = EXCLUDED.topic,
  emoji       = EXCLUDED.emoji,
  description = EXCLUDED.description;

SELECT 'cosmos synced' AS status,
  (SELECT COUNT(*) FROM games) AS games_count;
