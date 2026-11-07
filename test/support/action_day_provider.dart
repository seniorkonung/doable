import 'package:doable/src/action/presentation/day/action_day_marks_view_model.dart';
import 'package:doable/src/action/presentation/day/action_day_view_model.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Провайдер единственного уже открытого каталога в страничной проверке.
/// Поиск не создаёт корневой экземпляр до первого построения страницы.
ActionDayViewModelProvider openedActionDayProvider(
  ProviderContainer container,
) => container
    .allProviders(family: actionDayViewModelProvider)
    .map((reference) => reference.provider)
    .whereType<ActionDayViewModelProvider>()
    .single;

/// Отметки того же экземпляра, что и уже открытый каталог.
ActionDayMarksViewModelProvider openedActionDayMarksProvider(
  ProviderContainer container,
) => actionDayMarksViewModelProvider(
  container.read(openedActionDayProvider(container).notifier).instance,
);
