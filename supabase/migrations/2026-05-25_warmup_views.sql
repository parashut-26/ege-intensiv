-- =============================================================================
-- 2026-05-25 — warmup_views: учёт активности учеников по дням и постам разогрева
-- =============================================================================
-- Прецедент: Ольга по играм видит кто играл (через game_attempts), а по постам
-- разогрева — нет. Зашла к ученице на 25 мая — оказалось что она даже
-- понедельник не открывала, но без таблицы это незаметно.
--
-- Таблица: одна запись на ПАРУ (user_id, day_id) или (user_id, block_id):
--   - day_id заполнен — открытие дня целиком (модалки/экрана дня)
--   - block_id заполнен — просмотр конкретного поста (свайп до него)
-- Уникальный индекс — UPSERT обновляет last_viewed_at + view_count++.
--
-- RLS:
--   - INSERT/UPDATE — только своя строка (user_id = auth.uid())
--   - SELECT — ученик видит свои, учитель/куратор — все
-- =============================================================================

CREATE TABLE IF NOT EXISTS warmup_views (
  id bigserial PRIMARY KEY,
  user_id uuid NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  day_id bigint REFERENCES warmup_days(id) ON DELETE CASCADE,
  block_id bigint REFERENCES warmup_blocks(id) ON DELETE CASCADE,
  first_viewed_at timestamptz NOT NULL DEFAULT now(),
  last_viewed_at timestamptz NOT NULL DEFAULT now(),
  view_count int NOT NULL DEFAULT 1,
  -- Должно быть заполнено ровно одно: либо день, либо пост
  CONSTRAINT warmup_views_day_xor_block CHECK (
    (day_id IS NOT NULL AND block_id IS NULL) OR
    (day_id IS NULL AND block_id IS NOT NULL)
  )
);

-- Партиальные уникальные индексы для UPSERT
CREATE UNIQUE INDEX IF NOT EXISTS warmup_views_day_uniq
  ON warmup_views (user_id, day_id)
  WHERE day_id IS NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS warmup_views_block_uniq
  ON warmup_views (user_id, block_id)
  WHERE block_id IS NOT NULL;

-- Индекс для запросов "кто видел этот день"
CREATE INDEX IF NOT EXISTS warmup_views_day_lookup
  ON warmup_views (day_id) WHERE day_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS warmup_views_block_lookup
  ON warmup_views (block_id) WHERE block_id IS NOT NULL;

-- RLS
ALTER TABLE warmup_views ENABLE ROW LEVEL SECURITY;

-- Удаляем старые политики если переapply миграции
DROP POLICY IF EXISTS "warmup_views_insert_own" ON warmup_views;
DROP POLICY IF EXISTS "warmup_views_update_own" ON warmup_views;
DROP POLICY IF EXISTS "warmup_views_select_own_or_teacher" ON warmup_views;

-- Ученик может INSERT'ить только свои просмотры
CREATE POLICY "warmup_views_insert_own" ON warmup_views
  FOR INSERT WITH CHECK (user_id = auth.uid());

-- И UPDATE только свои (для обновления last_viewed_at + view_count)
CREATE POLICY "warmup_views_update_own" ON warmup_views
  FOR UPDATE USING (user_id = auth.uid())
                WITH CHECK (user_id = auth.uid());

-- SELECT: свои — всегда; учитель/куратор — все
CREATE POLICY "warmup_views_select_own_or_teacher" ON warmup_views
  FOR SELECT USING (
    user_id = auth.uid()
    OR EXISTS (
      SELECT 1 FROM profiles
      WHERE id = auth.uid() AND role IN ('teacher', 'curator')
    )
  );

COMMENT ON TABLE warmup_views IS
  'Учёт активности ученика в Разогреве: какие дни и посты он открывал. Используется учителем для отслеживания «кто заходил, а кто пропал». Запись создаётся клиентом при первом открытии, last_viewed_at и view_count обновляются при повторных.';
