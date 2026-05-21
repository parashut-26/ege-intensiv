-- 2026-05-21: Подготовка БД к solver v2.
-- Добавляем колонки для структурированных UI каждого типа заданий
-- и для «черновика» ученика с разметкой текста (подчёркивания, цвета).
--
-- Запускать в Supabase Dashboard → SQL Editor → New query → Run.
-- Идемпотентно: повторный запуск ничего не сломает.

-- =====================================================================
-- 1. test_variant_questions:
--    structured  — JSONB с разобранной структурой задания (gap-ы, опции,
--                  предложения с цифрами и т.д.). null — рендерим по-старому
--                  (plain input). Парсер при импорте заполняет автоматически
--                  для известных типов 9-22.
--
--    scratch_default — учительский черновик-разметка как «стартовое
--                  состояние» (необязательно). Если ученик ничего не
--                  пишет — показывается этот текст.
-- =====================================================================
alter table public.test_variant_questions
  add column if not exists structured jsonb,
  add column if not exists scratch_default text;

-- =====================================================================
-- 2. test_variant_answers:
--    scratch     — TEXT с HTML-разметкой того, как ученик отметил текст
--                  задания (выделения, цвета, подчёркивания). Автосейв
--                  при правке. Учитель потом видит это в разборе.
-- =====================================================================
alter table public.test_variant_answers
  add column if not exists scratch text;

-- =====================================================================
-- Проверка:
-- select column_name, data_type from information_schema.columns
-- where table_schema='public' and table_name in ('test_variant_questions','test_variant_answers')
-- order by table_name, ordinal_position;
