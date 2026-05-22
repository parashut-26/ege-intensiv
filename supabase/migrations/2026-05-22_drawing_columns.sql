-- 2026-05-22: Добавляем колонки для рисунков карандашом
-- В каждой попытке варианта для каждого задания хранятся:
--   student_drawing — SVG-разметка ученика (как он отмечал текст карандашом)
--   teacher_drawing — SVG-разметка учителя (объяснения, обводки, стрелки)
--
-- Оба поля — строки с innerHTML SVG-слоя. Хранятся отдельно от текстового
-- scratch'а (там — HTML контеnteditable с пометками типа Ж/К/П/маркер).
--
-- Запускать в Supabase Dashboard → SQL Editor → New query → Run.
-- Идемпотентно.

alter table public.test_variant_answers
  add column if not exists student_drawing text,
  add column if not exists teacher_drawing text;

-- Проверка (опционально):
-- select column_name, data_type from information_schema.columns
-- where table_schema='public' and table_name='test_variant_answers'
-- order by ordinal_position;
