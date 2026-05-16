---
name: Supabase /auth/v1 заблокирован в РФ
description: У провайдеров в РФ endpoint /auth/v1/* Supabase отдаёт таймауты — sb.auth.setSession() и sb.auth.getUser() висят. /rest/v1/ при этом работает.
type: project
originSessionId: 98f5908c-eea0-4c00-9cdc-b159ec2eada1
---
В index.html Ольгиной платформы (parashut-26.github.io/ege-intensiv) endpoint `/auth/v1/user` и `/auth/v1/token` Supabase у российских провайдеров стабильно отдаёт таймауты — `sb.auth.setSession()` и `sb.auth.getUser()` висят бесконечно. При этом `/rest/v1/profiles` проходит нормально, и письма с magic link приходят (отправляются со стороны Supabase, не из браузера).

**Why:** Это не ошибка кода — это сетевая фильтрация со стороны провайдера/Роскомнадзора конкретно auth-эндпоинта.

**How to apply:** В коде уже реализован обход — функция `loadProfileDirect()` в index.html (~строка 384):
1. Декодирует JWT из URL hash прямо в браузере (`decodeJwtPayload`).
2. Берёт user_id из payload.sub, email из payload.email.
3. Делает прямой `fetch` к `/rest/v1/profiles?id=eq.<userId>` с заголовком `Authorization: Bearer <access_token>`.
4. Если профиля нет — создаёт через REST POST.
5. Сохраняет сессию в localStorage в формате `sb-<projectRef>-auth-token`, чтобы `sb.from()` потом работал.

Если в будущем что-то ломается на входе — НЕ возвращать прежний путь через `sb.auth.setSession`, останется только этот REST-обход. Альтернатива на длинную дистанцию: платный план Supabase ($25/мес) с собственным доменом для auth (например, auth.zebrus.ru), который не фильтруется.
