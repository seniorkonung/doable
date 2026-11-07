import 'package:flutter/foundation.dart';

import '../../../graph/application/graph_command_coordinator.dart';
import '../../../intention/domain/intention_id.dart';
import '../../../long_term_relation/domain/long_term_relation.dart';
import '../../../long_term_relation/domain/long_term_relation_id.dart';
import '../../application/action_details.dart';
import '../../application/action_result.dart';
import '../../application/path_candidates.dart';
import '../../domain/action_id.dart';
import '../../domain/action_path.dart';
import 'path_segment.dart';

/// Ключ одной экранной сессии пути. Его создаёт и держит экран, поэтому
/// повторное открытие получает новую сессию.
final class PathSessionKey {
  // Не const: ключи различаются идентичностью.
  PathSessionKey();
}

/// Откуда открыт экран пути: от этого зависят путь при открытии и то, что
/// делает «Сохранить».
sealed class PathPurpose {
  const PathPurpose();

  /// Исходный путь; `null`, пока путь нового действия не выбран.
  ActionPath? get original;

  /// Путь, с которым экран открывается; `null` — путь на экране пуст.
  ActionPath? get start;
}

/// Путь листа нового действия: «Сохранить» возвращает его в лист.
final class NewActionPathPurpose extends PathPurpose {
  const NewActionPathPurpose(
    this.original, {
    ActionPath? start,
    this.createdIntention = false,
    this.onSaved,
  }) : start = start ?? original;

  /// Путь листа, прочитанный с разрывом: экран открывается с первого целого
  /// участка [start], а без актуальных намерений — пустым.
  const NewActionPathPurpose.segment(
    ActionPath this.original, {
    required this.start,
    this.onSaved,
  }) : createdIntention = false;

  @override
  final ActionPath? original;

  @override
  final ActionPath? start;

  final bool createdIntention;
  final void Function(LoadedPathDraft draft)? onSaved;
}

/// Сохранённый путь действия: «Сохранить» сам заменяет его. Путь с разрывом
/// открывается с первого целого участка.
final class ExistingActionPathPurpose extends PathPurpose {
  ExistingActionPathPurpose(ActionDetails details)
    : actionId = details.action.id,
      original = details.action.path,
      start = firstWholeSegment(details.path);

  final ActionId actionId;

  @override
  final ActionPath original;

  @override
  final ActionPath? start;
}

/// Замена сохранённого пути с экрана «Изменить путь».
sealed class PathSaving {
  const PathSaving();
}

final class PathSavingIdle extends PathSaving {
  const PathSavingIdle();
}

/// Принятая замена выполняется: путь на экране не меняется, а уход не
/// спрашивает об отмене.
final class PathSavingRunning extends PathSaving {
  const PathSavingRunning();
}

/// Отказ замены остаётся на экране до следующего сохранения.
final class PathSavingFailed extends PathSaving {
  const PathSavingFailed(this.failure, {this.presentation});

  final ActionCommandFailure failure;
  final GraphInitiatorPresentationClaim? presentation;
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

/// В пути есть намерения: переключатель половин показан при любом исходе
/// чтения участка.
sealed class NonEmptyPathDraft extends PathDraft {
  const NonEmptyPathDraft();

  CandidateState get candidates;

  NonEmptyPathDraft withCandidates(CandidateState value);
}

/// Участок пути читается: названий и связей ещё нет.
final class LoadingPathDraft extends NonEmptyPathDraft {
  LoadingPathDraft(Iterable<IntentionId> intentions, this.candidates)
    : intentions = List.unmodifiable(intentions);

  @override
  final List<IntentionId> intentions;
  @override
  final CandidateState candidates;

  @override
  LoadingPathDraft withCandidates(CandidateState value) =>
      LoadingPathDraft(intentions, value);
}

/// Путь — целый участок с текущими данными намерений и связей.
final class LoadedPathDraft extends NonEmptyPathDraft {
  const LoadedPathDraft(this.segment, this.candidates, {this.appended});

  final PathSegment segment;
  final PathCandidate? appended;
  @override
  final CandidateState candidates;

  @override
  List<IntentionId> get intentions => [
    segment.root.id,
    for (final step in segment.steps) step.intention.id,
    if (appended case final candidate?) candidate.relation.relatedIntentionId,
  ];

  @override
  LoadedPathDraft withCandidates(CandidateState value) =>
      LoadedPathDraft(segment, value, appended: appended);
}

/// Чтение участка завершилось отказом; это не пустой путь.
final class FailedPathDraft extends NonEmptyPathDraft {
  FailedPathDraft(
    Iterable<IntentionId> intentions,
    this.failure,
    this.candidates,
  ) : intentions = List.unmodifiable(intentions);

  @override
  final List<IntentionId> intentions;
  final PathCandidatesReadFailure failure;
  @override
  final CandidateState candidates;

  /// Повтор несёт только доказанно временный отказ.
  bool get canRetry => failure is PathCandidatesUnavailableFailure;

  @override
  FailedPathDraft withCandidates(CandidateState value) =>
      FailedPathDraft(intentions, failure, value);
}

/// Связи и намерения, созданные с экрана пути. Они уже в графе и остаются
/// там при любом уходе с экрана.
final class PathCreations {
  const PathCreations({this.relations = const {}, this.intentions = 0});

  /// Связи, добавленные «Добавить»; их кандидаты отмечены «Новое».
  final Set<LongTermRelationId> relations;

  /// Намерения, созданные в поисках, открытых с экрана.
  final int intentions;

  PathCreations withRelations(Iterable<LongTermRelationId> added) =>
      PathCreations(
        relations: {...relations, ...added},
        intentions: intentions,
      );
  PathCreations withIntention() =>
      PathCreations(relations: relations, intentions: intentions + 1);
}

final class PathState {
  PathState({required ActionPath? original, required this.draft})
    : original = original?.intentions ?? const [],
      saving = const PathSavingIdle(),
      creations = const PathCreations();

  const PathState._(this.original, this.draft, this.saving, this.creations);

  /// Исходный путь, с которым открыт экран; пустой, пока путь не выбран.
  final List<IntentionId> original;
  final PathDraft draft;
  final PathSaving saving;
  final PathCreations creations;

  /// Кандидаты продолжения; у пустого пути их нет.
  CandidateState? get candidates => switch (draft) {
    EmptyPathDraft() => null,
    NonEmptyPathDraft(:final candidates) => candidates,
  };

  /// Пути сравниваются по последовательности намерений.
  bool get isChanged => !listEquals(draft.intentions, original);

  /// Сохраняется только путь, который показан на экране, и не повторно, пока
  /// принятая замена выполняется.
  bool get canSave =>
      isChanged && draft is LoadedPathDraft && saving is! PathSavingRunning;

  /// Уход во время принятой замены её не отменяет, поэтому не спрашивает.
  PathCloseDecision get closeDecision =>
      isChanged && saving is! PathSavingRunning
      ? PathCloseDecision.askDiscard
      : PathCloseDecision.close;

  PathState withDraft(PathDraft value) =>
      PathState._(original, value, saving, creations);
  PathState withSaving(PathSaving value) =>
      PathState._(original, draft, value, creations);
  PathState withCreations(PathCreations value) =>
      PathState._(original, draft, saving, value);
}

final class CandidateState {
  /// Кандидаты пути, который ещё не читался: половину выбирает первое чтение.
  static const initial = CandidateState(
    half: LongTermRelationType.need,
    loading: true,
    chooseDefault: true,
  );

  const CandidateState({
    required this.half,
    this.counts,
    this.items = const [],
    this.cursor,
    this.loading = false,
    this.failure,
    this.chooseDefault = false,
  });
  final LongTermRelationType half;
  final PathCandidateCounts? counts;
  final List<PathCandidate> items;
  final PathCandidatesCursor? cursor;
  final bool loading;
  final PathCandidatesReadFailure? failure;
  final bool chooseDefault;
}
