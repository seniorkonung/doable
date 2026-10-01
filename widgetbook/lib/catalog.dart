import 'package:widgetbook/widgetbook.dart';

import 'sandbox/intention_screen.dart';

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
    name: 'Песочница',
    children: [
      WidgetbookComponent(
        name: 'Экран намерения',
        useCases: [
          WidgetbookUseCase(
            name: 'По умолчанию',
            builder: (context) => const IntentionScreen(),
          ),
        ],
      ),
    ],
  ),
];
