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
