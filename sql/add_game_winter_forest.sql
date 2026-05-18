-- Добавляем вторую игру серии «гонок» в каталог.
-- Тема — Зимняя гонка (сани, снежная трасса). Серия одна (все игры
-- — гонки на фразеологизмы), отличаются темой и звуками.
-- Запускать после sql/add_games.sql.

INSERT INTO games (slug, title, topic, emoji, description, url, is_published)
VALUES (
  'winter-forest',
  'Зимняя гонка',
  'Фразеологизмы',
  '🛷',
  'Снежная трасса, 16 заданий. Кликай по словам, чтобы выделить фразеологизм; после каждого ответа — объяснение значения. Балл засчитывается, если найден хотя бы один фразеологизм в задании.',
  '/games/winter-forest/',
  FALSE
)
ON CONFLICT (slug) DO UPDATE SET
  title       = EXCLUDED.title,
  emoji       = EXCLUDED.emoji,
  description = EXCLUDED.description;

SELECT 'winter-forest synced' AS status,
  (SELECT COUNT(*) FROM games) AS games_count;
