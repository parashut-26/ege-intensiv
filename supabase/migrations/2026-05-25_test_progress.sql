-- =============================================================================
-- 2026-05-25 — test_progress: синхронизация прогресса тренажёра между устройствами
-- =============================================================================
-- Прецедент: «У многих слетали ответы — кажется, из-за того что дети
-- переходили на другое устройство или заходили спустя больше количества
-- времени» (Ольга, 25.05). Текущее хранение в localStorage:
--   - Только на одном устройстве (другой телефон/комп — пусто)
--   - TTL 6 часов (зашли через 7+ часов — стёрто)
--
-- Решение: одна запись на user_id (у ученика одновременно один активный
-- тренажёр — STATE.testOpen). Payload — тот же JSON что и в localStorage.
-- Клиент при каждом изменении делает UPSERT (с debounce 1.5с), при загрузке
-- тренажёра сравнивает _t из БД и из localStorage, берёт более свежий.
--
-- RLS: каждый ученик видит/пишет только свой прогресс. Учитель не лезет.
-- =============================================================================

CREATE TABLE IF NOT EXISTS test_progress (
  user_id uuid PRIMARY KEY REFERENCES profiles(id) ON DELETE CASCADE,
  payload jsonb NOT NULL,
  updated_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE test_progress ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "tp_select_own" ON test_progress;
DROP POLICY IF EXISTS "tp_insert_own" ON test_progress;
DROP POLICY IF EXISTS "tp_update_own" ON test_progress;
DROP POLICY IF EXISTS "tp_delete_own" ON test_progress;

CREATE POLICY "tp_select_own" ON test_progress
  FOR SELECT USING (user_id = auth.uid());
CREATE POLICY "tp_insert_own" ON test_progress
  FOR INSERT WITH CHECK (user_id = auth.uid());
CREATE POLICY "tp_update_own" ON test_progress
  FOR UPDATE USING (user_id = auth.uid())
              WITH CHECK (user_id = auth.uid());
CREATE POLICY "tp_delete_own" ON test_progress
  FOR DELETE USING (user_id = auth.uid());

COMMENT ON TABLE test_progress IS
  'Промежуточный прогресс тренажёра ученика: ответы, режим, доска вопросов. Используется для синхронизации между устройствами. Удаляется когда ученик завершает тренажёр.';
