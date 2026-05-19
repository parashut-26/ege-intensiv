---
name: Telegram-бот оплат работает в проде + TODO Email-канал
description: tg-payment-webhook задеплоен, парсит формат tb.ru, UI на сводке и вкладке Оплаты готов. Email-резерв через Albato — после интенсива.
type: project
originSessionId: bc3cfd8d-1cc1-4068-a4e4-49170c0cb170
---
**2026-05-16: бот в проде.** `@ZebrusPayBot` (BotFather), токен `TG_PAY_BOT_TOKEN` в Supabase Secrets, webhook установлен. Ольга вручную пересылает уведомления Т-банка (формат с `tb.ru`: «Имя Фамилия / Почта / Контактный телефон / Номер операции / Описание заказа / Итого») → бот:
- Парсит: amount, payerName, payerEmail, payerPhone, operationId, orderDescription.
- Ищет ученика по 3 каналам: email → корень фамилии (Халиулина→Халиулин) → имена с заглавной в описании заказа.
- Дедуп по `operation_id` (UNIQUE index).
- Создаёт строку в `payment_suggestions` (status='pending') + отвечает учителю в Telegram.

**В кабинете учителя готово:**
- Жёлтая карточка «🤖 N новых поступлений» на Сводке.
- Вкладка «💰 Оплаты»: плашки по периодам, фильтр по ученику, ручное добавление, CSV-экспорт, edit/delete.
- В карточке ученика — секция «💰 История оплат» (только учитель, у куратора скрыто).
- В кабинете ученика (Достижения) — «💰 История моих оплат» только свои (RLS).

**SQL миграции (уже прогнаны):**
- `add_payment_suggestions.sql` — таблица
- `add_payment_suggestions_v2.sql` — email/phone/operation_id/order_description + UNIQUE на operation_id

**TODO: Email-канал как резерв (после 4 июня).**
- Edge Function `email-payment-webhook`.
- Albato: Яндекс.Почта → POST на webhook.
- Парсер общий с tg-payment-webhook (формат tb.ru одинаков и в письме, и в Telegram).
- Дедуп через тот же operation_id — если придёт и по Telegram, и по email, в кабинете будет один suggestion.

**Почему не Telegram→Telegram авто-пересылка:** Telegram запрещает ботам читать сообщения от других ботов (платформенное правило). Userbot — нарушение TOS + нужен 24/7 сервер.

**Why:** Резервирование канала на случай падения Telegram у Т-банка или RKN. Не для замены ручной пересылки (3 сек/платёж — приемлемо), а как страховка.

**How to apply:** После 4 июня. ~1 час: Edge Function + регистрация в Albato + связка. С Ольгой пошагово через скрины, как было с Telegram-ботом.
