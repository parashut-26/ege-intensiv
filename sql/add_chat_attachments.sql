-- =========================================================
-- ГОЛОСОВЫЕ И ФОТО В ЧАТЕ
-- Добавляем колонки в chat_messages + bucket chat-media.
-- =========================================================

ALTER TABLE chat_messages
  ADD COLUMN IF NOT EXISTS voice_url  TEXT,
  ADD COLUMN IF NOT EXISTS image_url  TEXT;

INSERT INTO storage.buckets (id, name, public)
VALUES ('chat-media', 'chat-media', TRUE)
ON CONFLICT (id) DO UPDATE SET public = TRUE;

DROP POLICY IF EXISTS "chat_media_read_all" ON storage.objects;
CREATE POLICY "chat_media_read_all" ON storage.objects
  FOR SELECT USING (bucket_id = 'chat-media');

DROP POLICY IF EXISTS "chat_media_insert_auth" ON storage.objects;
CREATE POLICY "chat_media_insert_auth" ON storage.objects
  FOR INSERT WITH CHECK (
    bucket_id = 'chat-media' AND auth.uid() IS NOT NULL
  );

DROP POLICY IF EXISTS "chat_media_delete_auth" ON storage.objects;
CREATE POLICY "chat_media_delete_auth" ON storage.objects
  FOR DELETE USING (
    bucket_id = 'chat-media' AND auth.uid() IS NOT NULL
  );

-- Проверка
SELECT column_name FROM information_schema.columns
WHERE table_schema='public' AND table_name='chat_messages'
  AND column_name IN ('voice_url','image_url');
