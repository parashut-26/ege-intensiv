-- =========================================================
-- АВТО-ЗАПИСЬ УЧЕНИКОВ НА АКТИВНЫЙ ИНТЕНСИВ
--
-- Триггер: когда создаётся новый профиль с role='student', он автоматически
-- попадает в enrollments на активный интенсив. Если активного нет — никуда.
-- =========================================================

CREATE OR REPLACE FUNCTION auto_enroll_new_student()
RETURNS TRIGGER AS $$
DECLARE
  active_intensive_id INTEGER;
BEGIN
  IF NEW.role = 'student' THEN
    SELECT id INTO active_intensive_id
    FROM intensives
    WHERE is_active = TRUE
    ORDER BY start_date DESC
    LIMIT 1;

    IF active_intensive_id IS NOT NULL THEN
      INSERT INTO enrollments (student_id, intensive_id)
      VALUES (NEW.id, active_intensive_id)
      ON CONFLICT (student_id, intensive_id) DO NOTHING;
    END IF;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_auto_enroll_student ON profiles;
CREATE TRIGGER trg_auto_enroll_student
  AFTER INSERT OR UPDATE OF role ON profiles
  FOR EACH ROW
  EXECUTE FUNCTION auto_enroll_new_student();

-- Заодно — однократно записать всех существующих учеников
INSERT INTO enrollments (student_id, intensive_id)
SELECT p.id, i.id
FROM profiles p
CROSS JOIN intensives i
WHERE p.role = 'student' AND i.is_active = TRUE
ON CONFLICT (student_id, intensive_id) DO NOTHING;

SELECT COUNT(*) AS total_enrollments FROM enrollments;
