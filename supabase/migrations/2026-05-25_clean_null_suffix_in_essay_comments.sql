-- =============================================================================
-- 2026-05-25 — Чистка артефакта "null" в конце текстов essay_comments.comment
-- =============================================================================
-- Прецедент: Ольга увидела в попапе у ученика комментарий вида
--   «Непонятно, к чему последнее предложение.
--    null»
-- Это след старого пути сохранения AI-замечаний (callCheckEssay → marks):
-- если AI возвращал m.correction/m.title/m.comment как строку "null" вместо
-- JSON null, проверка `if(m.correction)` пропускала её truthy, и в итоге к
-- комментарию приклеивался хвост вида '\n\nПравильно: null' или просто '\nnull'.
--
-- Клиентская защита уже добавлена (см. index.html — safeComment + явная
-- фильтрация 'null' в callCheckEssay-marks). Эта миграция — одноразовая
-- зачистка legacy-данных в БД, чтобы и в API-ответе, и в любых будущих
-- клиентах не было артефакта.
--
-- Идемпотентность: regexp_replace + фильтр в WHERE — повторный запуск
-- не находит чего фиксить и не делает обновлений.
-- =============================================================================

BEGIN;

-- Считаем сколько строк пострадало (для отчёта в Output).
DO $$
DECLARE
  affected int;
BEGIN
  SELECT count(*) INTO affected
  FROM essay_comments
  WHERE comment ~* E'\\s*\\n+\\s*(null|undefined)\\s*$';
  RAISE NOTICE 'essay_comments с хвостом null/undefined: %', affected;
END $$;

-- Сама зачистка. Снимаем висячий «\nnull» / «\nundefined» (с возможными
-- пробелами/табами вокруг). Хвост может встретиться в двух исторических
-- сценариях:
--   • от AI-marks: '...\n\nПравильно: null' → тут replace НЕ срезает, потому что
--     «Правильно:» это нормальный префикс. Срезает только если null/undefined
--     стоит самостоятельно на последней строке без «Правильно: ».
--   • прямая конкатенация (старый код): 'текст\nnull' → срезает.
UPDATE essay_comments
SET comment = regexp_replace(comment, E'\\s*\\n+\\s*(null|undefined)\\s*$', '', 'i')
WHERE comment ~* E'\\s*\\n+\\s*(null|undefined)\\s*$';

-- Отдельно: записи где comment === literal 'null' / 'undefined' целиком —
-- заменяем на NULL (safeComment на клиенте всё равно вернёт пустую строку,
-- но в БД чище NULL чем строка 'null').
UPDATE essay_comments
SET comment = NULL
WHERE comment IN ('null', 'undefined', 'NULL');

COMMIT;
