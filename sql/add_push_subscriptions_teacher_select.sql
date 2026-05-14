-- =========================================================
-- Чтобы счётчик «Подписаны на пуш» в чек-листе готовности
-- видел подписки всех учеников, а не только свои —
-- учителю/куратору даём SELECT на push_subscriptions.
--
-- Каждый user по-прежнему может SELECT/INSERT/DELETE свои строки
-- (через user_id = auth.uid()), это поведение НЕ ломаем.
-- =========================================================

-- Включаем RLS если ещё нет (на всякий)
ALTER TABLE push_subscriptions ENABLE ROW LEVEL SECURITY;

-- Учителю/куратору — читать все подписки (для статистики).
DROP POLICY IF EXISTS "push_subscriptions teacher select all" ON push_subscriptions;
CREATE POLICY "push_subscriptions teacher select all"
  ON push_subscriptions
  FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM profiles p
       WHERE p.id = auth.uid()
         AND p.role IN ('teacher','curator')
    )
  );

-- Проверка
SELECT 'push_subscriptions: teacher SELECT policy ok' AS status;
