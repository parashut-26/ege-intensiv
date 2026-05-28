-- «Скоро в отпуск!» — заключительный интерактивный урок 6 класса по русскому языку.
-- 9 упражнений по презентации Урок 66 (приставки, фонетика, фразеологизмы, шарады, кроссворд).
-- Запускать после sql/add_games.sql и sql/add_game_grade.sql.

INSERT INTO games (slug, title, grade, topic, emoji, description, url, is_published)
VALUES (
  'skoro-v-otpusk',
  'Скоро в отпуск!',
  '6 класс',
  'Заключительный урок',
  '🏖️',
  '9 летних упражнений по русскому: орфограммы, фонетика, словарные игры и фразеологизмы. Заключительный урок 6 класса. Без сохранения результатов — для повторения и для тех, кто пропустил занятие.',
  '/games/skoro-v-otpusk/',
  FALSE
)
ON CONFLICT (slug) DO UPDATE SET
  title       = EXCLUDED.title,
  grade       = EXCLUDED.grade,
  topic       = EXCLUDED.topic,
  emoji       = EXCLUDED.emoji,
  description = EXCLUDED.description,
  url         = EXCLUDED.url;

SELECT 'skoro-v-otpusk synced' AS status,
  grade, topic, slug
FROM games
WHERE slug = 'skoro-v-otpusk';
