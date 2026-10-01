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
      // Виджеты приложения берут системные строки из его локализации.
      LocalizationAddon(
        locales: const [Locale('ru'), Locale('en')],
        localizationsDelegates: AppLocalizations.localizationsDelegates,
      ),
    ],
  );
}
