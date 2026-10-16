import 'package:auto_route/auto_route.dart';
import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/src/app/routing/app_router.gr.dart';
import 'package:doable/src/design_system/doable_icon.dart';

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

  /// Корневая страница пункта — дочерний маршрут оболочки.
  ///
  /// Порядок вкладок оболочки следует порядку значений, поэтому индекс
  /// вкладки совпадает с индексом пункта и используется сборкой навигации.
  PageInfo get page => switch (this) {
    AppDestination.home => HomeRoute.page,
    AppDestination.dailyChoices => DailyChoiceCatalogRoute.page,
    AppDestination.intentionGraph => IntentionCatalogRoute.page,
  };

  /// Контурный значок невыбранного пункта.
  DoableIconData get icon => switch (this) {
    AppDestination.home => DoableIconData.home,
    AppDestination.dailyChoices => DoableIconData.calendarDays,
    // Центральный узел соединён с внешними во все стороны: значок изображает
    // граф, а не иерархию уровней.
    AppDestination.intentionGraph => DoableIconData.graph,
  };

  /// Залитый значок выбранного пункта: выбор различим не только цветом.
  DoableIconData get selectedIcon => switch (this) {
    AppDestination.home => DoableIconData.homeFilled,
    AppDestination.dailyChoices => DoableIconData.calendarDaysFilled,
    AppDestination.intentionGraph => DoableIconData.graphFilled,
  };
}
