# Подключение Telegram-уведомлений — пошаговая инструкция

Готовые файлы уже в репо:
- `sql/add_telegram_integration.sql` — миграция БД
- `supabase/functions/tg-webhook/index.ts` — обработчик входящих от Telegram
- `supabase/functions/tg-send/index.ts` — универсальная отправка уведомлений
- Кнопка «🤖 Привязать Telegram» во фронте — уже в `index.html`
- Триггер «новое сообщение в ЛС» → TG — уже в `index.html`

Бот: **@ZRMoveBot**. Токен есть.

---

## Шаг 1. Прогнать SQL-миграцию

Открой Supabase Dashboard → SQL Editor → New Query. Скопируй содержимое файла `sql/add_telegram_integration.sql` и нажми Run. В конце должно вывести 4 строки с новыми колонками — это проверка.

## Шаг 2. Добавить секреты в Supabase

Supabase Dashboard → Project Settings → **Edge Functions** → **Manage secrets** → New secret.

Добавь **три** секрета:

| Имя | Значение |
|---|---|
| `TELEGRAM_BOT_TOKEN` | `7813524187:AAG96ICwtP2wmMOTKmN05WmWrV_YXKeWd_U` |
| `TELEGRAM_WEBHOOK_SECRET` | `zr_wh_8f4c9b2a1e6d5f3a_v1` |
| (уже есть) `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY` | — берутся автоматически |

Секрет вебхука — это секретная строка-«подпись» в заголовке, которой бот доказывает что запрос идёт от Telegram, а не от прохожего. Можно оставить как есть или сгенерить свою — главное чтобы совпадало с тем, что пошлёшь в `setWebhook` на шаге 4.

## Шаг 3. Залить две Edge Functions

Supabase Dashboard → **Edge Functions** → **Create a new function**.

### 3.1. Функция `tg-webhook`

- Имя: `tg-webhook`
- Verify JWT: **Off** (важно — Telegram не пришлёт JWT)
- Код: скопируй из файла `supabase/functions/tg-webhook/index.ts`
- Deploy

### 3.2. Функция `tg-send`

- Имя: `tg-send`
- Verify JWT: **On** (обычные пользователи проходят через свой JWT)
- Код: скопируй из файла `supabase/functions/tg-send/index.ts`
- Deploy

## Шаг 4. Зарегистрировать webhook у Telegram

В Терминале выполни одной строкой:

```bash
curl -s -X POST "https://api.telegram.org/bot7813524187:AAG96ICwtP2wmMOTKmN05WmWrV_YXKeWd_U/setWebhook" \
  -H "Content-Type: application/json" \
  -d '{
    "url": "https://hyczawwuehrqsqqosgub.supabase.co/functions/v1/tg-webhook",
    "secret_token": "zr_wh_8f4c9b2a1e6d5f3a_v1",
    "drop_pending_updates": true
  }'
```

Должно вернуть `{"ok":true,"result":true,"description":"Webhook was set"}`.

Проверка статуса:

```bash
curl -s "https://api.telegram.org/bot7813524187:AAG96ICwtP2wmMOTKmN05WmWrV_YXKeWd_U/getWebhookInfo"
```

Должно показать `url: https://hyczawwuehrqsqqosgub...` и `pending_update_count: 0`.

## Шаг 5. Тест

1. Зайди как ученик на zebrus.online → вкладка «Профиль» → нажми «🤖 Привязать Telegram».
2. Откроется Telegram → жми «Запустить». Бот напишет «✅ Готово».
3. В кабинете через 5-10 секунд карточка изменится на «✅ Telegram подключён».
4. Открой ЛС с учителем (или попроси Ольгу написать) → должно прилететь уведомление в Telegram с кнопкой «Открыть».

## Шаг 6. Сменить токен бота (после теста!)

Токен бота засветился в чате с AI. Когда убедишься что всё работает:

1. Telegram → @BotFather → `/revoke` → выбрать @ZRMoveBot → подтвердить.
2. Получить новый токен.
3. Обновить `TELEGRAM_BOT_TOKEN` в Supabase Secrets.
4. **Перерегистрировать webhook** командой из шага 4, подставив новый токен в URL.

---

## Что будет в следующих заходах

- Уведомление о проверенном сочинении (триггер во фронте после `essay.status = done`)
- Уведомление учителю о новом сочинении на проверку
- Уведомление об открытом дне интенсива
- Напоминание за час до вебинара (через `pg_cron` в Supabase)
- Настройки уведомлений в профиле (вкл/выкл по типам)
