-- ============================================================
-- ZebRus · Краш-тест 2026 — схема базы данных Supabase
-- Запустить целиком в Supabase → SQL Editor → New query → Run
-- ============================================================

-- =========================================================
-- 1) ПРОФИЛИ (расширение auth.users)
-- =========================================================
CREATE TYPE user_role AS ENUM ('student', 'curator', 'teacher', 'parent');
CREATE TYPE student_type AS ENUM ('свой', 'гость');
CREATE TYPE student_status AS ENUM ('pending', 'active', 'lagging');

CREATE TABLE profiles (
  id           UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  role         user_role NOT NULL DEFAULT 'student',
  full_name    TEXT NOT NULL,
  email        TEXT NOT NULL,
  avatar_color TEXT,
  -- только для учеников:
  s_type       student_type,
  s_status     student_status,
  bee          INTEGER DEFAULT 0,
  weak_topics  INTEGER[] DEFAULT '{}',  -- номера заданий ЕГЭ, где слабые места
  -- только для кураторов:
  curator_perms JSONB DEFAULT '{
    "addTasks": false,
    "addMaterials": false,
    "editTasks": false,
    "manageDays": false,
    "approveGuests": false
  }',
  onboarded_at TIMESTAMPTZ,
  created_at   TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX ON profiles (role);
CREATE INDEX ON profiles (s_status);

-- Связь родитель ↔ ученик (многие-ко-многим)
CREATE TABLE parent_student (
  parent_id  UUID REFERENCES profiles(id) ON DELETE CASCADE,
  student_id UUID REFERENCES profiles(id) ON DELETE CASCADE,
  PRIMARY KEY (parent_id, student_id)
);

-- =========================================================
-- 2) КУРС / ИНТЕНСИВЫ
-- =========================================================
CREATE TABLE intensives (
  id          SERIAL PRIMARY KEY,
  name        TEXT NOT NULL,                -- "Краш-тест 2026"
  start_date  DATE NOT NULL,
  end_date    DATE NOT NULL,
  exam_date   DATE,
  description TEXT,
  is_active   BOOLEAN DEFAULT TRUE,
  created_at  TIMESTAMPTZ DEFAULT NOW()
);

-- Запись ученика на интенсив (отдельно от профиля — чтобы один ученик мог быть на нескольких)
CREATE TABLE enrollments (
  id           SERIAL PRIMARY KEY,
  student_id   UUID REFERENCES profiles(id) ON DELETE CASCADE,
  intensive_id INTEGER REFERENCES intensives(id) ON DELETE CASCADE,
  enrolled_at  TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE (student_id, intensive_id)
);

-- =========================================================
-- 3) ДНИ ИНТЕНСИВА
-- =========================================================
CREATE TYPE day_kind AS ENUM ('work', 'walk', 'exam');

CREATE TABLE intensive_days (
  id           SERIAL PRIMARY KEY,
  intensive_id INTEGER REFERENCES intensives(id) ON DELETE CASCADE,
  ord          INTEGER NOT NULL,        -- порядок (1, 2, 3...)
  day_date     DATE NOT NULL,
  kind         day_kind DEFAULT 'work',
  title        TEXT,
  summary      TEXT,
  emoji        TEXT,
  ege_tasks    INTEGER[] DEFAULT '{}',  -- номера заданий ЕГЭ для этого дня (4,5,6,9-15)
  is_open      BOOLEAN DEFAULT FALSE
);

-- Активности дня (утро, вебинар, разбор, сочинение)
CREATE TYPE activity_kind AS ENUM ('morning', 'webinar', 'review', 'essay');

CREATE TABLE day_activities (
  id        SERIAL PRIMARY KEY,
  day_id    INTEGER REFERENCES intensive_days(id) ON DELETE CASCADE,
  kind      activity_kind NOT NULL,
  title     TEXT,
  est_min   INTEGER,        -- продолжительность в минутах
  start_at  TIME,           -- 13:00, 18:00 и т.д.
  max_bee   INTEGER DEFAULT 0
);

-- =========================================================
-- 4) ЗАДАНИЯ ЕГЭ (1–26) И ТЕОРИЯ
-- =========================================================
CREATE TABLE ege_tasks (
  n           INTEGER PRIMARY KEY,    -- номер задания 1–26
  topic       TEXT NOT NULL,
  theory_md   TEXT,                   -- markdown-текст теории
  default_day INTEGER                 -- по умолчанию какой день (1, 2, 3)
);

-- =========================================================
-- 5) БАНК ВОПРОСОВ ТРЕНАЖЁРА
-- =========================================================
CREATE TYPE question_type AS ENUM ('single', 'multi', 'text', 'pair', 'fill');

CREATE TABLE quiz_questions (
  id          SERIAL PRIMARY KEY,
  ege_task_n  INTEGER REFERENCES ege_tasks(n),
  q_type      question_type NOT NULL,
  q_text      TEXT NOT NULL,                  -- текст вопроса
  context     TEXT,                           -- доп. текст-преамбула
  sentences   TEXT[],                         -- список предложений (для задания 5 и т.п.)
  word        TEXT,                           -- большое слово (для пар)
  options     TEXT[] DEFAULT '{}',            -- варианты для single/multi
  answer      JSONB NOT NULL,                 -- {"idx": 2} | {"idxs":[0,2]} | {"texts":["житейский"]}
  hint        TEXT,
  source      TEXT,                           -- "Вариант 1 · задание 5" / "Банк ФИПИ"
  created_by  UUID REFERENCES profiles(id),
  created_at  TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX ON quiz_questions (ege_task_n);

-- Пары паронимов для тренажёра «Напиши пару»
CREATE TABLE paronym_pairs (
  id     SERIAL PRIMARY KEY,
  word_a TEXT NOT NULL,
  word_b TEXT NOT NULL,
  hint   TEXT
);

-- =========================================================
-- 6) ПОПЫТКИ УЧЕНИКОВ
-- =========================================================
CREATE TABLE attempts (
  id           SERIAL PRIMARY KEY,
  student_id   UUID REFERENCES profiles(id) ON DELETE CASCADE,
  intensive_id INTEGER REFERENCES intensives(id),
  ege_task_n   INTEGER REFERENCES ege_tasks(n),
  is_random    BOOLEAN DEFAULT FALSE,         -- случайный набор пар?
  question_ids INTEGER[],                     -- какие вопросы были в подборке
  answers      JSONB,                         -- что ответил
  score        INTEGER NOT NULL,              -- сколько правильно
  max_score    INTEGER NOT NULL,
  bee_earned   INTEGER DEFAULT 0,
  created_at   TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX ON attempts (student_id, ege_task_n);
CREATE INDEX ON attempts (created_at DESC);

-- =========================================================
-- 7) СОЧИНЕНИЯ И ИХ ПРОВЕРКА
-- =========================================================
CREATE TYPE essay_status AS ENUM ('draft', 'submitted', 'in_progress', 'pre_checked', 'done');
CREATE TYPE essay_format AS ENUM ('typed', 'photo');

CREATE TABLE essays (
  id            SERIAL PRIMARY KEY,
  student_id    UUID REFERENCES profiles(id) ON DELETE CASCADE,
  intensive_id  INTEGER REFERENCES intensives(id),
  source_text   TEXT,                         -- текст исходника, к которому пишут
  problem       TEXT,                         -- проблема, заявленная учителем
  format        essay_format NOT NULL,
  body_text     TEXT,                         -- если typed
  photo_urls    TEXT[],                       -- ссылки на Supabase Storage если photo
  word_count    INTEGER,
  status        essay_status DEFAULT 'submitted',
  submitted_at  TIMESTAMPTZ DEFAULT NOW(),
  pre_checked_by UUID REFERENCES profiles(id),  -- куратор
  finalized_by   UUID REFERENCES profiles(id),  -- учитель
  finalized_at   TIMESTAMPTZ
);
CREATE INDEX ON essays (status);
CREATE INDEX ON essays (student_id);

-- Оценка по К1-К10 + общий комментарий
CREATE TABLE essay_reviews (
  essay_id    INTEGER PRIMARY KEY REFERENCES essays(id) ON DELETE CASCADE,
  k1  SMALLINT, k2  SMALLINT, k3  SMALLINT, k4  SMALLINT, k5  SMALLINT,
  k6  SMALLINT, k7  SMALLINT, k8  SMALLINT, k9  SMALLINT, k10 SMALLINT,
  k7_errors  SMALLINT, k8_errors SMALLINT,
  k9_errors  SMALLINT, k10_errors SMALLINT,
  total       SMALLINT,                       -- считаем триггером
  general_comment TEXT,
  voice_url   TEXT,                           -- голосовой общий комментарий
  is_pre_check BOOLEAN DEFAULT FALSE,         -- предварительно от куратора
  reviewer_id UUID REFERENCES profiles(id),
  reviewed_at TIMESTAMPTZ DEFAULT NOW()
);

-- Комментарии к фрагментам сочинения (текст или фото)
CREATE TYPE error_kind AS ENUM ('orf', 'pun', 'gram', 'rech', 'fact', 'log', 'eth', 'other');

CREATE TABLE essay_comments (
  id          SERIAL PRIMARY KEY,
  essay_id    INTEGER REFERENCES essays(id) ON DELETE CASCADE,
  author_id   UUID REFERENCES profiles(id),
  fragment    TEXT,                           -- выделенный кусок текста
  start_pos   INTEGER,                        -- позиция в тексте (для typed)
  end_pos     INTEGER,
  photo_anchor JSONB,                         -- {x, y, page} для photo
  kind        error_kind DEFAULT 'other',
  comment     TEXT NOT NULL,
  voice_url   TEXT,
  created_at  TIMESTAMPTZ DEFAULT NOW()
);

-- Образцы сочинений (учебные)
CREATE TABLE essay_samples (
  id          SERIAL PRIMARY KEY,
  author_name TEXT,                           -- "София Малинина" / "Ученик ФИПИ #2"
  title       TEXT NOT NULL,
  text        TEXT,
  photo_urls  TEXT[],
  score       SMALLINT,
  max_score   SMALLINT DEFAULT 22,
  level       TEXT,                           -- 'high'/'medium'/'low'
  short       TEXT,                           -- короткое описание
  k_breakdown JSONB,                          -- {"K1":1,"K2":3,...}
  comments    TEXT,                           -- разбор экспертов
  created_at  TIMESTAMPTZ DEFAULT NOW()
);

-- =========================================================
-- 8) МАТЕРИАЛЫ
-- =========================================================
CREATE TYPE material_tag AS ENUM ('теория', 'вариант', 'разбор', 'видео');

CREATE TABLE materials (
  id          SERIAL PRIMARY KEY,
  name        TEXT NOT NULL,
  storage_path TEXT NOT NULL,                 -- путь в Supabase Storage
  size_bytes  BIGINT,
  tag         material_tag DEFAULT 'теория',
  ege_task_n  INTEGER REFERENCES ege_tasks(n),
  day_id      INTEGER REFERENCES intensive_days(id),
  uploaded_by UUID REFERENCES profiles(id),
  created_at  TIMESTAMPTZ DEFAULT NOW()
);

-- =========================================================
-- 9) ЧАТ
-- =========================================================
CREATE TYPE chat_room_kind AS ENUM ('group', 'dm');

CREATE TABLE chat_rooms (
  id           SERIAL PRIMARY KEY,
  intensive_id INTEGER REFERENCES intensives(id),
  kind         chat_room_kind NOT NULL,
  -- для dm — пара участников
  participant_a UUID REFERENCES profiles(id),
  participant_b UUID REFERENCES profiles(id),
  created_at   TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE chat_messages (
  id         SERIAL PRIMARY KEY,
  room_id    INTEGER REFERENCES chat_rooms(id) ON DELETE CASCADE,
  author_id  UUID REFERENCES profiles(id),
  body       TEXT NOT NULL,
  marked_helped_by UUID REFERENCES profiles(id),  -- кто пометил «помогло»
  created_at TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX ON chat_messages (room_id, created_at DESC);

-- =========================================================
-- 10) ПОСЕЩАЕМОСТЬ
-- =========================================================
CREATE TYPE attendance_source AS ENUM ('self', 'teacher', 'auto');

CREATE TABLE attendance (
  id           SERIAL PRIMARY KEY,
  student_id   UUID REFERENCES profiles(id) ON DELETE CASCADE,
  activity_id  INTEGER REFERENCES day_activities(id) ON DELETE CASCADE,
  source       attendance_source NOT NULL,
  marked_at    TIMESTAMPTZ DEFAULT NOW(),
  marked_by    UUID REFERENCES profiles(id),    -- если teacher или curator
  UNIQUE (student_id, activity_id)
);

-- =========================================================
-- 11) ОПЛАТЫ
-- =========================================================
CREATE TYPE payment_status AS ENUM ('paid', 'partial', 'pending', 'refunded');

CREATE TABLE payments (
  id           SERIAL PRIMARY KEY,
  student_id   UUID REFERENCES profiles(id) ON DELETE CASCADE,
  intensive_id INTEGER REFERENCES intensives(id) ON DELETE CASCADE,
  amount       NUMERIC(10,2) NOT NULL,
  status       payment_status DEFAULT 'pending',
  method       TEXT,                            -- "СБП", "карта", "наличные"
  paid_at      DATE,
  note         TEXT,
  created_at   TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE (student_id, intensive_id)
);

-- =========================================================
-- 12) ДОСТИЖЕНИЯ И ПЧЁЛКИ
-- =========================================================
CREATE TABLE achievement_defs (
  id          TEXT PRIMARY KEY,                  -- 'a1', 'b2'...
  category    TEXT,                              -- 'showup'/'self'/'social'/'final'
  emoji       TEXT,
  name        TEXT NOT NULL,
  description TEXT NOT NULL,
  bee_reward  INTEGER DEFAULT 5
);

CREATE TABLE user_achievements (
  student_id     UUID REFERENCES profiles(id) ON DELETE CASCADE,
  achievement_id TEXT REFERENCES achievement_defs(id) ON DELETE CASCADE,
  unlocked_at    TIMESTAMPTZ DEFAULT NOW(),
  PRIMARY KEY (student_id, achievement_id)
);

-- Лента активности — каждое начисление пчёлок
CREATE TABLE bee_transactions (
  id          SERIAL PRIMARY KEY,
  student_id  UUID REFERENCES profiles(id) ON DELETE CASCADE,
  amount      INTEGER NOT NULL,                  -- +5, +10
  reason      TEXT NOT NULL,                     -- 'за точность', 'за посещение' и т.п.
  source_kind TEXT,                              -- 'attempt'/'attendance'/'achievement'/'helped'
  source_id   INTEGER,                           -- ссылка на запись в соответствующей таблице
  emoji       TEXT,
  created_at  TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX ON bee_transactions (student_id, created_at DESC);

-- =========================================================
-- 13) АНАЛИТИКА — заполняется триггерами / приложением
-- =========================================================
-- Слабые темы группы — VIEW, считаем при обращении
CREATE OR REPLACE VIEW group_weak_topics AS
SELECT
  e.n          AS task_n,
  e.topic      AS topic,
  COALESCE(
    100 - (SUM(a.score)::FLOAT / NULLIF(SUM(a.max_score),0) * 100)::INTEGER,
    0
  )            AS error_pct,
  COUNT(a.*)   AS attempts_count
FROM ege_tasks e
LEFT JOIN attempts a ON a.ege_task_n = e.n
GROUP BY e.n, e.topic;

-- =========================================================
-- 14) RLS — БЕЗОПАСНОСТЬ ДОСТУПА
-- =========================================================
ALTER TABLE profiles            ENABLE ROW LEVEL SECURITY;
ALTER TABLE parent_student      ENABLE ROW LEVEL SECURITY;
ALTER TABLE intensives          ENABLE ROW LEVEL SECURITY;
ALTER TABLE enrollments         ENABLE ROW LEVEL SECURITY;
ALTER TABLE intensive_days      ENABLE ROW LEVEL SECURITY;
ALTER TABLE day_activities      ENABLE ROW LEVEL SECURITY;
ALTER TABLE ege_tasks           ENABLE ROW LEVEL SECURITY;
ALTER TABLE quiz_questions      ENABLE ROW LEVEL SECURITY;
ALTER TABLE paronym_pairs       ENABLE ROW LEVEL SECURITY;
ALTER TABLE attempts            ENABLE ROW LEVEL SECURITY;
ALTER TABLE essays              ENABLE ROW LEVEL SECURITY;
ALTER TABLE essay_reviews       ENABLE ROW LEVEL SECURITY;
ALTER TABLE essay_comments      ENABLE ROW LEVEL SECURITY;
ALTER TABLE essay_samples       ENABLE ROW LEVEL SECURITY;
ALTER TABLE materials           ENABLE ROW LEVEL SECURITY;
ALTER TABLE chat_rooms          ENABLE ROW LEVEL SECURITY;
ALTER TABLE chat_messages       ENABLE ROW LEVEL SECURITY;
ALTER TABLE attendance          ENABLE ROW LEVEL SECURITY;
ALTER TABLE payments            ENABLE ROW LEVEL SECURITY;
ALTER TABLE achievement_defs    ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_achievements   ENABLE ROW LEVEL SECURITY;
ALTER TABLE bee_transactions    ENABLE ROW LEVEL SECURITY;

-- Хелперы
CREATE OR REPLACE FUNCTION current_user_role() RETURNS user_role AS $$
  SELECT role FROM profiles WHERE id = auth.uid()
$$ LANGUAGE SQL STABLE SECURITY DEFINER;

CREATE OR REPLACE FUNCTION is_teacher() RETURNS BOOLEAN AS $$
  SELECT current_user_role() = 'teacher'
$$ LANGUAGE SQL STABLE SECURITY DEFINER;

CREATE OR REPLACE FUNCTION is_curator() RETURNS BOOLEAN AS $$
  SELECT current_user_role() = 'curator'
$$ LANGUAGE SQL STABLE SECURITY DEFINER;

-- ПРОФИЛИ:
-- Каждый видит свой и всех активных в группе. Учитель видит всех.
CREATE POLICY "profiles_self_select" ON profiles FOR SELECT TO authenticated
  USING (id = auth.uid() OR is_teacher() OR is_curator() OR s_status = 'active');

CREATE POLICY "profiles_self_update" ON profiles FOR UPDATE TO authenticated
  USING (id = auth.uid()) WITH CHECK (id = auth.uid());

CREATE POLICY "profiles_teacher_all" ON profiles FOR ALL TO authenticated
  USING (is_teacher()) WITH CHECK (is_teacher());

-- ИНТЕНСИВЫ / ДНИ / ЕГЭ-задания: чтение всем авторизованным; запись — учителю.
CREATE POLICY "intensives_read"   ON intensives        FOR SELECT TO authenticated USING (TRUE);
CREATE POLICY "intensives_write"  ON intensives        FOR ALL    TO authenticated USING (is_teacher()) WITH CHECK (is_teacher());
CREATE POLICY "days_read"         ON intensive_days    FOR SELECT TO authenticated USING (TRUE);
CREATE POLICY "days_write"        ON intensive_days    FOR ALL    TO authenticated USING (is_teacher()) WITH CHECK (is_teacher());
CREATE POLICY "activities_read"   ON day_activities    FOR SELECT TO authenticated USING (TRUE);
CREATE POLICY "activities_write"  ON day_activities    FOR ALL    TO authenticated USING (is_teacher()) WITH CHECK (is_teacher());
CREATE POLICY "ege_read"          ON ege_tasks         FOR SELECT TO authenticated USING (TRUE);
CREATE POLICY "ege_write"         ON ege_tasks         FOR ALL    TO authenticated USING (is_teacher()) WITH CHECK (is_teacher());

-- ВОПРОСЫ И ПАРЫ: читать всем; писать — учителю и куратору с правом addTasks.
CREATE POLICY "qq_read"           ON quiz_questions    FOR SELECT TO authenticated USING (TRUE);
CREATE POLICY "qq_write"          ON quiz_questions    FOR INSERT TO authenticated
  WITH CHECK (is_teacher() OR (is_curator() AND (SELECT (curator_perms->>'addTasks')::BOOLEAN FROM profiles WHERE id = auth.uid())));
CREATE POLICY "qq_update"         ON quiz_questions    FOR UPDATE TO authenticated USING (is_teacher()) WITH CHECK (is_teacher());
CREATE POLICY "qq_delete"         ON quiz_questions    FOR DELETE TO authenticated USING (is_teacher());

CREATE POLICY "pp_read"           ON paronym_pairs     FOR SELECT TO authenticated USING (TRUE);
CREATE POLICY "pp_write"          ON paronym_pairs     FOR ALL    TO authenticated USING (is_teacher()) WITH CHECK (is_teacher());

-- ПОПЫТКИ: ученик видит свои; учитель и куратор — все.
CREATE POLICY "att_self"          ON attempts          FOR SELECT TO authenticated USING (student_id = auth.uid() OR is_teacher() OR is_curator());
CREATE POLICY "att_insert_self"   ON attempts          FOR INSERT TO authenticated WITH CHECK (student_id = auth.uid());

-- СОЧИНЕНИЯ
CREATE POLICY "essay_read"   ON essays FOR SELECT TO authenticated USING (
  student_id = auth.uid() OR is_teacher() OR is_curator()
);
CREATE POLICY "essay_write"  ON essays FOR INSERT TO authenticated WITH CHECK (student_id = auth.uid());
CREATE POLICY "essay_update" ON essays FOR UPDATE TO authenticated USING (
  student_id = auth.uid() OR is_teacher() OR is_curator()
);

CREATE POLICY "review_read"  ON essay_reviews FOR SELECT TO authenticated USING (
  EXISTS(SELECT 1 FROM essays e WHERE e.id = essay_id AND (e.student_id = auth.uid() OR is_teacher() OR is_curator()))
);
CREATE POLICY "review_write" ON essay_reviews FOR ALL TO authenticated USING (is_teacher() OR is_curator()) WITH CHECK (is_teacher() OR is_curator());

CREATE POLICY "comment_read"  ON essay_comments FOR SELECT TO authenticated USING (
  EXISTS(SELECT 1 FROM essays e WHERE e.id = essay_id AND (e.student_id = auth.uid() OR is_teacher() OR is_curator()))
);
CREATE POLICY "comment_write" ON essay_comments FOR ALL TO authenticated USING (is_teacher() OR is_curator()) WITH CHECK (is_teacher() OR is_curator());

CREATE POLICY "samples_read"  ON essay_samples FOR SELECT TO authenticated USING (TRUE);
CREATE POLICY "samples_write" ON essay_samples FOR ALL TO authenticated USING (is_teacher()) WITH CHECK (is_teacher());

-- МАТЕРИАЛЫ: читать всем; писать — учитель и куратор с правом.
CREATE POLICY "mat_read"   ON materials FOR SELECT TO authenticated USING (TRUE);
CREATE POLICY "mat_insert" ON materials FOR INSERT TO authenticated
  WITH CHECK (is_teacher() OR (is_curator() AND (SELECT (curator_perms->>'addMaterials')::BOOLEAN FROM profiles WHERE id = auth.uid())));
CREATE POLICY "mat_modify" ON materials FOR UPDATE TO authenticated USING (is_teacher());
CREATE POLICY "mat_delete" ON materials FOR DELETE TO authenticated USING (is_teacher());

-- ЧАТ
CREATE POLICY "rooms_read" ON chat_rooms FOR SELECT TO authenticated USING (
  is_teacher() OR is_curator()
  OR participant_a = auth.uid() OR participant_b = auth.uid()
  OR (kind = 'group' AND EXISTS(SELECT 1 FROM enrollments WHERE student_id = auth.uid() AND intensive_id = chat_rooms.intensive_id))
);
CREATE POLICY "msgs_read" ON chat_messages FOR SELECT TO authenticated USING (
  EXISTS(SELECT 1 FROM chat_rooms r WHERE r.id = room_id AND (
    is_teacher() OR is_curator()
    OR r.participant_a = auth.uid() OR r.participant_b = auth.uid()
    OR (r.kind = 'group' AND EXISTS(SELECT 1 FROM enrollments WHERE student_id = auth.uid() AND intensive_id = r.intensive_id))
  ))
);
CREATE POLICY "msgs_insert" ON chat_messages FOR INSERT TO authenticated WITH CHECK (author_id = auth.uid());
CREATE POLICY "msgs_helped" ON chat_messages FOR UPDATE TO authenticated USING (is_teacher() OR is_curator());

-- ПОСЕЩАЕМОСТЬ
CREATE POLICY "att_read" ON attendance FOR SELECT TO authenticated USING (
  student_id = auth.uid() OR is_teacher() OR is_curator()
);
CREATE POLICY "att_self_mark" ON attendance FOR INSERT TO authenticated WITH CHECK (
  student_id = auth.uid() AND source = 'self'
);
CREATE POLICY "att_teacher_mark" ON attendance FOR ALL TO authenticated USING (is_teacher() OR is_curator()) WITH CHECK (is_teacher() OR is_curator());

-- ОПЛАТЫ — только учитель
CREATE POLICY "pay_teacher" ON payments FOR ALL TO authenticated USING (is_teacher() OR student_id = auth.uid()) WITH CHECK (is_teacher());

-- ДОСТИЖЕНИЯ
CREATE POLICY "ach_read"   ON achievement_defs FOR SELECT TO authenticated USING (TRUE);
CREATE POLICY "ach_write"  ON achievement_defs FOR ALL TO authenticated USING (is_teacher()) WITH CHECK (is_teacher());
CREATE POLICY "ua_read"    ON user_achievements FOR SELECT TO authenticated USING (
  student_id = auth.uid() OR is_teacher() OR is_curator()
);
CREATE POLICY "ua_insert"  ON user_achievements FOR INSERT TO authenticated WITH CHECK (TRUE);

-- ПЧЁЛКИ
CREATE POLICY "bee_read"   ON bee_transactions FOR SELECT TO authenticated USING (
  student_id = auth.uid() OR is_teacher() OR is_curator()
);
CREATE POLICY "bee_insert" ON bee_transactions FOR INSERT TO authenticated WITH CHECK (TRUE);

-- =========================================================
-- 15) ТРИГГЕРЫ
-- =========================================================
-- Когда добавилась попытка — обновить пчёлки и записать транзакцию
CREATE OR REPLACE FUNCTION on_attempt_insert() RETURNS TRIGGER AS $$
BEGIN
  IF NEW.bee_earned > 0 THEN
    INSERT INTO bee_transactions (student_id, amount, reason, source_kind, source_id, emoji)
    VALUES (NEW.student_id, NEW.bee_earned, 'за выполнение задания ' || NEW.ege_task_n, 'attempt', NEW.id, '🎯');
    UPDATE profiles SET bee = bee + NEW.bee_earned WHERE id = NEW.student_id;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER trg_attempt_insert AFTER INSERT ON attempts
FOR EACH ROW EXECUTE FUNCTION on_attempt_insert();

-- Триггер на вставку профиля при регистрации в auth.users
CREATE OR REPLACE FUNCTION on_auth_user_created() RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO profiles (id, role, full_name, email, s_type, s_status)
  VALUES (
    NEW.id,
    'student',
    COALESCE(NEW.raw_user_meta_data->>'full_name', NEW.email),
    NEW.email,
    'гость',
    'pending'
  );
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER trg_auth_user_created
AFTER INSERT ON auth.users
FOR EACH ROW EXECUTE FUNCTION on_auth_user_created();

-- =========================================================
-- 16) НАЧАЛЬНЫЕ ДАННЫЕ — 26 ЗАДАНИЙ ЕГЭ
-- =========================================================
INSERT INTO ege_tasks (n, topic, default_day) VALUES
  (1,  'Логико-смысловые отношения между предложениями', 3),
  (2,  'Лексикология. Лексический анализ слова',          3),
  (3,  'Функциональная стилистика. Культура речи',         3),
  (4,  'Орфоэпия. Нормы ударения',                          1),
  (5,  'Паронимы и их употребление',                        1),
  (6,  'Плеоназм. Тавтология. Сочетаемость',                1),
  (7,  'Морфологические нормы',                              2),
  (8,  'Синтаксические нормы',                               2),
  (9,  'Гласные и согласные в корне',                        1),
  (10, 'Ъ, Ь, приставки, ы и и после приставок',             1),
  (11, 'Правописание суффиксов',                              1),
  (12, 'Окончания глаголов и суффиксы причастий',             1),
  (13, 'Правописание не и ни',                                1),
  (14, 'Слитно/дефисно/раздельно',                            1),
  (15, '-Н- и -НН- в словах',                                 1),
  (16, 'Однородные. Знаки препинания в сложных предложениях', 2),
  (17, 'Знаки препинания при обособлении',                    2),
  (18, 'Вводные конструкции, обращения',                      2),
  (19, 'Сложноподчинённые предложения',                       2),
  (20, 'Сложные предложения с разными видами связи',          2),
  (21, 'Пунктуационный анализ предложения',                   2),
  (22, 'Изобразительно-выразительные средства',               3),
  (23, 'Информационно-смысловая переработка',                 3),
  (24, 'Виды информации в тексте',                            3),
  (25, 'Лексический анализ слова (повтор)',                   3),
  (26, 'Логико-смысловые отношения (повтор)',                 3);

-- 14 достижений
INSERT INTO achievement_defs (id, category, emoji, name, description, bee_reward) VALUES
  ('a1','showup','🐝','Первая пчёлка','Выполнила первое задание интенсива',5),
  ('a2','showup','☀️','Утренняя птичка','Прошла утреннюю разминку дня 1 до полудня',5),
  ('a3','showup','📅','Три дня вместе','Заходила на платформу каждый из трёх дней',10),
  ('a4','showup','🎙️','Слушающий ум','Посетила все три вебинара',10),
  ('a5','showup','✍️','Сочинение сдано','Сдала сочинение (за сам факт сдачи, до проверки)',5),
  ('b1','self','⚡','Быстрый старт','Выполнила задание раньше дедлайна дня',5),
  ('b2','self','🎯','Точно в цель','Сдала любой тест без ошибок',10),
  ('b3','self','📈','Рост','Пересдала тест и улучшила результат',5),
  ('b4','self','💪','Стабильный результат','Три теста подряд хотя бы на 70%',10),
  ('b5','self','🔁','Работа над ошибками','Открыла разбор после прохождения теста',5),
  ('c1','social','🤝','Помогла другу','Ответила на вопрос одноклассника в чате — учитель отметил твой ответ как полезный',10),
  ('c2','social','💬','Активный голос','Задала вопрос учителю в чате',5),
  ('c3','social','🐝🐝','Душа улья','Помогла трём одноклассникам за интенсив',15),
  ('f1','final','👑','Прошла Краш-тест','Дошла до 4 июня, мы вместе прошли весь интенсив',25);

-- Интенсив «Краш-тест 2026»
INSERT INTO intensives (name, start_date, end_date, exam_date, description, is_active) VALUES
  ('Краш-тест 2026', '2026-05-30', '2026-06-03', '2026-06-04',
   'Перед ЕГЭ — последняя репетиция. Три дня живых вебинаров, тренажёров и разборов.', TRUE);

-- Дни этого интенсива
INSERT INTO intensive_days (intensive_id, ord, day_date, kind, title, summary, ege_tasks, is_open) VALUES
  (1, 1, '2026-05-30', 'work', 'Орфография + задания 4–6', 'Утренняя разминка готова к старту', '{4,5,6,9,10,11,12,13,14,15}', TRUE),
  (1, 2, '2026-05-31', 'walk', 'Прогулка с друзьями', 'мотивация', '{}', FALSE),
  (1, 3, '2026-06-01', 'walk', 'Прогулка с друзьями', 'мотивация', '{}', FALSE),
  (1, 4, '2026-06-02', 'work', 'Пунктуация + задания 7–8 + 21', 'Ещё не открыт — ждите 2 июня', '{7,8,16,17,18,19,20,21}', FALSE),
  (1, 5, '2026-06-03', 'work', 'Текст + сочинение', 'Финальный день', '{1,2,3,22,23,24,25,26}', FALSE),
  (1, 6, '2026-06-04', 'exam', 'ЭКЗАМЕН', 'вперёд!', '{}', FALSE);

-- 40 пар паронимов
INSERT INTO paronym_pairs (word_a, word_b, hint) VALUES
  ('дипломатичный','дипломатический','Дипломатичный — тактичный (про человека). Дипломатический — относящийся к дипломатии (документ, корпус, миссия).'),
  ('представить','предоставить','Представить — познакомить, показать. Предоставить — дать в распоряжение, разрешить.'),
  ('надеть','одеть','Надеть — что-то на себя. Одеть — кого-то (ребёнка, куклу).'),
  ('эффектный','эффективный','Эффектный — производящий впечатление. Эффективный — приводящий к нужному результату.'),
  ('понятный','понятливый','Понятный — ясный (текст). Понятливый — быстро понимающий (человек).'),
  ('жизненный','житейский','Жизненный — связан с жизнью, важный (опыт). Житейский — обыденный (уклад, мудрость).'),
  ('жёсткий','жестокий','Жёсткий — твёрдый, строгий. Жестокий — безжалостный, причиняющий страдания.'),
  ('искусный','искусственный','Искусный — мастерский. Искусственный — ненастоящий, сделанный руками человека.'),
  ('удачный','удачливый','Удачный — получившийся (поход, день). Удачливый — везучий (человек).'),
  ('обидный','обидчивый','Обидный — причиняющий обиду (намёк). Обидчивый — легко обижающийся (человек).'),
  ('демократичный','демократический','Демократичный — простой в общении (стиль). Демократический — связанный с демократией (строй).'),
  ('технический','техничный','Технический — относящийся к технике. Техничный — выполненный мастерски, ловкий.'),
  ('комический','комичный','Комический — относящийся к жанру комедии. Комичный — забавный, смешной.'),
  ('драматический','драматичный','Драматический — относящийся к драме (театр). Драматичный — напряжённый, тяжёлый по содержанию.'),
  ('этический','этичный','Этический — относящийся к этике (норма). Этичный — соответствующий нормам морали (поступок).'),
  ('эстетический','эстетичный','Эстетический — относящийся к эстетике (вкус). Эстетичный — красивый внешне.'),
  ('органический','органичный','Органический — относящийся к живому. Органичный — естественный, гармоничный.'),
  ('дружеский','дружественный','Дружеский — между друзьями. Дружественный — между странами, организациями.'),
  ('желанный','желательный','Желанный — тот, кого ждут (гость). Желательный — нужный, рекомендуемый.'),
  ('безответный','безответственный','Безответный — без ответа (любовь). Безответственный — не несущий ответственности (человек).'),
  ('информативный','информационный','Информативный — содержащий много информации. Информационный — относящийся к информации (бюллетень).'),
  ('ледяной','ледовый','Ледяной — состоящий из льда (горка). Ледовый — относящийся ко льду (поле, побоище).'),
  ('лесистый','лесной','Лесистый — покрытый лесом (склон). Лесной — относящийся к лесу (тропа).'),
  ('глинистый','глиняный','Глинистый — содержащий глину (грунт). Глиняный — сделанный из глины (кувшин).'),
  ('двойной','двойственный','Двойной — состоящий из двух (дно). Двойственный — противоречивый (чувство).'),
  ('занятой','занятый','Занятой — постоянно занят делами (человек). Занятый — занят сейчас (стол, место).'),
  ('зрительный','зрительский','Зрительный — связан со зрением (нерв). Зрительский — связан со зрителями (зал, успех).'),
  ('единичный','единственный','Единичный — отдельный, не массовый (случай). Единственный — только один (друг, шанс).'),
  ('длинный','длительный','Длинный — большой по длине (волосы). Длительный — продолжительный во времени (отпуск).'),
  ('годичный','годовой','Годичный — длящийся год (курс). Годовой — за весь год (отчёт, бюджет).'),
  ('годовой','годовалый','Годовой — за год (доход). Годовалый — которому год (ребёнок, телёнок).'),
  ('действенный','действительный','Действенный — эффективный (метод). Действительный — настоящий, имеющий силу (билет).'),
  ('деловой','деловитый','Деловой — связан с делом (костюм). Деловитый — энергичный, занятой по виду.'),
  ('враждебный','вражеский','Враждебный — недружелюбный (взгляд). Вражеский — принадлежащий врагу (танк).'),
  ('памятный','памятливый','Памятный — запоминающийся (день). Памятливый — обладающий хорошей памятью.'),
  ('сравнимый','сравнительный','Сравнимый — поддающийся сравнению. Сравнительный — построенный на сравнении (анализ).'),
  ('явный','явственный','Явный — очевидный, открытый (обман). Явственный — отчётливый (звук, шёпот).'),
  ('униженный','унизительный','Униженный — испытавший унижение (вид). Унизительный — оскорбительный (положение).'),
  ('звериный','зверский','Звериный — принадлежащий зверю (тропа). Зверский — жестокий, как у зверя (поступок).'),
  ('царский','царственный','Царский — принадлежащий царю (трон). Царственный — величественный (осанка).');

-- =========================================================
-- ВСЁ. После запуска — таблицы созданы, политики безопасности включены,
-- 26 заданий ЕГЭ + 14 достижений + 40 пар паронимов уже в базе.
-- =========================================================
