---
name: Дашборд ученика в Достижениях — зеркало карточки учителя
description: Сверху вкладки «Достижения» у ученика виден комментарий учителя, KPI, слабые темы, история попыток, пробники, оплаты, чемодан
type: project
originSessionId: bc3cfd8d-1cc1-4068-a4e4-49170c0cb170
---
**2026-05-16: внедрено.**

Функция `studentSelfDashboardCard()` в `viewStudentAchievements`. Показывается СВЕРХУ, перед «🐝 Как работают пчёлки».

**Что внутри:**
1. **💬 Комментарий учителя** — бирюзовая карточка, текст из `profiles.student_visible_comment`. Показывается только если поле заполнено.
2. **KPI grid** (4 карточки): всего попыток, средний балл, заданий охвачено, слабые темы.
3. **⚠ На что обратить внимание** — список тем с <70% (порог 1 попытка, не 2 — иначе во время интенсива пусто).
4. **📈 История моих попыток по заданиям** — collapsible `<details>`, по 26 заданиям, клик на плашку → modalAttemptDetail (тот же что у учителя).
5. **📋 Мои пробники** — collapsible, если есть `STATE.myVariantAttempts`.
6. **💰 История моих оплат** — collapsible, только свои по RLS (`pay_teacher` policy: `is_teacher() OR student_id = auth.uid()`).
7. **🧳 Чемодан без ручки** — реюз существующего `mistakeBankCard()`.

**Источник данных:**
- `MY_ATTEMPTS` (global) — все попытки ученика, загружается в `loadMyStats()` (там же где `MY_STATS.done/avg/streak`). Лимит 500.
- `PAYMENTS` — общий массив, фильтруется по `student_id === MY_PROFILE.id`.
- `STATE.myVariantAttempts` — кэш из viewStudentVariants.
- `MY_PROFILE.student_visible_comment` — приходит в `loadProfileDirect` через `select=*`.

**Связка с «комментарием учителя»:**
- Учитель пишет в `modalStudentDetail` → бирюзовая карточка «💬 Комментарий ученику» (отдельно от приватной «📝 Заметка учителя»).
- PATCH `/profiles?id=eq.<student_id>` → поле `student_visible_comment`.
- Ученик видит сразу при следующем входе.

**SQL миграция (уже прогнана):**
- `add_student_visible_comment.sql` — `ALTER TABLE profiles ADD COLUMN student_visible_comment TEXT`.

**Why:** Ольга хотела, чтобы ученик видел свою картину целиком (не только баллы, но и слабые темы, оплаты, индивидуальные комментарии учителя), в одном месте.

**How to apply:** Если меняется набор данных карточки учителя — параллельно обновлять и `studentSelfDashboardCard()`, чтобы зеркало не отставало. Если добавляются новые поля в profiles — добавлять в `loadStudentsFromDb` select и в `loadProfileDirect` (но там `select=*`).
