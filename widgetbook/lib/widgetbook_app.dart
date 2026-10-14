import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/src/design_system/doable_theme.dart';
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
      // Примеры и их фон используют темы из модуля основ оформления.
      // https://docs.widgetbook.io/addons/theme-addon#material-theme
      MaterialThemeAddon(
        themes: [
          WidgetbookTheme(name: 'Светлая', data: doableTheme(Brightness.light)),
          WidgetbookTheme(name: 'Тёмная', data: doableTheme(Brightness.dark)),
        ],
      ),
      // Поверхность под примерами сохраняет эффекты нажатия ListTile
      // над фоном дополнения темы.
      // https://docs.widgetbook.io/addons/builder-addon
      BuilderAddon(
        name: 'Поверхность Material',
        builder: (context, child) =>
            Material(type: MaterialType.transparency, child: child),
      ),
      // Виджеты приложения берут системные строки из его локализации.
      LocalizationAddon(
        locales: const [Locale('ru'), Locale('en')],
        localizationsDelegates: AppLocalizations.localizationsDelegates,
      ),
      // Необязательный ручной выбор размера текста для просмотра примеров.
      TextScaleAddon(min: 1, max: 2.5),
    ],
  );
}
