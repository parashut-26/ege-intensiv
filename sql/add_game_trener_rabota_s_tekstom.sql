-- Тренажёр «Работа с текстом» — задания 1-3 и 22-26 ЕГЭ:
--   1  — стилистический анализ / средства связи
--   2  — средства связи (часть речи + функция связи)
--   3  — лексический анализ / стили речи
--   22 — соответствие содержанию текста
--   23 — типы речи
--   24 — лексическое значение / антонимы / синонимы
--   25 — средства связи между предложениями
--   26 — средства художественной выразительности
-- 25 заданий: теория + практика, embed-режим уже реализован.
-- Запускать после sql/add_games.sql.

INSERT INTO games (slug, title, topic, emoji, description, url, is_published)
VALUES (
  'trener-rabota-s-tekstom',
  'Тренажёр. Работа с текстом',
  'Тренажёры ЕГЭ',
  '📖',
  'Задания 1-3 и 22-26 ЕГЭ: стилистика, средства связи, типы речи, лексический анализ, средства выразительности. 25 заданий с теорией и практикой.',
  '/games/trener-rabota-s-tekstom/',
  FALSE
)
ON CONFLICT (slug) DO UPDATE SET
  title       = EXCLUDED.title,
  topic       = EXCLUDED.topic,
  emoji       = EXCLUDED.emoji,
  description = EXCLUDED.description,
  url         = EXCLUDED.url;

SELECT 'trener-rabota-s-tekstom synced' AS status,
  (SELECT COUNT(*) FROM games) AS games_count;
