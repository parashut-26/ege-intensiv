---
name: WYSIWYG-редакторы постов и теории
description: contenteditable+execCommand в постах «Разогрев» и теории заданий; сохраняется HTML, рендер у ученика через innerHTML
type: project
---

**2026-05-20:** Переписала редактор постов «Разогрев» и редактор теории заданий с textarea+markdown на **contenteditable** div + `document.execCommand`. Текст сразу становится жирным/цветным при клике кнопки — без `**`, `<span>` и прочей разметки.

## Где это в коде
- **Посты «Разогрев»** — `renderAddBlockForm` (вокруг строки 19286): `bodyEditor` (contenteditable div) + `bodyTextarea` (прокси `{ get value, set value, focus }` для совместимости со старым кодом, который читает `bodyTextarea.value`).
- **Теория заданий** — `modalEditTheory` (вокруг строки 16912): `theoryEditor` (contenteditable div) + `ta` (прокси).

## Toolbar (одинаковый в обоих)
Ж / К / П / маркер / цвета (красный/синий/зелёный) / ⨯ removeFormat / H1 / H2 / ¶ / списки / линия / 🔗 ссылка / 👁 превью.

Каждая кнопка делает `_postExec(cmd, val)` или `_theoryExec(cmd, val)` — это thin-обёртка над `document.execCommand`. Cmd/Ctrl+B/I/U — keyboard handler с preventDefault + execCommand.

## Рендер у ученика — innerHTML, не textNode
**ВАЖНО:** в `renderWarmupBlockStudent` и `renderWarmupBlockTeacher` (вокруг строк 19618 и 19219) `b.body` рендерится через `innerHTML`, если в нём есть HTML-теги. Иначе — старый markdown через `marked.parse`. Иначе — plain-text с `whiteSpace: pre-wrap`. Детект через regex: `/<\/?(b|i|u|mark|span|h1|h2|h3|h4|ul|ol|li|br|hr|p|div|strong|em|a|img|font)[\s>\/]/i`.

Если забыть этот шаг — у учителя в редакторе всё красиво, а у ученика в посте видны сырые `<mark>текст</mark>` теги. Один раз уже так попалось 2026-05-20.

## Грабли, на которые я уже наступила

1. **`[object Object]` вместо редактора:** в `card.append(...)` нельзя передавать `ta` (proxy-объект) — только `theoryEditor` (настоящий div). Прокси `ta` существует только для совместимости со старым кодом, который читает `ta.value`.

2. **Картинки в теории:** старая логика вставляла markdown-плейсхолдер `![Загружаю_]()` — в contenteditable это не работает, появляется literal text. Переписала на DOM-плейсхолдер `<div data-loading-id="...">⏳ Загружаю</div>`, который заменяется на `<img>` после upload через `replaceChild`.

3. **Paste из Word/Notion:** обязательно `e.preventDefault()` + `document.execCommand('insertText', false, plainText)` — иначе влетят чужие стили и `<style>` блоки.

## Why
Ольга сравнила с редактором постов: «нельзя сделать, чтобы текст сразу становился цветным, жирным?». Привычка к Word/Telegram-разметке гораздо ближе, чем markdown-маркеры. Один раз обучить execCommand-pattern — и весь UI становится единообразным.

## How to apply
Если будут просить ещё один rich-text редактор где-то — используй тот же паттерн: contenteditable div + execCommand + proxy для старого кода + детект HTML в рендерере получателя. См. `todo_blocky_theory.md` — там этот же редактор будет переиспользован как text-блок.
