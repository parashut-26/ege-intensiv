-- =============================================================================
-- 2026-05-25 — В банке задания 22 заменить разметку __подчёркивание__ → **жирный**
-- =============================================================================
-- Прецедент: при загрузке 30 заданий 22 из PDF я использовала __б__уква____
-- для иллюстрации аллитерации/ассонанса, рассчитывая на расширение
-- renderInlineMd (поддержка __текст__ → <u>текст</u>). Расширение есть в
-- index.html, но Ольга справедливо попросила: «лучше уж просто жирным
-- выделять чем так подчёркивать» — на iPad PWA пока показывало
-- маркеры как plain text «___р___» (либо JS не подгружен, либо разметка
-- неудобна визуально). Жирный (**...**) поддерживался renderInlineMd
-- давно и точно работает.
--
-- Безопасность: внутри текстов заданий 22 двойное подчёркивание `__`
-- встречается ТОЛЬКО как мой markdown-маркер. В исходных строках PDF
-- настоящих `__` нет (проверила). Поэтому REPLACE безопасен.
--
-- Идемпотентность: повторный запуск — no-op, потому что после первого
-- запуска `__` в данных уже нет, REPLACE ничего не находит.
-- =============================================================================

UPDATE quiz_bank_overrides
SET questions = replace(questions::text, '__', '**')::jsonb,
    updated_at = NOW()
WHERE task_n = 22
  AND questions::text LIKE '%\\_\\_%' ESCAPE '\';

-- Самопроверка: сколько в банке заданий 22 содержат '**' и '__'.
DO $$
DECLARE
  total int;
  with_bold int;
  with_underscore int;
BEGIN
  SELECT jsonb_array_length(questions) INTO total
    FROM quiz_bank_overrides WHERE task_n = 22;
  SELECT count(*) INTO with_bold
    FROM jsonb_array_elements((SELECT questions FROM quiz_bank_overrides WHERE task_n = 22)) elem
    WHERE elem::text LIKE '%**%';
  SELECT count(*) INTO with_underscore
    FROM jsonb_array_elements((SELECT questions FROM quiz_bank_overrides WHERE task_n = 22)) elem
    WHERE elem::text LIKE '%\_\_%' ESCAPE '\';
  RAISE NOTICE 'Задание 22: всего %, с жирным **: %, с подчёркиванием __: % (должно быть 0)',
    total, with_bold, with_underscore;
END $$;
