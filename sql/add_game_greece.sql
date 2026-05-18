-- Игра №7 серии «гонок за фразеологизмами» — Греческая гонка.
-- Тема — фразеологизмы-вводные, связки, оформление речи; риторика
-- и логика диалога. 17 заданий (в №2 и №13 — по два фразеологизма).
-- Запускать после sql/add_games.sql.

INSERT INTO games (slug, title, topic, emoji, description, url, is_published)
VALUES (
  'greece',
  'Греческая гонка',
  'Фразеологизмы-вводные',
  '🐎',
  'Древняя Греция, агора, 17 заданий. Фразеологизмы-вводные, связки и обороты, оформляющие речь. Кликай по словам, чтобы выделить фразеологизм; балл засчитывается за любой полностью найденный.',
  '/games/greece/',
  FALSE
)
ON CONFLICT (slug) DO UPDATE SET
  title       = EXCLUDED.title,
  topic       = EXCLUDED.topic,
  emoji       = EXCLUDED.emoji,
  description = EXCLUDED.description;

SELECT 'greece synced' AS status,
  (SELECT COUNT(*) FROM games) AS games_count;
