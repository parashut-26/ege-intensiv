---
name: DONE — поддомен krashtest.zebrus.online для лендинга
description: Лендинг parashut-26.github.io/krash-test-2026/ привязан к krashtest.zebrus.online (DNS через Cloudflare)
type: project
originSessionId: 78f19cb3-178e-41ff-b4b9-2077b8ef4782
---
**2026-05-13: Сделано.** Лендинг доступен по `https://krashtest.zebrus.online`.

**Что было сделано:**
1. В Cloudflare DNS (DNS зоны `zebrus.online` управляются Cloudflare, не reg.ru): добавлен CNAME `krashtest` → `parashut-26.github.io`, Proxy: DNS only (без оранжевого облачка, иначе GitHub Pages не выдаст HTTPS).
2. В репозитории `parashut-26/krash-test-2026` → Settings → Pages → Custom domain = `krashtest.zebrus.online`. DNS check прошёл.
3. Let's Encrypt выпустил сертификат, «Enforce HTTPS» доступен.

**Важно:**
- Домен `zebrus.online` куплен у reg.ru, но **NS-серверы переключены на Cloudflare** (`???.ns.cloudflare.com`). Любые DNS-изменения делать в Cloudflare, не в reg.ru.
- Cloudflare прокси (оранжевое облако) для CNAME на GitHub Pages выключать — иначе TLS handshake сломается.

**Будущее:** Если Ольга решит уйти на российскую инфраструктуру (см. также todo по Yandex.Cloud) — DNS можно перенести обратно на reg.ru или на Yandex DNS. Пока Cloudflare работает.
