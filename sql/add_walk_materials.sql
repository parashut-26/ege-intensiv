-- =========================================================
-- МАТЕРИАЛЫ МОТИВАЦИОННЫХ ДНЕЙ (walk-дней)
-- Учитель/куратор может загружать аудио, картинки, ссылки.
-- Ученики могут слушать/смотреть/переходить.
-- =========================================================

CREATE TABLE IF NOT EXISTS walk_materials (
  id            SERIAL PRIMARY KEY,
  walk_key      TEXT NOT NULL,           -- 'walk1' / 'walk2' / 'walk3'
  kind          TEXT NOT NULL,           -- 'audio' / 'image' / 'link'
  title         TEXT,
  storage_path  TEXT,                    -- путь в bucket 'walks' (для audio/image)
  url           TEXT,                    -- внешняя ссылка (для kind='link')
  size_bytes    BIGINT,
  uploaded_by   UUID REFERENCES profiles(id) ON DELETE SET NULL,
  created_at    TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS walk_materials_walk_key_idx ON walk_materials(walk_key);

ALTER TABLE walk_materials ENABLE ROW LEVEL SECURITY;

-- Читать могут все авторизованные
DROP POLICY IF EXISTS walk_materials_select_all ON walk_materials;
CREATE POLICY walk_materials_select_all ON walk_materials
  FOR SELECT USING (auth.uid() IS NOT NULL);

-- Добавлять — только учитель/куратор
DROP POLICY IF EXISTS walk_materials_insert_teacher ON walk_materials;
CREATE POLICY walk_materials_insert_teacher ON walk_materials
  FOR INSERT WITH CHECK (
    EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role IN ('teacher','curator'))
  );

-- Удалять — только учитель/куратор
DROP POLICY IF EXISTS walk_materials_delete_teacher ON walk_materials;
CREATE POLICY walk_materials_delete_teacher ON walk_materials
  FOR DELETE USING (
    EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role IN ('teacher','curator'))
  );

-- =========================================================
-- Storage bucket 'walks' — публичный, чтобы ученик мог напрямую
-- читать аудио/картинку без подписи. Загружают только учителя.
-- =========================================================
INSERT INTO storage.buckets (id, name, public)
VALUES ('walks', 'walks', TRUE)
ON CONFLICT (id) DO UPDATE SET public = TRUE;

-- Storage-политики
DROP POLICY IF EXISTS "walks_read_all" ON storage.objects;
CREATE POLICY "walks_read_all" ON storage.objects
  FOR SELECT USING (bucket_id = 'walks');

DROP POLICY IF EXISTS "walks_insert_teacher" ON storage.objects;
CREATE POLICY "walks_insert_teacher" ON storage.objects
  FOR INSERT WITH CHECK (
    bucket_id = 'walks' AND
    EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role IN ('teacher','curator'))
  );

DROP POLICY IF EXISTS "walks_delete_teacher" ON storage.objects;
CREATE POLICY "walks_delete_teacher" ON storage.objects
  FOR DELETE USING (
    bucket_id = 'walks' AND
    EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role IN ('teacher','curator'))
  );

-- Проверка
SELECT 'walk_materials' AS table_name, COUNT(*) AS rows FROM walk_materials;
