-- 2026-05-23: Разрешить NULL в points и max_points
--
-- Контекст: после снятия DEFAULT и попытки INSERT-ить строки только со
-- structured_state/scratch/drawing (без points/max_points) — БД отбивает
-- 400 ошибкой «null value violates not-null constraint». То есть колонки
-- ещё имеют NOT NULL.
--
-- Семантика «не оценено» — это NULL, а не 0. Никто из кода уже не пишет
-- ничего такого, что сломалось бы от NULL: calcVariantTestSum трактует
-- Number(null) → NaN → || 0 → 0; variantCell проверяет ans.points != null
-- ans.max_points != null для определения «оценено или нет».
--
-- Запуск: Supabase Dashboard → SQL Editor → New query → Run.

alter table public.test_variant_answers
  alter column points drop not null;

alter table public.test_variant_answers
  alter column max_points drop not null;

-- Проверка: оба столбца должны вернуть is_nullable = YES
select column_name, is_nullable, column_default
from information_schema.columns
where table_schema = 'public'
  and table_name = 'test_variant_answers'
  and column_name in ('points', 'max_points');
