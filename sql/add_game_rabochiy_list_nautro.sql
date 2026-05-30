-- Рабочий лист «НАУТРО и НА УТРО» — слитное и раздельное написание.
--   Тема: различение наречия НАУТРО (когда? = утром) и предлога с
--   существительным НА УТРО (на что? на какое время?; есть определение/зависимое слово).
-- 7 упражнений (выбор написания, перетаскивание определений, поиск ошибок,
--   мини-диктант, открытые задания) — 27 проверяемых пунктов с разбором.
-- Новая группа каталога: 'Орфография'. Embed-режим уже реализован.
-- Запускать после sql/add_games.sql.

INSERT INTO games (slug, title, topic, emoji, description, url, is_published)
VALUES (
  'rabochiy-list-nautro',
  'Рабочий лист. НАУТРО и НА УТРО',
  'Орфография',
  '🌼',
  'Слитное и раздельное написание НАУТРО / НА УТРО: правило и два приёма проверки (вставка определения и замена словом «утром»). 7 упражнений, 27 проверяемых заданий с мгновенным разбором.',
  '/games/rabochiy-list-nautro/',
  FALSE
)
ON CONFLICT (slug) DO UPDATE SET
  title       = EXCLUDED.title,
  topic       = EXCLUDED.topic,
  emoji       = EXCLUDED.emoji,
  description = EXCLUDED.description,
  url         = EXCLUDED.url;

SELECT 'rabochiy-list-nautro synced' AS status,
  (SELECT COUNT(*) FROM games) AS games_count;
