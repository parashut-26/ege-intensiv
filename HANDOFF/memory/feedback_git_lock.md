---
name: Git lock-файлы — снимать перед каждым коммитом одной командой
description: В репе ЗебРус sandbox оставляет .git/*.lock, которые потом не удалить из bash; убирать пре-эмптивно
type: feedback
originSessionId: 27e11199-e03b-4c5c-8a23-22d4774276c4
---
В репе `/Users/olgakh/Documents/Claude/Projects/Приложение` каждый `git commit/add` из bash-sandbox оставляет за собой `.git/index.lock` и/или `.git/HEAD.lock`. Удалить их потом из-под sandbox-процесса нельзя («Operation not permitted») — даже от того же пользователя. Файл блокирует следующий коммит → Ольге приходится снимать вручную.

**Why:** Sandbox-маунт `/sessions/.../mnt/Приложение` имеет ограничения на удаление файлов, созданных в .git. Каждый промах с коммитом превращается в «попросить Ольгу `rm` → ждать → пробовать снова».

**How to apply:** ВСЕГДА делать коммит цепочкой команд через `&&`, начиная с `rm -f .git/index.lock .git/HEAD.lock`. Шаблон:

```bash
cd /sessions/sleepy-gallant-albattani/mnt/Приложение && \
rm -f .git/index.lock .git/HEAD.lock 2>/dev/null; \
git add <files> && \
git commit -m "..."
```

`2>/dev/null` глушит «Operation not permitted» от rm — это норма, если файла нет или sandbox его не отдаёт. Сам `git commit` после этого проходит, потому что в момент start-а нового процесса git проверяет файл и пересоздаёт его. Если файл существует на момент проверки — git упадёт; если был только что удалён — пройдёт.

Если несмотря на это упёрлись в lock — отдать Ольге одну chained-команду с `cd && rm -f && git add && git commit && git push`, чтобы она прокрутила всё одним копипастом в Терминале.

Push по-прежнему делает Ольга вручную (workflow из брифа).
