import '../../../graph/application/graph_revision.dart';
import '../../../intention/domain/intention.dart';
import '../../../long_term_relation/application/long_term_relation_projection.dart';
import '../../application/choice_path_continuations.dart';
import '../../application/choice_path_draft.dart';
import '../../application/confirmed_choice_path.dart';

/// Состояние верхнего обхода всегда сохраняет видимый пользователю префикс.
sealed class ChoicePathState {
  ChoicePathState(this.draft, Iterable<LongTermRelationSummary> visibleSteps)
    : visibleSteps = List<LongTermRelationSummary>.unmodifiable(visibleSteps);

  final ChoicePathDraft draft;
  final List<LongTermRelationSummary> visibleSteps;

  /// Подтверждение возможно только по проверенному снимку достигнутого шага.
  ConfirmedChoicePath? get confirmedPath => null;
}

final class ChoicePathLoading extends ChoicePathState {
  ChoicePathLoading(super.draft, super.visibleSteps);
}

sealed class ChoicePathConfirmedState extends ChoicePathState {
  ChoicePathConfirmedState({
    required ChoicePathDraft draft,
    required Iterable<LongTermRelationSummary> visibleSteps,
    required this.current,
    required this.revision,
  }) : super(draft, visibleSteps);

  final Intention current;
  final GraphRevision revision;

  bool get canConfirm =>
      draft is ChoicePathDraftProgress &&
      current.readiness == IntentionReadiness.ready;

  @override
  ConfirmedChoicePath? get confirmedPath =>
      canConfirm ? (draft as ChoicePathDraftProgress).confirmedPath : null;
}

/// Продолжений на текущем шаге нет; достигнутое действие всё ещё можно выбрать.
final class ChoicePathEmpty extends ChoicePathConfirmedState {
  ChoicePathEmpty({
    required super.draft,
    required super.visibleSteps,
    required super.current,
    required super.revision,
  });
}

sealed class ChoicePathPageProgress {
  const ChoicePathPageProgress();
}

final class ChoicePathPageIdle extends ChoicePathPageProgress {
  const ChoicePathPageIdle();
}

final class ChoicePathPageLoading extends ChoicePathPageProgress {
  const ChoicePathPageLoading();
}

final class ChoicePathPageFailure extends ChoicePathPageProgress {
  const ChoicePathPageFailure(this.failure);

  final ChoicePathContinuationFailure failure;
  bool get canRetry => failure is ChoicePathContinuationUnavailableFailure;
}

/// Подтверждённые продолжения одной ревизии, включая уже загруженные порции.
final class ChoicePathData extends ChoicePathConfirmedState {
  ChoicePathData({
    required super.draft,
    required super.visibleSteps,
    required super.current,
    required super.revision,
    required Iterable<LongTermRelationSummary> items,
    required this.nextCursor,
    this.progress = const ChoicePathPageIdle(),
  }) : items = List<LongTermRelationSummary>.unmodifiable(items);

  final List<LongTermRelationSummary> items;
  final ChoicePathContinuationCursor? nextCursor;
  final ChoicePathPageProgress progress;

  ChoicePathData withProgress(ChoicePathPageProgress value) => ChoicePathData(
    draft: draft,
    visibleSteps: visibleSteps,
    current: current,
    revision: revision,
    items: items,
    nextCursor: nextCursor,
    progress: value,
  );
}

/// Префикс или снимок устарел; требуется новое чтение до подтверждения.
final class ChoicePathConflict extends ChoicePathState {
  ChoicePathConflict(super.draft, super.visibleSteps);
}

final class ChoicePathNotFound extends ChoicePathState {
  ChoicePathNotFound(super.draft, super.visibleSteps);
}

final class ChoicePathFailure extends ChoicePathState {
  ChoicePathFailure(super.draft, super.visibleSteps, this.failure);

  final ChoicePathContinuationFailure failure;
  bool get canRetry => failure is ChoicePathContinuationUnavailableFailure;
}
