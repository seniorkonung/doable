import 'package:doable/src/daily_choice/presentation/catalog/daily_choice_calendar_day_marks_view_model.dart';
import 'package:doable/src/daily_choice/presentation/catalog/daily_choice_catalog_view_model.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Провайдер единственного уже открытого каталога в страничной проверке.
/// Поиск не создаёт корневой экземпляр до первого построения страницы.
DailyChoiceCatalogViewModelProvider openedDailyChoiceCatalogProvider(
  ProviderContainer container,
) => container
    .allProviders(family: dailyChoiceCatalogViewModelProvider)
    .map((reference) => reference.provider)
    .whereType<DailyChoiceCatalogViewModelProvider>()
    .single;

/// Отметки того же экземпляра, что и уже открытый каталог.
DailyChoiceCalendarDayMarksViewModelProvider openedDailyChoiceDayMarksProvider(
  ProviderContainer container,
) => dailyChoiceCalendarDayMarksViewModelProvider(
  container.read(openedDailyChoiceCatalogProvider(container).notifier).instance,
);
