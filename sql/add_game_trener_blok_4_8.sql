-- Тренажёр «Блок 4-8» — задания 4-8 ЕГЭ:
--   4 — орфоэпия (ударения)
--   5 — паронимы
--   6 — лексические нормы
--   7 — морфологические нормы (формы слов)
--   8 — синтаксические нормы (грамматика)
-- 26 заданий: теория + практика, embed-режим уже реализован.
-- Запускать после sql/add_games.sql.

INSERT INTO games (slug, title, topic, emoji, description, url, is_published)
VALUES (
  'trener-blok-4-8',
  'Тренажёр. Блок 4-8',
  'Тренажёры ЕГЭ',
  '🎯',
  'Задания 4-8 ЕГЭ: орфоэпия, паронимы, лексические, морфологические и синтаксические нормы. 26 заданий с теорией и практикой.',
  '/games/trener-blok-4-8/',
  FALSE
)
ON CONFLICT (slug) DO UPDATE SET
  title       = EXCLUDED.title,
  topic       = EXCLUDED.topic,
  emoji       = EXCLUDED.emoji,
  description = EXCLUDED.description,
  url         = EXCLUDED.url;

SELECT 'trener-blok-4-8 synced' AS status,
  (SELECT COUNT(*) FROM games) AS games_count;
