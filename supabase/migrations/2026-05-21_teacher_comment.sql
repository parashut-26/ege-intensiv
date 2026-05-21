-- 2026-05-21: добавляем колонку teacher_comment в test_variant_answers
-- Учитель пишет туда комментарий к ответу ученика на конкретное задание
-- пробника. Доступ:
--   • teacher / curator — INSERT/UPDATE
--   • student — SELECT (видит только свои попытки через RLS на attempts)
--
-- Запускать в Supabase Dashboard → SQL Editor → New query → вставить → Run.
-- Идемпотентно: повторный запуск ничего не сломает.

alter table public.test_variant_answers
  add column if not exists teacher_comment text;

-- Проверка (опционально, для удобства):
-- select column_name, data_type from information_schema.columns
--   where table_schema='public' and table_name='test_variant_answers'
--   order by ordinal_position;
