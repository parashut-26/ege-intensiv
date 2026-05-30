-- Рабочий лист «НАУТРО и НА УТРО» — слитное и раздельное написание.
--   Тема: различение наречия НАУТРО (когда? = утром) и предлога с
--   существительным НА УТРО (на что? на какое время?; есть определение/зависимое слово).
-- 7 упражнений (выбор написания, перетаскивание определений, поиск ошибок,
--   мини-диктант, открытые задания) — 27 проверяемых пунктов с разбором.
-- 1-й уровень каталога (grade) — раздел 'Орфография' (рядом с «11 класс», «9 класс»…).
-- 2-й уровень (topic) — тема 'Слитное и раздельное написание'.
-- Embed-режим уже реализован. Запускать после sql/add_games.sql и sql/add_game_grade.sql.

INSERT INTO games (slug, title, grade, topic, emoji, description, url, is_published)
VALUES (
  'rabochiy-list-nautro',
  'Рабочий лист. НАУТРО и НА УТРО',
  'Орфография',
  'Слитное и раздельное написание',
  '🌼',
  'Слитное и раздельное написание НАУТРО / НА УТРО: правило и два приёма проверки (вставка определения и замена словом «утром»). 7 упражнений, 27 проверяемых заданий с мгновенным разбором.',
  '/games/rabochiy-list-nautro/',
  FALSE
)
ON CONFLICT (slug) DO UPDATE SET
  title       = EXCLUDED.title,
  grade       = EXCLUDED.grade,
  topic       = EXCLUDED.topic,
  emoji       = EXCLUDED.emoji,
  description = EXCLUDED.description,
  url         = EXCLUDED.url;

SELECT 'rabochiy-list-nautro synced' AS status,
  grade, topic
FROM games WHERE slug = 'rabochiy-list-nautro';
