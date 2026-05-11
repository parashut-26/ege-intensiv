# Telegram-уведомления, часть 2: остальные триггеры

Добавляем 4 новых типа уведомлений:

| # | Кому | Когда |
|---|---|---|
| 1 | Ученику | Когда учитель/куратор финализировал его сочинение (`status=done`) |
| 2 | Учителю + кураторам | Когда ученик отправил новое сочинение (`status=submitted`) |
| 3 | Учителю | Когда куратор сделал предварительную проверку (`status=pre_checked`) |
| 4 | Всем enrolled ученикам | За час до вебинара (через pg_cron) |
| 5 | Всем enrolled ученикам | При открытии нового дня в 9:00 МСК (через pg_cron) |

Триггеры 1–3 — уже во фронте (`index.html`), уйдут с `git push`. Триггеры 4–5 — серверные, через `pg_cron`. Настройка ниже.

---

## Шаг 1. Включить расширения pg_cron и pg_net

В Supabase Dashboard:

1. Слева внизу → **Database** → **Extensions**
2. В поле поиска набери **`pg_cron`** → найди в списке → **Enable** (если ещё не включено)
3. Аналогично — **`pg_net`** → **Enable**

Если уже включены — пропусти.

## Шаг 2. Добавить секрет TG_CRON_SECRET

1. Supabase Dashboard → **Project Settings** → **Edge Functions** → **Manage secrets**
2. **+ Add new secret**
3. Name: `TG_CRON_SECRET`
4. Value: `zr_cron_4f8a1c3e9b7d2f6a`
5. Save

## Шаг 3. Залить Edge Function `tg-cron`

1. Supabase → **Edge Functions** → **Deploy a new function → Via Editor**
2. **Name:** `tg-cron`
3. **❗ Verify JWT — выключи** (OFF / серый тоггл). Защищаем через X-Cron-Secret.
4. Удали дефолтный код, вставь содержимое файла:
 `/Users/olgakh/Documents/Claude/Projects/Приложение/supabase/functions/tg-cron/index.ts`
5. Deploy

## Шаг 4. Прогнать SQL-миграцию

1. SQL Editor → New query
2. Открой файл `sql/add_telegram_cron.sql` и **скопируй содержимое целиком**
3. Вставь → Run
4. В конце должна вывестись 1 строка с задачей `tg-cron-minute` (active=true)

## Шаг 5. `git push`

В Терминале:

```bash
cd "/Users/olgakh/Documents/Claude/Projects/Приложение" && \
rm -f .git/index.lock .git/HEAD.lock && \
git add index.html supabase/functions/tg-send/index.ts supabase/functions/tg-cron/index.ts sql/add_telegram_cron.sql TELEGRAM_SETUP_PART2.md && \
git commit -m "TG-уведомления часть 2: сочинения, день, вебинар через pg_cron" && \
git push
```

---

## Тест

### Тест №1: сочинение проверено

1. Зайди как ученик → отправь сочинение
2. Зайди как учитель → открой сочинение → проверь → нажми «Опубликовать ученику»
3. Ученику в Telegram должно прилететь: «🎉 Сочинение проверено! Итоговый балл: X / 22»

### Тест №2: новое сочинение на проверку

1. Зайди как ученик → отправь новое сочинение
2. Учителю и всем кураторам в Telegram должно прилететь: «📝 Новое сочинение на проверку. От: Имя»

### Тест №3: открытие дня

Будет автоматически срабатывать **30 мая в 9:00 МСК** (старт интенсива). Проверить заранее можно так:

1. В Supabase SQL Editor выполни:
 ```sql
 UPDATE intensive_days SET open_notified_at = NULL, day_date = CURRENT_DATE
 WHERE ord = 1 AND intensive_id = (SELECT id FROM intensives WHERE is_active);
 ```
2. Подожди до следующей минуты (cron срабатывает раз в минуту)
3. Если сейчас 9:00 МСК или позже — всем учащимся придёт «📅 Открыт День 1!»

После теста верни date обратно:
```sql
UPDATE intensive_days SET day_date = '2026-05-30' WHERE ord = 1 AND intensive_id = (SELECT id FROM intensives WHERE is_active);
```

### Тест №4: вебинар через час

1. В SQL Editor — сдвинь webinar на «через час»:
 ```sql
 UPDATE day_activities
 SET start_at = (CURRENT_TIME + INTERVAL '60 minutes')::TIME,
     webinar_reminded_at = NULL
 WHERE kind = 'webinar' AND day_id = (
   SELECT id FROM intensive_days WHERE ord = 1 AND intensive_id = (SELECT id FROM intensives WHERE is_active)
 );

 UPDATE intensive_days SET day_date = CURRENT_DATE
 WHERE ord = 1 AND intensive_id = (SELECT id FROM intensives WHERE is_active);
 ```
2. Подожди до следующей минуты
3. Всем enrolled должно прилететь «🎙 Вебинар через час!»

После теста — верни обратно реальные даты/время.

---

## Если что-то не пошло

- **Cron-задача не запускается:** Supabase → Database → **Cron jobs** (или SQL: `SELECT * FROM cron.job_run_details ORDER BY start_time DESC LIMIT 10;`) — там видно успехи/ошибки запусков.
- **`tg-cron` падает:** Edge Functions → tg-cron → **Logs** — увидим стек.
- **Уведомления не приходят:** проверь что у учеников `telegram_id` заполнен и `tg_notify_enabled = true`.
