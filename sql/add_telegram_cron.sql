-- =========================================================
-- TG-АВТОУВЕДОМЛЕНИЯ ПО РАСПИСАНИЮ — крон
--
-- Что добавляем:
--   • колонки *_notified_at для идемпотентности (не слать дважды)
--   • расширения pg_cron + pg_net (если ещё не включены)
--   • cron-задание раз в минуту — POST на Edge Function tg-cron
--
-- Перед прогоном этого файла:
--   1) Supabase Dashboard → Database → Extensions → включить pg_cron и pg_net
--      (если уже включены — пропустить)
--   2) Edge Function tg-cron должна быть задеплоена (Verify JWT = OFF,
--      её защищает SECRET в URL).
-- =========================================================

-- 1) Идемпотентность: храним «уже уведомили»
ALTER TABLE day_activities
  ADD COLUMN IF NOT EXISTS webinar_reminded_at TIMESTAMPTZ;

ALTER TABLE intensive_days
  ADD COLUMN IF NOT EXISTS open_notified_at TIMESTAMPTZ;

-- 2) Включаем расширения (если ещё не включены)
CREATE EXTENSION IF NOT EXISTS pg_cron;
CREATE EXTENSION IF NOT EXISTS pg_net;

-- 3) Удалим старое cron-задание (если перезапускаем)
SELECT cron.unschedule('tg-cron-minute') WHERE EXISTS (
  SELECT 1 FROM cron.job WHERE jobname = 'tg-cron-minute'
);

-- 4) Регистрируем крон: каждую минуту POST на tg-cron Edge Function.
--    ⚠ TG_CRON_SECRET и TG_CRON_URL — замени на свои значения ниже!
--    URL формата https://hyczawwuehrqsqqosgub.supabase.co/functions/v1/tg-cron
--    Secret любая длинная строка, она же должна быть в Edge Function secret.
SELECT cron.schedule(
  'tg-cron-minute',
  '* * * * *',  -- каждую минуту
  $$
    SELECT net.http_post(
      url := 'https://hyczawwuehrqsqqosgub.supabase.co/functions/v1/tg-cron',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'X-Cron-Secret', 'zr_cron_4f8a1c3e9b7d2f6a'
      ),
      body := '{}'::jsonb,
      timeout_milliseconds := 30000
    );
  $$
);

-- 5) Проверка
SELECT jobid, jobname, schedule, active FROM cron.job WHERE jobname = 'tg-cron-minute';
