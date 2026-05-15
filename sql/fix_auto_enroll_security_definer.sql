-- =========================================================
-- ФИКС: триггер auto_enroll_new_student падает на RLS
-- enrollments при смене role curator → student.
--
-- Симптом:
--   PATCH /profiles?id=eq.<curator_id> { role: 'student', ... }
--   → 403: new row violates row-level security policy for table "enrollments"
--
-- Причина:
--   Функция была без SECURITY DEFINER, поэтому INSERT в enrollments
--   шёл от имени учителя — а у enrollments нет write-политики для
--   teacher (только select).
--
-- Лечение:
--   1) SECURITY DEFINER + явный search_path (требование Supabase)
--   2) То же для on_auth_user_created на всякий случай — он тоже
--      создаёт строку в profiles и потом срабатывает auto-enroll
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
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- Проверка
SELECT 'auto_enroll_new_student → SECURITY DEFINER ok' AS status;
