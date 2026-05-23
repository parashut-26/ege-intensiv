-- Тренажёр «Орфография» — задания 9-15 ЕГЭ:
--   9  — корни (проверяемые, непроверяемые, чередующиеся)
--   10 — приставки
--   11 — суффиксы
--   12 — суффиксы причастий и личные окончания глаголов
--   13 — слитное/раздельное написание НЕ и НИ
--   14 — слитное/дефисное/раздельное написание
--   15 — Н и НН в разных частях речи
-- 64 задания: теория + практика, embed-режим уже реализован.
-- Запускать после sql/add_games.sql.

INSERT INTO games (slug, title, topic, emoji, description, url, is_published)
VALUES (
  'trener-orfografiya',
  'Тренажёр. Орфография',
  'Тренажёры ЕГЭ',
  '✍️',
  'Задания 9-15 ЕГЭ: корни, приставки, суффиксы, причастия, Н/НН, НЕ/НИ, слитно/раздельно/через дефис. 64 задания с теорией и практикой.',
  '/games/trener-orfografiya/',
  FALSE
)
ON CONFLICT (slug) DO UPDATE SET
  title       = EXCLUDED.title,
  topic       = EXCLUDED.topic,
  emoji       = EXCLUDED.emoji,
  description = EXCLUDED.description,
  url         = EXCLUDED.url;

SELECT 'trener-orfografiya synced' AS status,
  (SELECT COUNT(*) FROM games) AS games_count;
