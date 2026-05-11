-- =========================================================
-- АВАТАРЫ ПРОФИЛЕЙ
-- Колонка avatar_url + Storage bucket 'avatars' (публичный).
-- =========================================================

ALTER TABLE profiles ADD COLUMN IF NOT EXISTS avatar_url TEXT;

INSERT INTO storage.buckets (id, name, public)
VALUES ('avatars', 'avatars', TRUE)
ON CONFLICT (id) DO UPDATE SET public = TRUE;

-- Читают все
DROP POLICY IF EXISTS "avatars_read_all" ON storage.objects;
CREATE POLICY "avatars_read_all" ON storage.objects
  FOR SELECT USING (bucket_id = 'avatars');

-- Загружает любой авторизованный (имя файла начинается с его user_id)
DROP POLICY IF EXISTS "avatars_insert_auth" ON storage.objects;
CREATE POLICY "avatars_insert_auth" ON storage.objects
  FOR INSERT WITH CHECK (
    bucket_id = 'avatars' AND auth.uid() IS NOT NULL
  );

-- Удаляет/перезаписывает любой авторизованный (RLS на profiles уже
-- даёт менять только свой avatar_url, лишних аватаров не наплодится)
DROP POLICY IF EXISTS "avatars_update_auth" ON storage.objects;
CREATE POLICY "avatars_update_auth" ON storage.objects
  FOR UPDATE USING (
    bucket_id = 'avatars' AND auth.uid() IS NOT NULL
  );

DROP POLICY IF EXISTS "avatars_delete_auth" ON storage.objects;
CREATE POLICY "avatars_delete_auth" ON storage.objects
  FOR DELETE USING (
    bucket_id = 'avatars' AND auth.uid() IS NOT NULL
  );

-- Проверка
SELECT column_name FROM information_schema.columns
WHERE table_schema='public' AND table_name='profiles' AND column_name='avatar_url';
