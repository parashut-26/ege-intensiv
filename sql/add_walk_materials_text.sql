-- Добавляем колонку для текстовых сообщений в walk_materials
-- (мотивационные заметки, цитаты, краткие напоминания и т.п.)
ALTER TABLE walk_materials ADD COLUMN IF NOT EXISTS text_content TEXT;

-- Проверка
SELECT column_name, data_type FROM information_schema.columns
WHERE table_schema='public' AND table_name='walk_materials' AND column_name='text_content';
