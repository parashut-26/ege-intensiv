# Web Push уведомления — пошаговая настройка

Файлы уже в репо:
- `sql/add_push_subscriptions.sql` — таблица подписок + RLS
- `sw.js` — Service Worker (в корне домена)
- `supabase/functions/push-send/index.ts` — отправка пушей
- В `index.html` всё подключено: helpers, кнопка «🔔 Включить» в карточке

Нужно сделать **5 шагов**.

---

## Шаг 1. Сгенерировать VAPID-ключи

VAPID — это пара ключей (публичный + приватный), которой сервер «подписывает» пуши. Делаются один раз навсегда.

В Терминале:

```bash
npx --yes web-push generate-vapid-keys
```

Выведет что-то вида:

```
Public Key:
BFh3KZNz_…длинная строка из base64…
Private Key:
gPMrL2yT…другая длинная строка…
```

Запиши обе. Public — в код, Private — в секреты Supabase.

---

## Шаг 2. Вставить PUBLIC ключ в `index.html`

Открой файл `index.html`, найди строку:

```js
const VAPID_PUBLIC_KEY = 'PASTE_YOUR_VAPID_PUBLIC_KEY_HERE';
```

Замени значение на свой публичный ключ. Сохрани.

---

## Шаг 3. Добавить PRIVATE ключ в Supabase Secrets

1. Supabase → **Project Settings → Edge Functions → Manage secrets** → New secret
2. **Name:** `VAPID_PRIVATE_KEY`, **Value:** твой приватный ключ → Save
3. Ещё один: **Name:** `VAPID_PUBLIC_KEY`, **Value:** тот же публичный → Save
4. Ещё один: **Name:** `VAPID_SUBJECT`, **Value:** `mailto:[email protected]` (или твой реальный email) → Save

Должно стать **6 секретов** всего:
`TELEGRAM_BOT_TOKEN`, `TELEGRAM_WEBHOOK_SECRET`, `TG_CRON_SECRET`,
`VAPID_PUBLIC_KEY`, `VAPID_PRIVATE_KEY`, `VAPID_SUBJECT`.

---

## Шаг 4. Прогнать SQL и залить функцию

### SQL

Supabase → SQL Editor → New query → скопируй содержимое
`sql/add_push_subscriptions.sql` → Run.

### Edge Function `push-send`

1. Supabase → Edge Functions → **Deploy a new function → Via Editor**
2. **Name:** `push-send`
3. **Verify JWT** — **выключи** (как у `tg-send` после фикса)
4. Удали дефолтный код
5. На компе открой `/Users/olgakh/Documents/Claude/Projects/Приложение/supabase/functions/push-send/index.ts` → TextEdit → Cmd+A → Cmd+C
6. Вставь в Code → **Deploy**

---

## Шаг 5. Push фронта + Service Worker

```bash
cd "/Users/olgakh/Documents/Claude/Projects/Приложение" && \
rm -f .git/index.lock .git/HEAD.lock && \
git add index.html sw.js sql/add_push_subscriptions.sql sql/add_chat_attachments.sql supabase/functions/push-send/index.ts WEBPUSH_SETUP.md && \
git commit -m "Голосовое+фото в чате + Web Push с VAPID" && \
git push
```

После push **подожди 1 минуту** — GitHub Pages обновит файлы, включая `sw.js`.

---

## Тест

1. На zebrus.online Cmd+Shift+R
2. Зайди как ученик → Профиль (или как учитель → Сводка) — должна появиться **новая карточка «🔔 Push-уведомления в браузере»**
3. Жми **«🔔 Включить»**
4. Браузер спросит разрешение → **«Разрешить»**
5. Карточка изменится на «✅ Push в этом браузере включён»
6. Тест: попроси кого-то написать тебе в ЛС → должно прийти **одновременно в Telegram И в браузере**

Если карточка не появилась — проверь что строка `VAPID_PUBLIC_KEY` в `index.html` НЕ равна `PASTE_YOUR_VAPID_PUBLIC_KEY_HERE`. Кэш браузера → Cmd+Shift+R.

---

## Где можно не приходить

- **iOS Safari**: Web Push поддерживается **только** для PWA, добавленных на главный экран (iOS 16.4+). Если ученик открывает zebrus.online просто в Safari — пуш не придёт. Решение: добавить иконку на главный экран (через «Поделиться» → «На экран Домой»). Тогда работает.
- **Старые Chrome (<50), старые Firefox** — не поддерживают.
- **Браузер закрыт совсем** — пуш доставится, когда юзер откроет браузер заново.

Telegram остаётся надёжнее iOS — поэтому держим оба канала.
