# Подключение Telegram-уведомлений — пошаговая инструкция

Готовые файлы уже в репо:
- `sql/add_telegram_integration.sql` — миграция БД
- `supabase/functions/tg-webhook/index.ts` — обработчик входящих от Telegram
- `supabase/functions/tg-send/index.ts` — универсальная отправка уведомлений
- Кнопка «🤖 Привязать Telegram» во фронте — уже в `index.html`
- Триггер «новое сообщение в ЛС» → TG — уже в `index.html`

Бот: **@ZRMoveBot**. Токен берётся у @BotFather в Telegram — нигде в этом репозитории не хранится.

> ⚠ Никогда не пиши токен в файл, коммит или сообщение чата — GitHub
> Secret Scanning ловит такие токены и принудительно их инвалидирует.
> Токен живёт только в **Supabase Edge Function secrets** и в одной
> локальной curl-команде, которую ты выполняешь руками.

---

## Шаг 1. Прогнать SQL-миграцию

Открой Supabase Dashboard → SQL Editor → New Query. Скопируй содержимое файла `sql/add_telegram_integration.sql` и нажми Run. В конце должно вывести 4 строки с новыми колонками — это проверка.

## Шаг 2. Добавить секреты в Supabase

Supabase Dashboard → Project Settings → **Edge Functions** → **Manage secrets** → New secret.

Добавь **три** секрета:

| Имя | Значение |
|---|---|
| `TELEGRAM_BOT_TOKEN` | свежий токен от @BotFather (формат `1234567890:AAH…`) |
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

В Терминале одной строкой. Сначала положи токен во временную переменную окружения (живёт только в текущей сессии Терминала — не в файлах):

```bash
read -s TG_TOKEN && export TG_TOKEN
# ↑ вставь токен от BotFather, нажми Enter (символы НЕ отображаются — это норма)
```

Регистрация:

```bash
curl -s -X POST "https://api.telegram.org/bot$TG_TOKEN/setWebhook" \
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
curl -s "https://api.telegram.org/bot$TG_TOKEN/getWebhookInfo"
```

Должно показать `url: https://hyczawwuehrqsqqosgub...` и `pending_update_count: 0`.

## Шаг 5. Тест

1. Зайди как ученик на zebrus.online → вкладка «Профиль» → нажми «🤖 Привязать Telegram».
2. Откроется Telegram → жми «Запустить». Бот напишет «✅ Готово».
3. В кабинете через 5-10 секунд карточка изменится на «✅ Telegram подключён».
4. Открой ЛС с учителем (или попроси Ольгу написать) → должно прилететь уведомление в Telegram с кнопкой «Открыть».

## Шаг 6. Безопасность токена

Токен живёт **только в Supabase Edge Function secrets**. Никогда не
коммить его в репо, не пиши в этом файле, не вставляй в чаты с AI.
GitHub Secret Scanning ловит формат `\d+:[A-Za-z0-9_-]{30,}` и
автоматически инвалидирует токен — придётся ротировать.

Если случилось — Telegram → @BotFather → `/revoke` → новый токен →
обновить `TELEGRAM_BOT_TOKEN` в Supabase Secrets → перерегистрировать
webhook командой из шага 4 (с новым токеном в `$TG_TOKEN`).

---

## Что будет в следующих заходах

- Уведомление о проверенном сочинении (триггер во фронте после `essay.status = done`)
- Уведомление учителю о новом сочинении на проверку
- Уведомление об открытом дне интенсива
- Напоминание за час до вебинара (через `pg_cron` в Supabase)
- Настройки уведомлений в профиле (вкл/выкл по типам)
