-- 2026-05-21: Проставляем правильные max_points для всех заданий вариантов
-- по официальной шкале ФИПИ-2026:
--
--   • Задания 8 и 22  — 2 балла
--   • Задание 27       — 22 балла (К1-К10)
--   • Остальные 1-26   — 1 балл
--
-- Запускать в Supabase Dashboard → SQL Editor → New query → Run.
-- После запуска нужно нажать «🔄 Пересчитать баллы» в каждом варианте,
-- чтобы старые попытки получили правильные итоговые баллы.

update public.test_variant_questions
set max_points = case
  when num = 8  then 2
  when num = 22 then 2
  when num = 27 then 22
  else 1
end
where max_points is distinct from (
  case
    when num = 8  then 2
    when num = 22 then 2
    when num = 27 then 22
    else 1
  end
);

-- Проверка (опционально):
-- select num, max_points, count(*) as cnt
-- from public.test_variant_questions
-- group by num, max_points
-- order by num, max_points;
