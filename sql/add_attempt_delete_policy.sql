-- =========================================================
-- ПРАВО НА УДАЛЕНИЕ ПОПЫТОК — ТОЛЬКО УЧИТЕЛЬ
--
-- Контекст:
--   В таблице attempts уже есть policy:
--     att_self        (SELECT — ученик свои, учитель/куратор все)
--     att_insert_self (INSERT — ученик только свои)
--   На DELETE политик НЕТ. По умолчанию RLS = всё запрещено,
--   поэтому ни ученик, ни даже учитель не могут удалить попытку.
--
--   Добавляем единственную DELETE-политику — только для учителя.
--   Ученики и кураторы НЕ могут удалять. Это защита от случайного
--   и намеренного «обнуления» истории попыток самим учеником.
-- =========================================================

DROP POLICY IF EXISTS "att_delete_teacher" ON attempts;
CREATE POLICY "att_delete_teacher" ON attempts
  FOR DELETE TO authenticated
  USING (is_teacher());

SELECT 'attempts: delete policy (teacher only) ok' AS status;
