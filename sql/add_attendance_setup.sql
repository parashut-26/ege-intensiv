-- ============================================================
-- Миграция: посещаемость интенсива «Краш-тест 2026»
--
-- Что делает:
--   1. Создаёт (если нет) интенсив «Краш-тест 2026», 3 дня и 3 вебинара —
--      привязки для attendance.
--   2. Триггер на INSERT в attendance: автоматически начисляет ученику
--      +3 🐝 в bee_transactions (один раз — UNIQUE на attendance это
--      гарантирует).
--   3. Расширяет SELECT-RLS для day_activities/intensive_days, чтобы
--      ученик мог видеть свои дни и активности.
--
-- Запустить однократно в Supabase SQL Editor.
-- ============================================================

-- 0. Параметризация (даты интенсива)
DO $$
DECLARE
  intensive_id_v INTEGER;
  day1_id_v INTEGER;
  day2_id_v INTEGER;
  day3_id_v INTEGER;
BEGIN
  -- Создаём интенсив, если ещё нет.
  -- В схеме колонка называется `name` (не `title`).
  SELECT id INTO intensive_id_v FROM intensives WHERE name = 'Краш-тест 2026' LIMIT 1;
  IF intensive_id_v IS NULL THEN
    INSERT INTO intensives (name, start_date, end_date)
    VALUES ('Краш-тест 2026', DATE '2026-05-30', DATE '2026-06-04')
    RETURNING id INTO intensive_id_v;
  END IF;

  -- 3 дня
  INSERT INTO intensive_days (intensive_id, ord, day_date, title, emoji, is_open)
  VALUES
    (intensive_id_v, 1, DATE '2026-05-30', 'День 1 · Орфоэпия и лексика', '☀️', TRUE),
    (intensive_id_v, 2, DATE '2026-05-31', 'День 2 · Грамматика и пунктуация', '🌤', FALSE),
    (intensive_id_v, 3, DATE '2026-06-01', 'День 3 · Сочинение', '🎯', FALSE)
  ON CONFLICT DO NOTHING;

  SELECT id INTO day1_id_v FROM intensive_days WHERE intensive_id = intensive_id_v AND ord = 1;
  SELECT id INTO day2_id_v FROM intensive_days WHERE intensive_id = intensive_id_v AND ord = 2;
  SELECT id INTO day3_id_v FROM intensive_days WHERE intensive_id = intensive_id_v AND ord = 3;

  -- 3 вебинара (по одному на день, в 13:00)
  -- Сначала проверим, что подобная активность ещё не создана для этого дня и kind=webinar
  IF NOT EXISTS (SELECT 1 FROM day_activities WHERE day_id = day1_id_v AND kind = 'webinar') THEN
    INSERT INTO day_activities (day_id, kind, title, est_min, start_at, max_bee)
    VALUES (day1_id_v, 'webinar', 'Вебинар День 1 · разбор орфоэпии', 90, TIME '13:00', 3);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM day_activities WHERE day_id = day2_id_v AND kind = 'webinar') THEN
    INSERT INTO day_activities (day_id, kind, title, est_min, start_at, max_bee)
    VALUES (day2_id_v, 'webinar', 'Вебинар День 2 · грамматика', 90, TIME '13:00', 3);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM day_activities WHERE day_id = day3_id_v AND kind = 'webinar') THEN
    INSERT INTO day_activities (day_id, kind, title, est_min, start_at, max_bee)
    VALUES (day3_id_v, 'webinar', 'Вебинар День 3 · сочинение', 90, TIME '13:00', 3);
  END IF;
END $$;

-- 1. Триггер на attendance: +3 🐝 автору при INSERT
CREATE OR REPLACE FUNCTION on_attendance_insert() RETURNS TRIGGER AS $$
DECLARE
  bee_amount INTEGER;
BEGIN
  -- Сколько пчёлок за активность: берём из day_activities.max_bee, по умолчанию 3
  SELECT COALESCE(max_bee, 3) INTO bee_amount FROM day_activities WHERE id = NEW.activity_id;
  IF bee_amount IS NULL THEN bee_amount := 3; END IF;

  IF bee_amount > 0 THEN
    INSERT INTO bee_transactions (student_id, amount, reason, source_kind, source_id, emoji)
    VALUES (
      NEW.student_id,
      bee_amount,
      'посещение вебинара',
      'attendance',
      NEW.activity_id,
      '🎙️'
    );
    UPDATE profiles SET bee = COALESCE(bee, 0) + bee_amount WHERE id = NEW.student_id;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trg_attendance_insert ON attendance;
CREATE TRIGGER trg_attendance_insert
  AFTER INSERT ON attendance
  FOR EACH ROW EXECUTE FUNCTION on_attendance_insert();

-- 2. RLS: позволим ученикам читать активности (день/вебинар) — нужно чтобы
--    видеть, на какой вебинар их записали. По умолчанию таблицы
--    intensive_days / day_activities закрыты.
--    (Если политики уже есть — не упадём, DROP IF EXISTS делает это безопасным.)
DROP POLICY IF EXISTS "intensive_days_read" ON intensive_days;
CREATE POLICY "intensive_days_read" ON intensive_days FOR SELECT TO authenticated USING (TRUE);

DROP POLICY IF EXISTS "day_activities_read" ON day_activities;
CREATE POLICY "day_activities_read" ON day_activities FOR SELECT TO authenticated USING (TRUE);

-- 3. Проверка
SELECT 'Setup done' AS status,
       (SELECT COUNT(*) FROM intensive_days) AS days,
       (SELECT COUNT(*) FROM day_activities WHERE kind = 'webinar') AS webinars;
