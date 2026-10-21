import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../graph/application/graph_change.dart';
import '../../graph/application/graph_command_coordinator.dart';

part 'graph_generation.g.dart';

/// Поколение графа: корневые страницы одного поколения открыты над одним и
/// тем же графом, а подтверждённая замена графа начинает новое поколение
/// (ADR-0036).
///
/// Поколения различаются идентичностью.
final class GraphGeneration {}

/// Текущее поколение графа в контейнере приложения.
///
/// Завершение операции с изменением «граф заменён» начинает новое
/// поколение. Оболочка по нему создаёт корневые страницы заново, а их модели,
/// которые следят за поколением, задают начальное состояние, как при запуске
/// приложения. Поколение живёт весь контейнер: пересозданное поколение
/// сбросило бы страницы без замены графа.
@Riverpod(keepAlive: true)
final class CurrentGraphGeneration extends _$CurrentGraphGeneration {
  @override
  GraphGeneration build() {
    final completions = ref
        .watch(graphCommandCoordinatorProvider.notifier)
        .completions
        .listen((completion) {
          if (completion.confirmedChange is ConfirmedGraphReplacement) {
            state = GraphGeneration();
          }
        });
    ref.onDispose(() => unawaited(completions.cancel()));
    return GraphGeneration();
  }
}
