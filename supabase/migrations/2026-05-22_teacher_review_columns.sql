-- 2026-05-22: ВСЁ для расширенной проверки попыток учителем
--
-- Что добавляем:
--   structured_state jsonb — снимок выбора ученика по рядам/позициям/словам.
--     Хранит { type: 'checks9_12'|'gaps'|'checks16'|'words13_14'|'dropdowns21'|'matching22'|'inline',
--              data: <зависит от type> }
--     Заполняется решалкой при каждом тике (debounce 0.6 c). Нужен, чтобы
--     учитель в разборе видел не только итоговую цифру в user_answer, но и
--     какие именно буквы/запятые/чекбоксы ученик расставил по дороге.
--
--   teacher_scratch text — HTML-разметка учителя (маркер, цвет, подчёркивание)
--     поверх формулировки. Зеркало student_scratch, но для учителя.
--
--   (teacher_drawing text — уже существует в таблице, ничего не добавляем.)
--
-- Безопасно: только ADD COLUMN IF NOT EXISTS, никаких удалений и переименований.
-- Запускать: Supabase Dashboard → SQL Editor → New query → вставить → Run.

alter table public.test_variant_answers
  add column if not exists structured_state jsonb;

alter table public.test_variant_answers
  add column if not exists teacher_scratch text;

-- На случай если по какой-то причине teacher_drawing нет (старые БД):
alter table public.test_variant_answers
  add column if not exists teacher_drawing text;

-- Индекс не нужен — читаем только по (attempt_id, question_num),
-- а под это уже есть composite primary key / unique index.

-- Проверка: вернёт три строки с именами и типами новых колонок.
select column_name, data_type
from information_schema.columns
where table_schema = 'public'
  and table_name = 'test_variant_answers'
  and column_name in ('structured_state', 'teacher_scratch', 'teacher_drawing')
order by column_name;
