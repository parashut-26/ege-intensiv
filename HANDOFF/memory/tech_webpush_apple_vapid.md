---
name: Web Push на iOS — VAPID_SUBJECT должен быть реальной почтой
description: Apple Push Service возвращает 403 если в VAPID subject стоит плейсхолдер email вроде [email protected]
type: project
originSessionId: 78f19cb3-178e-41ff-b4b9-2077b8ef4782
---
В Supabase Edge Function `push-send` секрет `VAPID_SUBJECT` обязан быть реальной рабочей mailto:- или https:-ссылкой. Apple Push Service для web (`web.push.apple.com`) валидирует её и при подделке возвращает 403 «Received unexpected response code», из-за чего подписка считается мёртвой и удаляется. Google FCM (`fcm.googleapis.com`) на это не смотрит — потому Chrome/Mac работали даже с фейковым subject, а iPhone — нет.

**Why:** Apple требует, чтобы оператор сайта был контактным. Это часть их анти-спам политики для Web Push.

**How to apply:** При настройке Web Push на новом проекте/домене обязательно установить `VAPID_SUBJECT = mailto:<реальная_почта_оператора>`. Текущее значение для ZebRus = `mailto:xxx154xxx153@gmail.com`. При смене e-mail оператора — обновить секрет и передеплоить `push-send`.

Также в `push-send/index.ts` уже стоит автоудаление подписки на 403 от Apple endpoint — этот fallback оставляем, он защитит при будущих мертворождённых подписках (например когда iOS Safari использовался без PWA).
