---
name: Git lock-файлы — снимать перед коммитом ПРАВИЛЬНЫМИ командами
description: В репе ЗебРус sandbox оставляет .git/*.lock; убирать пре-эмптивно только .git/index.lock и .git/HEAD.lock; НЕ использовать find -delete
type: feedback
---
В репе `/Users/olgakh/Documents/Claude/Projects/Приложение` каждый `git commit/add` из bash-sandbox оставляет за собой `.git/index.lock` и/или `.git/HEAD.lock`. Удалить их потом из-под sandbox-процесса нельзя («Operation not permitted») — даже от того же пользователя. Файл блокирует следующий коммит → Ольге приходится снимать вручную.

**Why:** Sandbox-маунт `/sessions/.../mnt/Приложение` имеет ограничения на удаление файлов, созданных в .git. Каждый промах с коммитом превращается в «попросить Ольгу `rm` → ждать → пробовать снова».

**How to apply:** ВСЕГДА делать коммит цепочкой команд через `&&`, начиная с `rm -f .git/index.lock .git/HEAD.lock`. Шаблон:

```bash
cd ~/Documents/Claude/Projects/Приложение && \
rm -f .git/index.lock .git/HEAD.lock 2>/dev/null; \
git add <files> && \
git commit -m "..." && \
git push
```

`2>/dev/null` глушит «Operation not permitted» от rm — это норма.

## КРИТИЧНО: НЕ предлагать Ольге `find .git -name "*.lock" -delete`

2026-05-20: я однажды предложила `find .git -name "*.lock" -delete` чтобы убрать «все локи разом». В её сетапе эта команда **снесла ссылку на main** (`refs/heads/main` или близкий служебный файл), репозиторий пришёл в состояние «your current branch 'main' does not have any commits yet», все три моих коммита того дня остались только на GitHub, локально ветка стала пустой.

**Recovery (если опять случится):**
```bash
cd ~/Documents/Claude/Projects/Приложение
cp index.html ~/Desktop/index_backup.html   # бэкап рабочих правок!
git fetch origin
git update-ref refs/heads/main refs/remotes/origin/main
git reset --mixed
git log --oneline -3   # должны вернуться коммиты с GitHub
git status             # modified: index.html и др. — рабочие правки на месте
git add -A && git commit -m "..." && git push
```

**Правило:** удалять можно ТОЛЬКО `.git/index.lock` и `.git/HEAD.lock` по имени. Никаких `find -delete`. Никаких `*.lock`. Никаких `refs/heads/*.lock` (хотя они существуют) — оставлять в покое.

Push по-прежнему делает Ольга вручную.
