-- =============================================================================
-- 2026-05-29 — game_attempts: трекинг незавершённых попыток
-- =============================================================================
-- Прецедент: 29.05.2026 учителя жалуются что у учеников «вылетают игры».
-- Без записи о начатой попытке учитель этого не видит — game_attempts
-- создавалась только при успешном завершении через postMessage.
--
-- Меняем подход: при открытии игры клиент сразу INSERT-ит запись со score=0
-- и finished_at=NULL. При успешном завершении делает UPDATE с финальными
-- данными и finished_at=now(). Если ученик закрыл вкладку, ушёл в фон,
-- игра упала — запись остаётся со finished_at IS NULL → учитель видит
-- «🟡 не закончил».
-- =============================================================================

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'game_attempts'
      AND column_name = 'finished_at'
  ) THEN
    ALTER TABLE game_attempts
      ADD COLUMN finished_at timestamptz;
    /* Все существующие записи считаем завершёнными (они были созданы
       только при успехе через старый код). */
    UPDATE game_attempts
       SET finished_at = created_at
     WHERE finished_at IS NULL;
    CREATE INDEX game_attempts_pending_idx
      ON game_attempts(student_id, game_id)
     WHERE finished_at IS NULL;
  END IF;
END $$;

COMMENT ON COLUMN game_attempts.finished_at IS
  'Когда попытка завершилась (получен результат от игры). NULL = ученик начал, но не закончил (вылетело/закрыл).';

-- Проверка
DO $$
DECLARE
  total int;
  finished int;
  pending int;
BEGIN
  SELECT COUNT(*) INTO total FROM game_attempts;
  SELECT COUNT(*) INTO finished FROM game_attempts WHERE finished_at IS NOT NULL;
  SELECT COUNT(*) INTO pending FROM game_attempts WHERE finished_at IS NULL;
  RAISE NOTICE 'game_attempts: всего %, завершённых %, незавершённых %', total, finished, pending;
END $$;
