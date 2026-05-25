-- Серверная отправка push для отложенных постов «Разогрев».
--
-- ЗАЧЕМ. До этой миграции push рассылался клиентом в момент сохранения поста
-- учителем. Для отложенной публикации это плохо: учитель в 22:00 настраивает
-- пост на 8:00 завтра — push приходит ученикам сейчас, а самого поста они не
-- видят до утра.
--
-- РЕШЕНИЕ. pg_cron каждые 5 минут вызывает Edge Function
-- process-scheduled-warmup-pushes. Та сканирует warmup_blocks/warmup_days,
-- находит созревшие (publish_at <= now() AND push_sent_at IS NULL),
-- рассылает push и помечает push_sent_at=now(). При этом клиент перестаёт
-- слать push для постов с publish_at в будущем (см. index.html addWarmupBlock).
--
-- ВАЖНО ПЕРЕД ПРИМЕНЕНИЕМ:
--   1. В Supabase Dashboard включить расширения pg_cron и pg_net
--      (Database → Extensions).
--   2. Edge Function process-scheduled-warmup-pushes должна быть задеплоена
--      (supabase functions deploy process-scheduled-warmup-pushes).
--   3. В этой миграции ЗАМЕНИТЬ <PROJECT_REF> и <SERVICE_ROLE_KEY>
--      на свои значения (см. Supabase Dashboard → Settings → API).

------------------------------------------------------------------
-- 1. Колонки трекинга — чтобы не слать push повторно
------------------------------------------------------------------

ALTER TABLE warmup_blocks
  ADD COLUMN IF NOT EXISTS push_sent_at timestamptz NULL;

ALTER TABLE warmup_days
  ADD COLUMN IF NOT EXISTS push_sent_at timestamptz NULL;

COMMENT ON COLUMN warmup_blocks.push_sent_at IS
  'Когда отправлен push для этого поста (NULL = ещё не отправлено)';

COMMENT ON COLUMN warmup_days.push_sent_at IS
  'Когда отправлен push для появления этого дня';

-- Для постов, опубликованных СРАЗУ (клиентский push) — считаем
-- что push уже «отправлен», чтобы cron не задублировал.
-- (Безопасно: эти посты были созданы до миграции.)
UPDATE warmup_blocks
  SET push_sent_at = COALESCE(created_at, now())
  WHERE is_published = true
    AND (publish_at IS NULL OR publish_at <= now())
    AND push_sent_at IS NULL;

UPDATE warmup_days
  SET push_sent_at = COALESCE(created_at, now())
  WHERE is_published = true
    AND (publish_at IS NULL OR publish_at <= now())
    AND push_sent_at IS NULL;

-- Индекс ускоряет cron-запрос «найди созревшие, по которым push не уходил»
CREATE INDEX IF NOT EXISTS idx_warmup_blocks_push_pending
  ON warmup_blocks(publish_at)
  WHERE push_sent_at IS NULL AND publish_at IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_warmup_days_push_pending
  ON warmup_days(publish_at)
  WHERE push_sent_at IS NULL AND publish_at IS NOT NULL;

------------------------------------------------------------------
-- 2. Расширения pg_cron + pg_net
------------------------------------------------------------------

-- Если расширения уже включены через Dashboard — эти строки безвредны.
-- Если нет — миграция упадёт с понятной ошибкой, иди в Dashboard включить.
CREATE EXTENSION IF NOT EXISTS pg_cron;
CREATE EXTENSION IF NOT EXISTS pg_net;

------------------------------------------------------------------
-- 3. SQL-обёртка над HTTP-вызовом (чтобы секреты лежали в одном месте)
------------------------------------------------------------------

-- ВАЖНО: замени <PROJECT_REF> на ID своего проекта и <SERVICE_ROLE_KEY>
-- на свой service_role key из Settings → API.
-- Без замены cron-задача будет падать с 401.

CREATE OR REPLACE FUNCTION public.trigger_warmup_push_cron()
RETURNS bigint
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_url    text := 'https://hyczawwuehrqsqqosgub.functions.supabase.co/process-scheduled-warmup-pushes';
  v_secret text := '<LEGACY_SERVICE_ROLE_REDACTED>';
  v_request_id bigint;
BEGIN
  SELECT net.http_post(
    url     := v_url,
    headers := jsonb_build_object(
      'Content-Type',  'application/json',
      'Authorization', 'Bearer ' || v_secret
    ),
    body    := '{}'::jsonb,
    timeout_milliseconds := 30000
  ) INTO v_request_id;
  RETURN v_request_id;
END;
$$;

COMMENT ON FUNCTION public.trigger_warmup_push_cron() IS
  'HTTP-вызов Edge Function process-scheduled-warmup-pushes. Вызывается из cron каждые 5 минут.';

------------------------------------------------------------------
-- 4. Планировщик: каждые 5 минут
------------------------------------------------------------------

-- Если задача с таким именем уже есть — снимаем её
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'process-scheduled-warmup-pushes') THEN
    PERFORM cron.unschedule('process-scheduled-warmup-pushes');
  END IF;
END $$;

SELECT cron.schedule(
  'process-scheduled-warmup-pushes',
  '*/5 * * * *',
  $cron$SELECT public.trigger_warmup_push_cron();$cron$
);

-- Проверка: задача появилась?
-- SELECT jobid, jobname, schedule, active FROM cron.job
--   WHERE jobname = 'process-scheduled-warmup-pushes';

-- Лог выполнений (последние 20):
-- SELECT * FROM cron.job_run_details
--   WHERE jobid = (SELECT jobid FROM cron.job WHERE jobname='process-scheduled-warmup-pushes')
--   ORDER BY start_time DESC LIMIT 20;
