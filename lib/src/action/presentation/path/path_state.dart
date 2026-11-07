import 'package:flutter/foundation.dart';

import '../../../intention/domain/intention_id.dart';
import '../../application/path_candidates.dart';
import '../../domain/action_path.dart';

/// Ключ одной экранной сессии пути. Его создаёт и держит экран, поэтому
/// повторное открытие получает новую сессию.
final class PathSessionKey {
  // Не const: ключи различаются идентичностью.
  PathSessionKey();
}

/// Решение сессии о запросе ухода, единое для «Назад» и системного «назад».
enum PathCloseDecision {
  /// Путь на экране равен исходному.
  close,

  /// Изменённый путь не сохраняется: нужен ответ на «Отменить изменения?».
  askDiscard,
}

/// Путь на экране: последовательность намерений и её прочитанный участок.
sealed class PathDraft {
  const PathDraft();

  /// Намерения пути от корневого до последнего.
  List<IntentionId> get intentions;
}

/// В пути нет ни одного намерения: на месте корня «Выберите причину».
final class EmptyPathDraft extends PathDraft {
  const EmptyPathDraft();

  @override
  List<IntentionId> get intentions => const [];
}

/// Участок пути читается: названий и связей ещё нет.
final class LoadingPathDraft extends PathDraft {
  LoadingPathDraft(Iterable<IntentionId> intentions)
    : intentions = List.unmodifiable(intentions);

  @override
  final List<IntentionId> intentions;
}

/// Путь — целый участок с текущими данными намерений и связей.
final class LoadedPathDraft extends PathDraft {
  const LoadedPathDraft(this.segment);

  final PathSegment segment;

  @override
  List<IntentionId> get intentions => [
    segment.root.id,
    for (final step in segment.steps) step.intention.id,
  ];
}

/// Чтение участка завершилось отказом; это не пустой путь.
final class FailedPathDraft extends PathDraft {
  FailedPathDraft(Iterable<IntentionId> intentions, this.failure)
    : intentions = List.unmodifiable(intentions);

  @override
  final List<IntentionId> intentions;
  final PathCandidatesReadFailure failure;

  /// Повтор несёт только доказанно временный отказ.
  bool get canRetry => failure is PathCandidatesUnavailableFailure;
}

final class PathState {
  PathState({required ActionPath? original, required this.draft})
    : original = original?.intentions ?? const [];

  const PathState._(this.original, this.draft);

  /// Исходный путь, с которым открыт экран; пустой, пока путь не выбран.
  final List<IntentionId> original;
  final PathDraft draft;

  /// Пути сравниваются по последовательности намерений.
  bool get isChanged => !listEquals(draft.intentions, original);

  /// Сохраняется только путь, который показан на экране.
  bool get canSave => isChanged && draft is LoadedPathDraft;

  PathCloseDecision get closeDecision =>
      isChanged ? PathCloseDecision.askDiscard : PathCloseDecision.close;

  PathState withDraft(PathDraft value) => PathState._(original, value);
}
