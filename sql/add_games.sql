-- =========================================================
-- ИГРЫ (мини-тренажёры) — каталог + попытки учеников платформы
-- Гостевой режим (вход по внешней ссылке без логина) — НЕ сохраняем.
--
-- Архитектура:
--   - games          — каталог игр (карточки в кабинете учителя/ученика)
--   - game_attempts  — попытки ученика платформы (по profile_id)
--
-- Игра живёт как отдельный HTML в /games/<slug>/index.html.
-- Платформа открывает её в iframe с ?mode=embed; игра в этом
-- режиме шлёт результат через window.parent.postMessage(...).
-- =========================================================

-- 1. Каталог игр
CREATE TABLE IF NOT EXISTS games (
  id              SERIAL PRIMARY KEY,
  slug            TEXT NOT NULL UNIQUE,      -- 'race-phraseo' — папка под /games/
  title           TEXT NOT NULL,             -- 'Гонка за фразеологизмами'
  topic           TEXT,                      -- 'Фразеологизмы' / 'Паронимы' / 'Ударения' …
  emoji           TEXT DEFAULT '🎮',
  description     TEXT,                      -- короткое описание для карточки
  url             TEXT,                      -- относительный путь, по умолчанию '/games/<slug>/'
  is_published    BOOLEAN NOT NULL DEFAULT FALSE,  -- «открыта всем ученикам»
  day_id          INTEGER REFERENCES intensive_days(id) ON DELETE SET NULL, -- опционально привязка к дню
  created_by      UUID REFERENCES profiles(id),
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS games_is_published_idx ON games(is_published);
CREATE INDEX IF NOT EXISTS games_day_id_idx ON games(day_id);
CREATE INDEX IF NOT EXISTS games_topic_idx ON games(topic);

-- 2. Попытка ученика по игре
CREATE TABLE IF NOT EXISTS game_attempts (
  id              SERIAL PRIMARY KEY,
  game_id         INTEGER NOT NULL REFERENCES games(id) ON DELETE CASCADE,
  student_id      UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  score           INTEGER NOT NULL DEFAULT 0,        -- баллы (или верных ответов)
  max_score       INTEGER NOT NULL DEFAULT 0,        -- максимум
  percent         NUMERIC(5,2) GENERATED ALWAYS AS (
                    CASE WHEN max_score > 0
                         THEN ROUND((score::NUMERIC / max_score) * 100, 2)
                         ELSE NULL END
                  ) STORED,
  time_seconds    INTEGER,                            -- сколько секунд проходил
  payload         JSONB,                              -- любые доп.данные (ошибки, ход игры)
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS game_attempts_game_idx ON game_attempts(game_id);
CREATE INDEX IF NOT EXISTS game_attempts_student_idx ON game_attempts(student_id);
CREATE INDEX IF NOT EXISTS game_attempts_created_idx ON game_attempts(created_at DESC);

-- ---------------------------------------------------------
-- RLS
-- ---------------------------------------------------------
ALTER TABLE games ENABLE ROW LEVEL SECURITY;
ALTER TABLE game_attempts ENABLE ROW LEVEL SECURITY;

-- games: все авторизованные читают, пишут учитель/куратор
DROP POLICY IF EXISTS "games_read" ON games;
CREATE POLICY "games_read" ON games FOR SELECT TO authenticated USING (TRUE);

DROP POLICY IF EXISTS "games_write" ON games;
CREATE POLICY "games_write" ON games FOR ALL TO authenticated
  USING (is_teacher() OR is_curator())
  WITH CHECK (is_teacher() OR is_curator());

-- game_attempts:
--   - учитель/куратор видит всё
--   - ученик видит только свои попытки
--   - ученик может вставлять только свои попытки (student_id = auth.uid())
DROP POLICY IF EXISTS "ga_read" ON game_attempts;
CREATE POLICY "ga_read" ON game_attempts FOR SELECT TO authenticated USING (
  is_teacher() OR is_curator() OR student_id = auth.uid()
);

DROP POLICY IF EXISTS "ga_insert_own" ON game_attempts;
CREATE POLICY "ga_insert_own" ON game_attempts FOR INSERT TO authenticated
  WITH CHECK (student_id = auth.uid() OR is_teacher() OR is_curator());

DROP POLICY IF EXISTS "ga_update_teacher" ON game_attempts;
CREATE POLICY "ga_update_teacher" ON game_attempts FOR UPDATE TO authenticated
  USING (is_teacher() OR is_curator())
  WITH CHECK (is_teacher() OR is_curator());

DROP POLICY IF EXISTS "ga_delete_teacher" ON game_attempts;
CREATE POLICY "ga_delete_teacher" ON game_attempts FOR DELETE TO authenticated
  USING (is_teacher() OR is_curator());

-- ---------------------------------------------------------
-- Стартовый каталог: одна игра для интенсива 2–4 июня
-- ---------------------------------------------------------
INSERT INTO games (slug, title, topic, emoji, description, url, is_published)
VALUES (
  'race-phraseo',
  'Гонка за фразеологизмами',
  'Фразеологизмы',
  '🏎️',
  '16 заданий на скорость: выделяй фразеологизмы кликом по словам, получай объяснение после каждого ответа.',
  '/games/race-phraseo/',
  FALSE
)
ON CONFLICT (slug) DO NOTHING;

-- ---------------------------------------------------------
-- Realtime
-- ---------------------------------------------------------
-- Если нужны live-обновления в аналитике учителя, в Supabase Dashboard:
-- Database → Replication → supabase_realtime → добавить таблицы games и game_attempts.
-- (Через SQL-API альтер publication на бесплатном тарифе не всегда доступен.)

-- Проверка
SELECT 'games ok' AS status,
  (SELECT COUNT(*) FROM games) AS games_count,
  (SELECT COUNT(*) FROM game_attempts) AS attempts_count;
