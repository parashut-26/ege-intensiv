-- Игра №9 серии «гонок за фразеологизмами» — Песочная гонка (Египет).
-- Тема — фразеологизмы о времени, временных ориентирах и длительности,
-- 15 заданий (в № 1 — два фразеологизма: только что + поднял глаза).
-- Запускать после sql/add_games.sql.

INSERT INTO games (slug, title, topic, emoji, description, url, is_published)
VALUES (
  'egypt',
  'Песочная гонка',
  'Фразеологизмы времени',
  '🐪',
  'Пески Сахары, 15 заданий. Фразеологизмы о времени, временных ориентирах и длительности. Кликай по словам, чтобы выделить фразеологизм; балл засчитывается за любой полностью найденный.',
  '/games/egypt/',
  FALSE
)
ON CONFLICT (slug) DO UPDATE SET
  title       = EXCLUDED.title,
  topic       = EXCLUDED.topic,
  emoji       = EXCLUDED.emoji,
  description = EXCLUDED.description;

SELECT 'egypt synced' AS status,
  (SELECT COUNT(*) FROM games) AS games_count;
