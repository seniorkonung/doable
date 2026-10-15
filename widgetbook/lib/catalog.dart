import 'package:widgetbook/widgetbook.dart';

import 'calendar/calendar_handle_use_cases.dart';
import 'calendar/calendar_header_use_cases.dart';
import 'calendar/day_heading_use_cases.dart';
import 'calendar/month_grid_day_use_cases.dart';
import 'calendar/period_picker_use_cases.dart';
import 'calendar/week_strip_day_use_cases.dart';
import 'foundations/colors_use_cases.dart';
import 'foundations/typography_use_cases.dart';
import 'intention/intention_summary_view_use_cases.dart';
import 'messages/notice_use_cases.dart';
import 'navigation/app_navigation_bar_use_cases.dart';

/// Строит дерево каталога.
///
/// Дерево описано вручную, без `widgetbook_generator`: генератор после сборки
/// отправляет телеметрию (https://docs.widgetbook.io/telemetry), а создаваемый
/// им файл — такой же список узлов из публичного API пакета
/// (https://pub.dev/documentation/widgetbook/3.25.0/widgetbook/WidgetbookComponent-class.html).
///
/// Узлы хранят ссылку на родителя, поэтому каждое обращение возвращает новое
/// дерево, а не общее изменяемое состояние.
List<WidgetbookNode> buildCatalog() => [
  WidgetbookFolder(
    name: 'Основы',
    children: [
      WidgetbookComponent(name: 'Цвета', useCases: colorsUseCases()),
      WidgetbookComponent(name: 'Типографика', useCases: typographyUseCases()),
    ],
  ),
  WidgetbookFolder(
    name: 'Календарь',
    children: [
      WidgetbookComponent(
        name: 'День недельной полосы',
        useCases: weekStripDayUseCases(),
      ),
      WidgetbookComponent(
        name: 'День месячной сетки',
        useCases: monthGridDayUseCases(),
      ),
      WidgetbookComponent(
        name: 'Шапка месяца',
        useCases: calendarHeaderUseCases(),
      ),
      WidgetbookComponent(
        name: 'Выбор года и месяца',
        useCases: periodPickerUseCases(),
      ),
      WidgetbookComponent(
        name: 'Ручка календаря',
        useCases: calendarHandleUseCases(),
      ),
      WidgetbookComponent(
        name: 'Заголовок дня',
        useCases: dayHeadingUseCases(),
      ),
    ],
  ),
  WidgetbookFolder(
    name: 'Сообщения',
    children: [
      WidgetbookComponent(
        name: 'Сообщение об отказе',
        useCases: noticeUseCases(),
      ),
    ],
  ),
  WidgetbookFolder(
    name: 'Навигация',
    children: [
      WidgetbookComponent(
        name: 'Панель основной навигации',
        useCases: appNavigationBarUseCases(),
      ),
    ],
  ),
  WidgetbookFolder(
    name: 'Намерения',
    children: [
      WidgetbookComponent(
        name: 'Строка намерения',
        useCases: intentionSummaryViewUseCases(),
      ),
    ],
  ),
];
