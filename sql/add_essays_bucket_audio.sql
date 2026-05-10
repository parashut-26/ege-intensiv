-- ============================================================
-- Миграция: разрешить голосовые комментарии в бакете essays
--
-- Что делает:
--   1. Проверяет/создаёт бакет essays если его нет.
--   2. Снимает ограничения allowed_mime_types — теперь принимаются
--      любые типы (image/*, audio/webm, audio/mp4, application/pdf и т.д.).
--   3. Поднимает file_size_limit до 50 МБ.
--   4. Делает бакет публичным на чтение (нужно для отображения
--      фото/аудио ученикам).
--   5. Перекраивает RLS-политики storage.objects под essays:
--      — любой авторизованный может INSERT (учитель/куратор/ученик);
--      — все могут читать (включая анонимных — пригодится для
--        предпросмотра, если ученик откроет ссылку из почты);
--      — автор файла может удалять свои файлы.
--
-- Запустить однократно в Supabase SQL Editor.
-- ============================================================

-- 1. Бакет
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES ('essays', 'essays', TRUE, 52428800, NULL)
ON CONFLICT (id) DO UPDATE
  SET public = TRUE,
      file_size_limit = 52428800,
      allowed_mime_types = NULL;   -- NULL = разрешены любые типы

-- 2. RLS-политики storage.objects для essays
DROP POLICY IF EXISTS "essays_insert"  ON storage.objects;
DROP POLICY IF EXISTS "essays_read"    ON storage.objects;
DROP POLICY IF EXISTS "essays_delete"  ON storage.objects;
DROP POLICY IF EXISTS "essays_update"  ON storage.objects;

CREATE POLICY "essays_insert" ON storage.objects FOR INSERT TO authenticated
  WITH CHECK (bucket_id = 'essays');

CREATE POLICY "essays_read" ON storage.objects FOR SELECT TO public
  USING (bucket_id = 'essays');

CREATE POLICY "essays_update" ON storage.objects FOR UPDATE TO authenticated
  USING (bucket_id = 'essays' AND auth.uid()::text = (storage.foldername(name))[1])
  WITH CHECK (bucket_id = 'essays');

CREATE POLICY "essays_delete" ON storage.objects FOR DELETE TO authenticated
  USING (bucket_id = 'essays' AND (
    auth.uid()::text = (storage.foldername(name))[1]
    OR EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role IN ('teacher','curator'))
  ));

-- 3. Проверка
SELECT id, name, public, file_size_limit, allowed_mime_types FROM storage.buckets WHERE id = 'essays';
