-- Добавляем вторую игру в каталог: «Тропа фразеологизмов» (Зимний лес).
-- Запускать после sql/add_games.sql (когда таблица games уже создана).

INSERT INTO games (slug, title, topic, emoji, description, url, is_published)
VALUES (
  'winter-forest',
  'Тропа фразеологизмов',
  'Фразеологизмы',
  '❄️',
  'Зимний лес, 16 заданий. Кликай по словам, чтобы выделить фразеологизм; после каждого ответа — объяснение значения.',
  '/games/winter-forest/',
  FALSE   -- по умолчанию скрыта; учитель откроет вручную из вкладки «Игры»
)
ON CONFLICT (slug) DO NOTHING;

SELECT 'winter-forest added' AS status,
  (SELECT COUNT(*) FROM games) AS games_count;
