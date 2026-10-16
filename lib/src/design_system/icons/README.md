# Иконки дизайна

Источник: `context/doable-design/design/Main.dc.html`, экспорт холста
«Doable · Design» версии `1791926592-bd5b` от **14.10.2026**.
Приватный экспорт нужен для сверки при обновлении; SVG в `assets/` самостоятельны.

Сохранены размеры, `viewBox`, геометрия, заливки, `fill-rule`, ширина, окончания
и соединения линий, а также `currentColor`. Добавлено пространство имён SVG;
удалены `aria-hidden` и встроенные стили HTML: доступность, размещение и цвет
задаёт компонент интерфейса.

| Ресурс | Блок в `Main.dc.html` |
| --- | --- |
| [home.svg](assets/home.svg) | `nav[aria-label="Sections"]` → `nav.home.away` |
| [home_filled.svg](assets/home_filled.svg) | `nav[aria-label="Sections"]` → `nav.home.up` |
| [calendar_days.svg](assets/calendar_days.svg) | `nav[aria-label="Sections"]` → `nav.choices.away` |
| [calendar_days_filled.svg](assets/calendar_days_filled.svg) | `nav[aria-label="Sections"]` → `nav.choices.here` |
| [graph.svg](assets/graph.svg) | `nav[aria-label="Sections"]` → `nav.graph.away` |
| [graph_filled.svg](assets/graph_filled.svg) | `nav[aria-label="Sections"]` → `nav.graph.up` |
| [plus.svg](assets/plus.svg) | Кнопка `addTap`, первый SVG |
| [intention.svg](assets/intention.svg) | `pinSheet` → кнопка `pick.intention.go`, ведущий SVG |
| [relation.svg](assets/relation.svg) | `pinSheet` → кнопка `pick.relation.go`, ведущий SVG |
| [calendar.svg](assets/calendar.svg) | `pinSheet` → кнопка `pick.choice.go`, ведущий SVG |
| [intention_mini.svg](assets/intention_mini.svg) | Кнопка `addTap` → `isIntention` |
| [relation_mini.svg](assets/relation_mini.svg) | Кнопка `addTap` → `isRelation` |
| [calendar_mini.svg](assets/calendar_mini.svg) | Кнопка `addTap` → `isChoice` |
| [from_intention.svg](assets/from_intention.svg) | `choiceSheet` → ссылка `IntentionPicker.dc.html`, ведущий SVG |
| [from_action.svg](assets/from_action.svg) | `choiceSheet` → ссылка `ActionPicker.dc.html`, ведущий SVG |
| [check.svg](assets/check.svg) | `pinSheet` → `pick.intention.on`; та же галочка у `pick.relation.on` и `pick.choice.on` |
| [chevron_right.svg](assets/chevron_right.svg) | `choiceSheet` → ссылка `IntentionPicker.dc.html`, завершающий SVG; тот же шеврон у `ActionPicker.dc.html` |

Мини-значки имеют линию 2 при размере 14, значки меню — линию 1,75 при размере 22.
Календарь навигации содержит отметки дней, календарь меню и мини-значок — нет.
Эти варианты хранятся отдельно.
