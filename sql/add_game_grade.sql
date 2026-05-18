-- =========================================================
-- Двухуровневая группировка игр: класс (grade) → тема (topic)
-- 1-й уровень во вкладке «Игры» — класс/этап («11 класс», «10 класс», ОГЭ ...).
-- 2-й уровень внутри класса — тема ЕГЭ («Фразеологизмы», «Паронимы», ...).
-- =========================================================

-- Добавляем колонку grade
ALTER TABLE games ADD COLUMN IF NOT EXISTS grade TEXT DEFAULT '11 класс';

-- Все текущие 9 игр серии «гонок за фразеологизмами» — это ЕГЭ-материал, 11 класс
UPDATE games SET grade = '11 класс'
WHERE slug IN (
  'race-phraseo', 'winter-forest', 'paris-night', 'sakura',
  'underwater', 'savannah', 'greece', 'cosmos', 'egypt'
);

-- Индекс для быстрой группировки
CREATE INDEX IF NOT EXISTS games_grade_topic_idx ON games(grade, topic);

-- Проверка
SELECT 'games_grade_set' AS status,
  grade, topic, COUNT(*) as count
FROM games
GROUP BY grade, topic
ORDER BY grade, topic;
