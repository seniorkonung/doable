import 'package:doable/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:widgetbook/widgetbook.dart';

import 'catalog.dart';

/// Корневой виджет каталога.
final class WidgetbookApp extends StatelessWidget {
  const WidgetbookApp({super.key});

  @override
  Widget build(BuildContext context) => Widgetbook.material(
    directories: buildCatalog(),
    addons: [
      // Приложение свою тему не задаёт и рисуется темой Material по умолчанию.
      // Дополнение красит фон примера её цветом: без него фон берётся из темы
      // самого Widgetbook, которая следует тёмному режиму устройства.
      MaterialThemeAddon(
        themes: [WidgetbookTheme(name: 'Приложение', data: ThemeData())],
      ),
      // Виджеты приложения берут системные строки из его локализации.
      LocalizationAddon(
        locales: const [Locale('ru'), Locale('en')],
        localizationsDelegates: AppLocalizations.localizationsDelegates,
      ),
    ],
  );
}
