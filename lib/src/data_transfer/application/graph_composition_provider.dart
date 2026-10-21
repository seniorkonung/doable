import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'graph_composition.dart';

/// Источник состава графа для раздела «Данные».
///
/// Композиция приложения переопределяет провайдер репозиторием графа.
final graphCompositionSourceProvider = Provider<GraphCompositionSource>(
  (ref) => throw StateError(
    'Источник состава графа должен быть предоставлен композицией приложения.',
  ),
);

/// Состав графа, пока его показывает хотя бы один экран: экраны делят одно
/// наблюдение, а без них состав не перечитывается после каждой команды.
final graphCompositionProvider =
    StreamProvider.autoDispose<GraphCompositionRead>(
      (ref) => ref.watch(graphCompositionSourceProvider).watchComposition(),
    );
