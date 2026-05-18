-- =========================================================
-- Снимаем FK constraint game_day_assignments.day_id → intensive_days(id).
-- Причина: в платформе DAYS — локальный массив (id = 1/2/3), который
-- не гарантированно совпадает с фактическими ID в таблице intensive_days.
-- В test_variants.day_id такой же FK отсутствует, поэтому пробники работают.
-- Приводим game_day_assignments к той же модели.
-- =========================================================

ALTER TABLE game_day_assignments
  DROP CONSTRAINT IF EXISTS game_day_assignments_day_id_fkey;

-- Проверка: constraint удалён
SELECT 'fk_dropped' AS status,
  COUNT(*) AS remaining_fks
FROM information_schema.table_constraints
WHERE table_name = 'game_day_assignments'
  AND constraint_type = 'FOREIGN KEY'
  AND constraint_name = 'game_day_assignments_day_id_fkey';
