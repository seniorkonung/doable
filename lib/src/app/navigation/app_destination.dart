import 'package:doable/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

/// Пункт основной навигации.
///
/// Порядок значений — порядок пунктов панели слева направо. Название, значки
/// и остальные свойства пункта выводятся из значения исчерпывающими `switch`,
/// поэтому новый пункт нельзя добавить, не определив их.
enum AppDestination {
  home,
  dailyChoices,
  intentionGraph;

  /// Название пункта, общее для панели и заголовка его корневой страницы.
  String title(AppLocalizations localizations) => switch (this) {
    AppDestination.home => localizations.appDestinationHome,
    AppDestination.dailyChoices => localizations.appDestinationDailyChoices,
    AppDestination.intentionGraph => localizations.appDestinationIntentionGraph,
  };

  /// Контурный значок невыбранного пункта.
  IconData get icon => switch (this) {
    AppDestination.home => Icons.home_outlined,
    AppDestination.dailyChoices => Icons.calendar_month_outlined,
    // Центральный узел соединён с внешними во все стороны: значок изображает
    // граф, а не иерархию уровней.
    AppDestination.intentionGraph => Icons.hub_outlined,
  };

  /// Залитый значок выбранного пункта: выбор различим не только цветом.
  IconData get selectedIcon => switch (this) {
    AppDestination.home => Icons.home,
    AppDestination.dailyChoices => Icons.calendar_month,
    AppDestination.intentionGraph => Icons.hub,
  };
}
