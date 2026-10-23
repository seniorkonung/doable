# Иконки дизайна

Источник: макеты `context/doable-design/design/*.dc.html`, экспорт холста
«Doable · Design» версии `1791926592-bd5b` от **14.10.2026**.
Приватный экспорт нужен для сверки при обновлении; SVG в `assets/` самостоятельны.

Сохранены размеры, `viewBox`, геометрия, заливки, `fill-rule`, ширина, окончания
и соединения линий, а также `currentColor`. Добавлено пространство имён SVG;
удалены `aria-hidden` и встроенные стили HTML: доступность, размещение и цвет
задаёт компонент интерфейса.

| Ресурс | Макет | Блок |
| --- | --- | --- |
| [home.svg](assets/home.svg) | `Main.dc.html` | `nav[aria-label="Sections"]` → `nav.home.away` |
| [home_filled.svg](assets/home_filled.svg) | `Main.dc.html` | `nav[aria-label="Sections"]` → `nav.home.up` |
| [calendar_days.svg](assets/calendar_days.svg) | `Main.dc.html` | `nav[aria-label="Sections"]` → `nav.choices.away` |
| [calendar_days_filled.svg](assets/calendar_days_filled.svg) | `Main.dc.html` | `nav[aria-label="Sections"]` → `nav.choices.here` |
| [graph.svg](assets/graph.svg) | `Main.dc.html` | `nav[aria-label="Sections"]` → `nav.graph.away` |
| [graph_filled.svg](assets/graph_filled.svg) | `Main.dc.html` | `nav[aria-label="Sections"]` → `nav.graph.up` |
| [plus.svg](assets/plus.svg) | `Main.dc.html` | Кнопка `addTap`, первый SVG |
| [plus_small.svg](assets/plus_small.svg) | `TagsPanel.dc.html` | Кнопка `openNewTag`, SVG |
| [intention.svg](assets/intention.svg) | `Main.dc.html` | `pinSheet` → кнопка `pick.intention.go`, ведущий SVG |
| [relation.svg](assets/relation.svg) | `Main.dc.html` | `pinSheet` → кнопка `pick.relation.go`, ведущий SVG |
| [calendar.svg](assets/calendar.svg) | `Main.dc.html` | `pinSheet` → кнопка `pick.choice.go`, ведущий SVG |
| [intention_mini.svg](assets/intention_mini.svg) | `Main.dc.html` | Кнопка `addTap` → `isIntention` |
| [relation_mini.svg](assets/relation_mini.svg) | `Main.dc.html` | Кнопка `addTap` → `isRelation` |
| [calendar_mini.svg](assets/calendar_mini.svg) | `Main.dc.html` | Кнопка `addTap` → `isChoice` |
| [from_intention.svg](assets/from_intention.svg) | `Main.dc.html` | `choiceSheet` → ссылка `IntentionPicker.dc.html`, ведущий SVG |
| [from_action.svg](assets/from_action.svg) | `Main.dc.html` | `choiceSheet` → ссылка `ActionPicker.dc.html`, ведущий SVG |
| [check.svg](assets/check.svg) | `Main.dc.html` | `pinSheet` → `pick.intention.on`; та же галочка у `pick.relation.on` и `pick.choice.on` |
| [exclude.svg](assets/exclude.svg) | `TagsPanel.dc.html` | Строка `rows` → `row.no`, SVG |
| [chevron_right.svg](assets/chevron_right.svg) | `Main.dc.html` | `choiceSheet` → ссылка `IntentionPicker.dc.html`, завершающий SVG; тот же шеврон у `ActionPicker.dc.html` |
| [chevron_down.svg](assets/chevron_down.svg) | `TagsPanel.dc.html` | Кнопка `toggleSize` в полном размере, SVG |
| [search.svg](assets/search.svg) | `TagsPanel.dc.html` | Поле поиска `tags-search`, ведущий SVG |
| [clear.svg](assets/clear.svg) | `TagsPanel.dc.html` | Кнопка `clearQ`, SVG |
| [grip.svg](assets/grip.svg) | `TagsPanel.dc.html` | Строка `rows` → кнопка `row.grab`, SVG |
| [edit.svg](assets/edit.svg) | `TagsPanel.dc.html` | Меню `menuOpen` → пункт `menuEdit`, SVG |
| [copy.svg](assets/copy.svg) | `TagsPanel.dc.html` | Меню `menuOpen` → пункт `menuDuplicate`, SVG |
| [delete.svg](assets/delete.svg) | `TagsPanel.dc.html` | Меню `menuOpen` → пункт `menuDelete`, SVG |
| [settings.svg](assets/settings.svg) | `Home.dc.html` | Ссылка `Settings.dc.html` |
| [export.svg](assets/export.svg) | `Settings.dc.html` | Кнопка `openExport`, ведущий SVG |
| [lock_open.svg](assets/lock_open.svg) | `Settings.dc.html` | `exportOpen` → предупреждение панели, SVG |
| [backups.svg](assets/backups.svg) | `Settings.dc.html` | Кнопка `openBackups`, ведущий SVG |
| [import.svg](assets/import.svg) | `Settings.dc.html` | Кнопка `pickFile`, ведущий SVG |
| [warning.svg](assets/warning.svg) | `Settings.dc.html` | Блок `failed` → предупреждение, SVG |

Мини-значки имеют линию 2 при размере 14, значки меню — линию 1,75 при размере 22.
Календарь навигации содержит отметки дней, календарь меню и мини-значок — нет.
Эти варианты хранятся отдельно.
