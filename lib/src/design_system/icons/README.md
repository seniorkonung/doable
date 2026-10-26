# Иконки дизайна

Источник: макеты `context/doable-design/design/*.dc.html`, экспорт холста
«Doable · Design» версии `1791926592-bd5b` от **14.10.2026**.
Ползунки сортировки, стрелки порядка и шеврон вниз — из обновлённого макета
`ActionPicker.dc.html` от **25.10.2026**.
Селектор строки и направления сортировки — из `ActionPicker.dc.html` от
**26.10.2026**; те же значки `selector`, `sort-asc` и `sort-desc` описаны в
дизайн-системе `context/doable-design-system/`.
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
| [close.svg](assets/close.svg) | `ActionPicker.dc.html` | `header` → ссылка `Main.dc.html` с `cancelLabel`, SVG; тот же крестик у кнопки `cancel` |
| [filter.svg](assets/filter.svg) | `ActionPicker.dc.html` | `section[aria-label="Filters"]` → кнопка `openFilter`, SVG |
| [bolt.svg](assets/bolt.svg) | `ActionPicker.dc.html` | Строка `rows` → метка `row.isAct`, SVG |
| [arrow_up_right.svg](assets/arrow_up_right.svg) | `ActionPicker.dc.html` | Строка `rows` → кнопка `row.info`, SVG |
| [archive.svg](assets/archive.svg) | `ActionPicker.dc.html` | Строка `rows` → метка `row.archived`, SVG |
| [sliders.svg](assets/sliders.svg) | `ActionPicker.dc.html` | Кнопка `openSheet` → пилюля с `sortSummary`, SVG |
| [arrow_down.svg](assets/arrow_down.svg) | `ActionPicker.dc.html` | Лист «Show and sort» → группа «Order» → кнопка `dirA.pick`, SVG |
| [arrow_up.svg](assets/arrow_up.svg) | `ActionPicker.dc.html` | Лист «Show and sort» → группа «Order» → кнопка `dirB.pick`, SVG |
| [chevron_down.svg](assets/chevron_down.svg) | `ActionPicker.dc.html` | `header` → кнопка `openReminder`, завершающий SVG |
| [selector.svg](assets/selector.svg) | `ActionPicker.dc.html` | Лист «Show and sort» → строка «Type» с `mType.toggle`, завершающий SVG; тот же значок у строки «Sort by» |
| [sort_desc.svg](assets/sort_desc.svg) | `ActionPicker.dc.html` | Лист «Show and sort» → кнопка `dirFlip.pick`, SVG при `dirFlip.down` |
| [sort_asc.svg](assets/sort_asc.svg) | `ActionPicker.dc.html` | Лист «Show and sort» → кнопка `dirFlip.pick`, SVG при `dirFlip.up` |

Мини-значки имеют линию 2 при размере 14, значки меню — линию 1,75 при размере 22.
Календарь навигации содержит отметки дней, календарь меню и мини-значок — нет.
Эти варианты хранятся отдельно.
