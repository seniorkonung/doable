import 'package:widgetbook/widgetbook.dart';

import 'intention/intention_summary_view_use_cases.dart';
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
