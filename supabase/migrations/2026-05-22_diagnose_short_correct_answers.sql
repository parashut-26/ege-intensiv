-- 2026-05-22: ДИАГНОСТИКА — смотрим эталоны во всех вариантах
--
-- ВАЖНО: для №15/16/17-20 одна цифра в ответе бывает валидной
-- (например, только одна позиция требует НН / одно предложение с одной
-- запятой). Поэтому этот скрипт ничего не «фиксит» — он выводит ВСЕ
-- correct_answer по этим заданиям рядом с куском формулировки, чтобы
-- ты глазами могла сверить, где реально обрезано.
--
-- Запускать в Supabase Dashboard → SQL Editor → New query → Run.
-- Ничего не меняет — только SELECT. Безопасно.

-- =====================================================================
-- 1) Задания с ПУСТЫМ эталоном — точно проблема, как ни крути.
-- =====================================================================
select
  v.id      as variant_id,
  v.title   as variant,
  q.num     as task_num,
  q.correct_answer,
  left(coalesce(q.question_text, ''), 120) as q_preview
from public.test_variant_questions q
join public.test_variants v on v.id = q.variant_id
where coalesce(trim(q.correct_answer), '') = ''
order by v.title, q.num;

-- =====================================================================
-- 2) Все №15/16/17-20 с эталоном — твоя ручная проверка.
--    Смотри на пары correct_answer ↔ q_preview: если в формулировке
--    видно 4-6 позиций (1)(2)(3)…, а correct_answer = «1» — обрезано.
-- =====================================================================
select
  v.id      as variant_id,
  v.title   as variant,
  q.num     as task_num,
  q.correct_answer,
  length(regexp_replace(coalesce(q.correct_answer, ''), '[^0-9]', '', 'g')) as digits_count,
  left(coalesce(q.question_text, ''), 200) as q_preview
from public.test_variant_questions q
join public.test_variants v on v.id = q.variant_id
where q.num in (15, 16, 17, 18, 19, 20)
order by v.title, q.num;

-- =====================================================================
-- 3) Эталоны со слэшем «/» в №15/16 — там альтернативы по слэшу
--    обычно ошибка импорта (ответ должен быть одной строкой цифр).
--    Для 17-20 «/» может означать «несколько правильных порядков»
--    (например 23/32), это валидно — здесь только информативно.
-- =====================================================================
select
  v.id      as variant_id,
  v.title   as variant,
  q.num     as task_num,
  q.correct_answer
from public.test_variant_questions q
join public.test_variants v on v.id = q.variant_id
where q.num in (15, 16, 17, 18, 19, 20)
  and q.correct_answer like '%/%'
order by v.title, q.num;
