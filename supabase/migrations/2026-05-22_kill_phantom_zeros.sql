-- 2026-05-22: Уничтожение «нулёвок-фантомов» в test_variant_answers
-- + защита на будущее.
--
-- Проблема: как только ученик что-либо тапал в любом задании, фоновой polling
-- проходился по всем 27 заданиям и INSERT-ил пустые строки. Поля points и
-- max_points в БД имеют DEFAULT, поэтому строки получали points=0, max_points=1,
-- даже без реального ответа ученика. Учитель видел красную «0» в каждой ячейке.
--
-- Это лечение в три шага:
--   1) удалить ВСЕ строки, где явно никакого ответа не было — user_answer null,
--      points=0, max_points=1, и нет ни scratch/drawing/structured (то есть
--      ученик НЕ касался задания)
--   2) убрать DEFAULT с points и max_points, чтобы новые INSERT'ы без явных
--      значений писали NULL, а не 0/1
--   3) (профилактика) старые попытки, где ВСЕ 27 заданий — фантомы, всё ещё
--      сохраняются как «попытка», но в сводной не будет красных нулей
--
-- Безопасно: проверка по комбинации полей жёстче «нулёвки-фантома», реальные
-- ответы НЕ трогает.
-- Запуск: Supabase Dashboard → SQL Editor → New query → Run.

-- =====================================================================
-- 1) Удаляем все «фантомы». Точные условия фантома:
--    a) user_answer IS NULL  (ученик не вводил ответ)
--    b) points = 0           (не получил баллов — но это могло и быть, если
--                              реально неправильно ответил)
--    c) НО при этом
--       scratch IS NULL AND student_drawing IS NULL AND structured_state IS NULL
--       AND student_note IS NULL AND teacher_comment IS NULL
--       AND teacher_scratch IS NULL AND teacher_drawing IS NULL
--       → значит реально никаких признаков взаимодействия — строка пустая
-- =====================================================================
with deleted as (
  delete from public.test_variant_answers a
  where a.user_answer is null
    and (a.points is null or a.points = 0)
    and a.scratch is null
    and a.student_drawing is null
    and a.structured_state is null
    and a.student_note is null
    and a.teacher_comment is null
    and a.teacher_scratch is null
    and a.teacher_drawing is null
  returning attempt_id, question_num
)
select count(*) as deleted_phantoms,
       count(distinct attempt_id) as affected_attempts
from deleted;

-- =====================================================================
-- 2) Снимаем DEFAULT с points и max_points, чтобы будущие INSERT'ы без
--    явного значения писали NULL. Это самая важная часть — иначе фантомы
--    появятся снова при следующем сеансе ученика.
-- =====================================================================
alter table public.test_variant_answers
  alter column points drop default;

alter table public.test_variant_answers
  alter column max_points drop default;

-- =====================================================================
-- 3) Проверка: что осталось по варианту «Белые одежды» для Вероники.
--    Должно вернуть строк меньше, чем было (только реальные ответы).
-- =====================================================================
select
  va.id            as attempt_id,
  va.started_at,
  va.finished_at,
  count(a.id) filter (where a.user_answer is not null)             as answered,
  count(a.id) filter (where a.scratch is not null
                          or a.student_drawing is not null
                          or a.structured_state is not null)       as marked,
  count(a.id)                                                       as total_rows
from public.test_variant_attempts va
join public.test_variants v on v.id = va.variant_id
left join public.profiles p on p.id = va.profile_id
left join public.test_variant_answers a on a.attempt_id = va.id
where v.title ilike '%белые одежды%'
  and (p.full_name ilike '%вероник%'
       or va.otp_full_name ilike '%вероник%'
       or va.otp_user ilike '%вероник%')
group by va.id, va.started_at, va.finished_at
order by va.started_at desc;
