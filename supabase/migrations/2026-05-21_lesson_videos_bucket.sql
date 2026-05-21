-- 2026-05-21: бакет для видео-уроков в постах «Разогрев» и «Дни интенсива»
--
-- Запускать в Supabase Dashboard → SQL Editor → New query → вставить → Run.
-- Идемпотентно: если запустить дважды, ошибок не будет.

------------------------------------------------------------------------------
-- 1. Сам бакет
------------------------------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'lesson-videos',
  'lesson-videos',
  true,                                     -- публичное чтение через CDN
  104857600,                                -- 100 МБ на файл (Supabase free: 50, paid: до 5 ГБ)
  array['video/mp4','video/quicktime','video/webm','video/x-m4v']
)
on conflict (id) do update
  set public             = excluded.public,
      file_size_limit    = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;

------------------------------------------------------------------------------
-- 2. Политики storage.objects
------------------------------------------------------------------------------
-- 2.1 Чтение — публично (через CDN, без токена).
--     Бакет уже public, но политику на SELECT всё равно нужно создать,
--     иначе анонимные клиенты не пройдут RLS.
drop policy if exists "lesson_videos_public_read" on storage.objects;
create policy "lesson_videos_public_read"
  on storage.objects for select
  to anon, authenticated
  using (bucket_id = 'lesson-videos');

-- 2.2 Запись — только teacher или curator.
--     Используем функцию is_teacher() / is_curator(), которые уже есть в проекте
--     (см. schema.sql; обе SECURITY DEFINER, проверяют роль из profiles).
drop policy if exists "lesson_videos_teacher_insert" on storage.objects;
create policy "lesson_videos_teacher_insert"
  on storage.objects for insert
  to authenticated
  with check (
    bucket_id = 'lesson-videos'
    and (is_teacher() or is_curator())
  );

drop policy if exists "lesson_videos_teacher_update" on storage.objects;
create policy "lesson_videos_teacher_update"
  on storage.objects for update
  to authenticated
  using (
    bucket_id = 'lesson-videos'
    and (is_teacher() or is_curator())
  );

drop policy if exists "lesson_videos_teacher_delete" on storage.objects;
create policy "lesson_videos_teacher_delete"
  on storage.objects for delete
  to authenticated
  using (
    bucket_id = 'lesson-videos'
    and (is_teacher() or is_curator())
  );

------------------------------------------------------------------------------
-- 3. Проверка (для удобства, можно удалить после прогона)
------------------------------------------------------------------------------
-- select id, public, file_size_limit, allowed_mime_types from storage.buckets where id='lesson-videos';
-- select policyname from pg_policies where tablename='objects' and policyname like 'lesson_videos%';
