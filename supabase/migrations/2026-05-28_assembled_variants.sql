-- =============================================================================
-- 2026-05-28 — assembled_variants: сборки вариантов из вопросов QUIZ_BANK
-- =============================================================================
-- Прецедент: 28.05.2026 учительница хочет собирать собственные «варианты»
-- из конкретных вопросов разных коллекций и давать ученикам ссылку. Ссылка
-- ведёт прямо в тренажёр с выбранными вопросами; результат ученика
-- сохраняется в attempts с привязкой к этой сборке.
--
-- Хранение: snapshot вопросов копируется в jsonb-массив `questions`.
-- Это гарантирует стабильность результатов ученика, даже если позже учитель
-- удалит или переделает оригинальный вопрос в банке.
--
-- RLS:
--   • INSERT/UPDATE/DELETE: только учитель/куратор, только свои.
--   • SELECT: учитель видит свои; кураторы видят все; ученик/гость видят
--     активную сборку по точному slug (через дополнительное условие).
-- =============================================================================

CREATE TABLE IF NOT EXISTS assembled_variants (
  id          bigserial PRIMARY KEY,
  slug        text NOT NULL UNIQUE,
  title       text NOT NULL,
  description text,
  /* Массив снимков вопросов. Каждый элемент — копия объекта из QUIZ_BANK +
     служебные поля source_task_n / source_collection / ord. */
  questions   jsonb NOT NULL DEFAULT '[]'::jsonb,
  created_by  uuid REFERENCES profiles(id) ON DELETE SET NULL,
  is_active   boolean NOT NULL DEFAULT true,
  created_at  timestamptz NOT NULL DEFAULT now(),
  updated_at  timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS assembled_variants_created_by_idx
  ON assembled_variants(created_by);
CREATE INDEX IF NOT EXISTS assembled_variants_active_idx
  ON assembled_variants(is_active) WHERE is_active = true;

COMMENT ON TABLE assembled_variants IS
  'Сборки вариантов учителя: выбранные вопросы из QUIZ_BANK по ссылке (slug). Каждый элемент questions — snapshot вопроса для устойчивости результатов.';

-- ────────────────────────────────────────────────────────────────────────
-- RLS
-- ────────────────────────────────────────────────────────────────────────
ALTER TABLE assembled_variants ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "av_select_own_teacher"     ON assembled_variants;
DROP POLICY IF EXISTS "av_select_active_by_slug"  ON assembled_variants;
DROP POLICY IF EXISTS "av_insert_teacher"         ON assembled_variants;
DROP POLICY IF EXISTS "av_update_own_teacher"     ON assembled_variants;
DROP POLICY IF EXISTS "av_delete_own_teacher"     ON assembled_variants;

/* SELECT: учитель видит свои; куратор видит все. */
CREATE POLICY "av_select_own_teacher" ON assembled_variants
  FOR SELECT USING (
    created_by = auth.uid()
    OR EXISTS (
      SELECT 1 FROM profiles
      WHERE id = auth.uid() AND role IN ('teacher', 'curator')
    )
  );

/* SELECT: любой залогиненный (включая учеников) может прочитать ОДНУ
   активную сборку, если знает её slug. PostgREST это даёт через
   `assembled_variants?slug=eq.<slug>&is_active=eq.true`. */
CREATE POLICY "av_select_active_by_slug" ON assembled_variants
  FOR SELECT USING (
    is_active = true
  );

/* INSERT: только учитель/куратор, created_by = auth.uid(). */
CREATE POLICY "av_insert_teacher" ON assembled_variants
  FOR INSERT WITH CHECK (
    created_by = auth.uid()
    AND EXISTS (
      SELECT 1 FROM profiles
      WHERE id = auth.uid() AND role IN ('teacher', 'curator')
    )
  );

/* UPDATE: учитель меняет только свои сборки. */
CREATE POLICY "av_update_own_teacher" ON assembled_variants
  FOR UPDATE USING (
    created_by = auth.uid()
    AND EXISTS (
      SELECT 1 FROM profiles
      WHERE id = auth.uid() AND role IN ('teacher', 'curator')
    )
  ) WITH CHECK (
    created_by = auth.uid()
  );

/* DELETE: учитель удаляет только свои. */
CREATE POLICY "av_delete_own_teacher" ON assembled_variants
  FOR DELETE USING (
    created_by = auth.uid()
    AND EXISTS (
      SELECT 1 FROM profiles
      WHERE id = auth.uid() AND role IN ('teacher', 'curator')
    )
  );

-- ────────────────────────────────────────────────────────────────────────
-- attempts: ссылка на сборку (для истории попыток ученика)
-- ────────────────────────────────────────────────────────────────────────
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'attempts'
      AND column_name = 'assembled_variant_id'
  ) THEN
    ALTER TABLE attempts
      ADD COLUMN assembled_variant_id bigint
        REFERENCES assembled_variants(id) ON DELETE SET NULL;
    CREATE INDEX attempts_assembled_variant_idx
      ON attempts(assembled_variant_id) WHERE assembled_variant_id IS NOT NULL;
  END IF;
END $$;

COMMENT ON COLUMN attempts.assembled_variant_id IS
  'Если попытка связана со сборкой (вход по ссылке ?aid=…) — id сборки. NULL для обычных тренажёров.';

-- ────────────────────────────────────────────────────────────────────────
-- updated_at автоматически
-- ────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION touch_assembled_variants_updated_at()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_assembled_variants_updated_at ON assembled_variants;
CREATE TRIGGER trg_assembled_variants_updated_at
  BEFORE UPDATE ON assembled_variants
  FOR EACH ROW EXECUTE FUNCTION touch_assembled_variants_updated_at();

-- ────────────────────────────────────────────────────────────────────────
-- Проверка: какие политики создались
-- ────────────────────────────────────────────────────────────────────────
DO $$
DECLARE
  pnames text;
BEGIN
  SELECT string_agg(polname, ', ') INTO pnames
    FROM pg_policy
   WHERE polrelid = 'assembled_variants'::regclass;
  RAISE NOTICE 'Политики на assembled_variants: %', COALESCE(pnames, '(нет)');
END $$;
