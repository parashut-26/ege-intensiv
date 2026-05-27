-- Игротека ОГЭ для 9 класса — две сборки мини-игр по открытому банку ФИПИ.
-- Часть 1: задания 3, 4, 5, 6 — синтаксис и орфография (5 мини-игр).
-- Часть 2: задания 7, 8, 9, 11, 12 — лексика, формы слов, грамматика (5 мини-игр).
-- Результаты до сентября 2026 пишутся в Google Sheets через Apps Script (см. data/grade9_meta/Инструкция_Лидерборд_v3.docx).
-- С сентября 2026 переводим на Supabase attempts, когда ученики 9 класса появятся в приложении.
-- Запускать после sql/add_games.sql и sql/add_game_grade.sql.

INSERT INTO games (slug, title, grade, topic, emoji, description, url, is_published)
VALUES (
  'igrioteka-ogje-1',
  'Игротека ОГЭ · Часть 1',
  '9 класс',
  'Игротека ОГЭ',
  '🐝',
  'Синтаксис и орфография: «Верные характеристики», «5 лишний», «Крестики-нолики», «Пунктуация-пазл», «Правило-пример». Задания 3-6 из открытого банка ФИПИ.',
  '/games/igrioteka-ogje-1/',
  FALSE
)
ON CONFLICT (slug) DO UPDATE SET
  title       = EXCLUDED.title,
  grade       = EXCLUDED.grade,
  topic       = EXCLUDED.topic,
  emoji       = EXCLUDED.emoji,
  description = EXCLUDED.description,
  url         = EXCLUDED.url;

INSERT INTO games (slug, title, grade, topic, emoji, description, url, is_published)
VALUES (
  'igrioteka-ogje-2',
  'Игротека ОГЭ · Часть 2',
  '9 класс',
  'Игротека ОГЭ',
  '🍯',
  'Лексика и формы слов: «Цветочное поле», «Лабиринт форм», «Сборка улья», «Аквариум», «Собери котят». Задания 7, 8, 9, 11, 12 из открытого банка ФИПИ.',
  '/games/igrioteka-ogje-2/',
  FALSE
)
ON CONFLICT (slug) DO UPDATE SET
  title       = EXCLUDED.title,
  grade       = EXCLUDED.grade,
  topic       = EXCLUDED.topic,
  emoji       = EXCLUDED.emoji,
  description = EXCLUDED.description,
  url         = EXCLUDED.url;

INSERT INTO games (slug, title, grade, topic, emoji, description, url, is_published)
VALUES (
  'igrioteka-ogje-3',
  'Игротека ОГЭ · Часть 3',
  '9 класс',
  'Игротека ОГЭ',
  '🕵️',
  'Синтаксический детектив: «Поиск основ», «Колонны характеристик», «Правило-сыщик». 3 мини-игры по новым текстам, задания 2-4 из открытого банка ФИПИ.',
  '/games/igrioteka-ogje-3/',
  FALSE
)
ON CONFLICT (slug) DO UPDATE SET
  title       = EXCLUDED.title,
  grade       = EXCLUDED.grade,
  topic       = EXCLUDED.topic,
  emoji       = EXCLUDED.emoji,
  description = EXCLUDED.description,
  url         = EXCLUDED.url;

SELECT 'ogje igrioteka synced' AS status,
  grade, topic, COUNT(*) AS games_count
FROM games
WHERE grade = '9 класс'
GROUP BY grade, topic;
