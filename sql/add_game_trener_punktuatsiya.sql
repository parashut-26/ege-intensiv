-- Тренажёр «Пунктуация» — задания 16-21 ЕГЭ:
--   16 — однородные члены и сложносочинённое предложение
--   17 — обособленные определения, обстоятельства, приложения
--   18 — вводные слова, обращения
--   19 — сложноподчинённое предложение
--   20 — сложные синтаксические конструкции
--   21 — пунктуационный анализ текста
-- 39 заданий: теория + практика, embed-режим уже реализован.
-- Запускать после sql/add_games.sql.

INSERT INTO games (slug, title, topic, emoji, description, url, is_published)
VALUES (
  'trener-punktuatsiya',
  'Тренажёр. Пунктуация',
  'Тренажёры ЕГЭ',
  '⸺',
  'Задания 16-21 ЕГЭ: однородные/ССП, обособление, вводные/обращения, СПП, сложные конструкции, пунктуационный анализ. 39 заданий с теорией и практикой.',
  '/games/trener-punktuatsiya/',
  FALSE
)
ON CONFLICT (slug) DO UPDATE SET
  title       = EXCLUDED.title,
  topic       = EXCLUDED.topic,
  emoji       = EXCLUDED.emoji,
  description = EXCLUDED.description,
  url         = EXCLUDED.url;

SELECT 'trener-punktuatsiya synced' AS status,
  (SELECT COUNT(*) FROM games) AS games_count;
