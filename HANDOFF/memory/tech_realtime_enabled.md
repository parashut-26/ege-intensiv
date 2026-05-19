---
name: Supabase Realtime включён на attempts и payment_suggestions
description: Учитель видит живые обновления Сводки, Аналитики и предложений оплат без ручного refresh
type: project
originSessionId: bc3cfd8d-1cc1-4068-a4e4-49170c0cb170
---
**2026-05-16: включено в проде.**

В Supabase в публикации `supabase_realtime` добавлены таблицы:
- `attempts` — для виджета «⚠️ Слабые места группы» на Сводке + таблицы «📋 Сводная: ученики × задания» в Аналитике.
- `payment_suggestions` — для жёлтой карточки «🤖 Новые поступления» на Сводке.

SQL который был прогнан:
```sql
ALTER PUBLICATION supabase_realtime ADD TABLE attempts;
ALTER PUBLICATION supabase_realtime ADD TABLE payment_suggestions;
```

**Архитектура (на фронте):**
- `startTeacherRealtime()` стартует ОДИН раз после логина, только для роли `teacher`.
- Два канала: `rt-attempts` и `rt-pay-sugg` (event: '*', schema: 'public').
- Дебаунс **2 секунды** через `_scheduleGroupStatsReload()` — если 5 учеников одновременно сохраняют, запрос пойдёт ОДИН.
- При событии attempts параллельно подгружаются `loadGroupStats()` + `loadReportAttempts({silent:true})`.
- Silent reload не сбрасывает данные в null — таблица не моргает «Загружаем…».
- В UI индикатор «🟢 live» появляется только если есть активные каналы.

**Why:** Во время интенсива ученики решают тренажёры параллельно. Без live-обновлений учитель не видит, что происходит, пока не нажмёт 🔄 или не перезагрузит вкладку.

**How to apply:** При работе с теми же таблицами на любом изменении схемы — не забывать что они в публикации. Если меняешь RLS — realtime тоже её соблюдает (учитель видит всех через `is_teacher() OR ...`).

**Если потребуется отключить:** убрать таблицу из публикации
```sql
ALTER PUBLICATION supabase_realtime DROP TABLE attempts;
ALTER PUBLICATION supabase_realtime DROP TABLE payment_suggestions;
```
Фронт сам обработает CHANNEL_ERROR и спрячет индикатор «🟢 live». Кнопка 🔄 продолжит работать.
