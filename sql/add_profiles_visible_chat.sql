-- ============================================================
-- Миграция: разрешить ученикам видеть профили учителей/кураторов
-- (нужно для отображения имени собеседника в ЛС-чате).
-- Запустить в Supabase SQL Editor.
--
-- До миграции: profiles_self_select разрешал ученику видеть только
-- своих одноклассников (s_status='active') + свой собственный
-- профиль. Учителей/кураторов ученик не видел, и в ЛС-чате
-- собеседник отображался как «Удалён».
-- ============================================================

DROP POLICY IF EXISTS "profiles_self_select" ON profiles;
CREATE POLICY "profiles_self_select" ON profiles FOR SELECT TO authenticated
  USING (
    id = auth.uid()
    OR is_teacher()
    OR is_curator()
    OR s_status = 'active'
    -- Любой авторизованный видит учителей и кураторов: нужно для шапки
    -- ЛС-чата + чтобы увидеть кто проверяет сочинение и т.п.
    OR role IN ('teacher', 'curator')
  );

-- Проверка
SELECT 'profiles_self_select обновлена' AS status;
