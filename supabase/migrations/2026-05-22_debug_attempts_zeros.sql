-- 2026-05-22: ДИАГНОСТИКА — откуда «0 0 0 …» в сводной по варианту «Белые одежды»
--
-- Только SELECT. Ничего не меняет.
-- Запустить в Supabase Dashboard → SQL Editor → New query → Run.

-- 1) Все попытки Вероники по варианту «Белые одежды».
--    Смотрим started_at/finished_at — какая live, какая закрыта.
select
  va.id            as attempt_id,
  v.title          as variant,
  p.full_name      as student,
  va.started_at,
  va.finished_at,
  va.parent_attempt_id,
  va.attempt_no,
  va.correct_count,
  va.total_score,
  va.percent_correct
from public.test_variant_attempts va
join public.test_variants v on v.id = va.variant_id
left join public.profiles p on p.id = va.profile_id
where v.title ilike '%белые одежды%'
  and (p.full_name ilike '%вероник%' or va.otp_full_name ilike '%вероник%' or va.otp_user ilike '%вероник%')
order by va.started_at desc;

-- 2) Что лежит в test_variant_answers по этим попыткам.
--    Если points=0 + max_points=1 + user_answer=NULL — это «нулёвки»
--    от твоего раннего «Завершить» (или авто-finalize). Их надо снести,
--    чтобы сводная показывала «—» / «·» вместо красных «0».
select
  va.id                          as attempt_id,
  va.started_at,
  va.finished_at,
  a.question_num                 as q,
  a.user_answer,
  a.points,
  a.max_points,
  case
    when a.user_answer is null and a.points = 0 and a.max_points > 0
      then '⚠ нулёвка-фантом (можно снести)'
    when a.user_answer is null and a.points is null and a.max_points is null
      then 'OK — пусто, цвет «·»'
    else '— реальный ответ'
  end                            as verdict
from public.test_variant_attempts va
join public.test_variant_answers a on a.attempt_id = va.id
join public.test_variants v on v.id = va.variant_id
left join public.profiles p on p.id = va.profile_id
where v.title ilike '%белые одежды%'
  and (p.full_name ilike '%вероник%' or va.otp_full_name ilike '%вероник%' or va.otp_user ilike '%вероник%')
order by va.started_at desc, a.question_num;
