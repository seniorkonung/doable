import '../../graph/application/graph_command_result.dart';
import '../../graph/application/graph_revision.dart';
import '../../intention/domain/intention.dart';
import '../../intention/domain/intention_id.dart';
import '../../long_term_relation/domain/long_term_relation.dart';
import '../../long_term_relation/domain/long_term_relation_id.dart';
import '../domain/choice_path_step_id.dart';
import '../domain/daily_choice_id.dart';
import 'confirmed_choice_path.dart';
import 'daily_choice_details.dart';

/// Вход задаёт прямого участника: основание верхнего обхода либо действие
/// нижнего. Для замены пути используются те же варианты запроса.
sealed class ChoicePathSuggestionsQuery {
  const ChoicePathSuggestionsQuery(this.participantId);

  final IntentionId participantId;
}

final class ChoicePathSuggestionsForSource extends ChoicePathSuggestionsQuery {
  const ChoicePathSuggestionsForSource(super.sourceIntentionId);
}

final class ChoicePathSuggestionsForAction extends ChoicePathSuggestionsQuery {
  const ChoicePathSuggestionsForAction(super.selectedActionId);
}

/// Недопустимость нового выбора не означает повреждение сохранённого пути.
enum ChoicePathSuggestionUnavailableReason {
  archivedIntention,
  archivedRelation,
  actionNotReady,
}

/// Конструктор вызывается только после проверки целого сохранённого выбора.
/// Повреждение любого кандидата отклоняет всё чтение как corruption.
final class ChoicePathSuggestionCorruptionException implements Exception {
  const ChoicePathSuggestionCorruptionException();
}

/// Снимок текущих данных одного прежнего пути, направленного от основания к
/// действию. Дата, описание и выполнение прежнего выбора не наследуются.
sealed class ChoicePathSuggestion {
  factory ChoicePathSuggestion.fromDetails(DailyChoiceDetails details) {
    final path = List<DailyChoicePathStepDetails>.unmodifiable(details.path);
    _validatePath(details, path);

    final reason = _unavailableReason(details, path);
    if (reason != null) {
      return UnavailableChoicePathSuggestion._(details, path, reason);
    }
    return AvailableChoicePathSuggestion._(
      details,
      path,
      ConfirmedChoicePath([
        for (final item in path)
          ConfirmedChoicePathStep(
            relationId: item.relation.id,
            sourceIntentionId: item.source.id,
            type: item.relation.type,
            relatedIntentionId: item.related.id,
          ),
      ]),
    );
  }

  const ChoicePathSuggestion._(
    this.originChoiceId,
    this.source,
    this.action,
    this.path,
  );

  final DailyChoiceId originChoiceId;
  final Intention source;
  final Intention action;
  final List<DailyChoicePathStepDetails> path;
}

/// Предложение содержит показанный смысл каждой связи; команда ещё раз
/// проверяет его и допустимость в транзакции сохранения.
final class AvailableChoicePathSuggestion extends ChoicePathSuggestion {
  AvailableChoicePathSuggestion._(
    DailyChoiceDetails details,
    List<DailyChoicePathStepDetails> path,
    this.confirmedPath,
  ) : super._(details.choice.id, details.source, details.selected, path);

  final ConfirmedChoicePath confirmedPath;
}

/// У недоступного маршрута нет предложения для команды создания или замены.
final class UnavailableChoicePathSuggestion extends ChoicePathSuggestion {
  UnavailableChoicePathSuggestion._(
    DailyChoiceDetails details,
    List<DailyChoicePathStepDetails> path,
    this.reason,
  ) : super._(details.choice.id, details.source, details.selected, path);

  final ChoicePathSuggestionUnavailableReason reason;
}

void _validatePath(
  DailyChoiceDetails details,
  List<DailyChoicePathStepDetails> path,
) {
  final choice = details.choice;
  if (details.source.id != choice.sourceIntentionId ||
      details.selected.id != choice.selectedIntentionId ||
      path.isEmpty) {
    throw const ChoicePathSuggestionCorruptionException();
  }
  var current = details.source.id;
  final visited = <IntentionId>{current};
  final relations = <LongTermRelationId>{};
  ChoicePathStepId? previousStepId;
  for (final item in path) {
    if (item.step.dailyChoiceId != choice.id ||
        item.step.previousStepId != previousStepId ||
        item.step.relationId != item.relation.id ||
        item.source.id != current ||
        item.relation.sourceIntentionId != item.source.id ||
        item.relation.relatedIntentionId != item.related.id ||
        !visited.add(item.related.id) ||
        !relations.add(item.relation.id)) {
      throw const ChoicePathSuggestionCorruptionException();
    }
    current = item.related.id;
    previousStepId = item.step.id;
  }
  if (current != details.selected.id) {
    throw const ChoicePathSuggestionCorruptionException();
  }
}

ChoicePathSuggestionUnavailableReason? _unavailableReason(
  DailyChoiceDetails details,
  List<DailyChoicePathStepDetails> path,
) {
  if (details.source.archiveState == IntentionArchiveState.archived ||
      path.any(
        (step) => step.related.archiveState == IntentionArchiveState.archived,
      )) {
    return ChoicePathSuggestionUnavailableReason.archivedIntention;
  }
  if (path.any((step) => step.relation.scope == RelationScope.archived)) {
    return ChoicePathSuggestionUnavailableReason.archivedRelation;
  }
  if (details.selected.readiness != IntentionReadiness.ready) {
    return ChoicePathSuggestionUnavailableReason.actionNotReady;
  }
  return null;
}

/// Репозиторий берёт последние 20 выборов участника по creation_sequence
/// DESC до проверки доступности и устранения повторов. До пяти допустимых
/// разных текущих цепочек упорядочены
/// по той же последовательности, представитель повтора — самый новый выбор.
/// Равенство цепочек определяется только порядком LongTermRelationId.
/// Технический ключ и SQL не входят в прикладной ответ.
final class ChoicePathSuggestionsSnapshot {
  ChoicePathSuggestionsSnapshot({
    required this.query,
    required Iterable<AvailableChoicePathSuggestion> items,
    required this.revision,
    Iterable<IntentionId> observedIntentionIds = const [],
    Iterable<LongTermRelationId> observedRelationIds = const [],
  }) : items = List<AvailableChoicePathSuggestion>.unmodifiable(items),
       observedIntentionIds = Set<IntentionId>.unmodifiable(
         observedIntentionIds,
       ),
       observedRelationIds = Set<LongTermRelationId>.unmodifiable(
         observedRelationIds,
       ) {
    if (this.items.length > maxSuggestions) {
      throw ArgumentError.value(this.items, 'items');
    }
    final choiceIds = <DailyChoiceId>{};
    final pathKeys = <List<LongTermRelationId>>[];
    for (final item in this.items) {
      final expected = switch (query) {
        ChoicePathSuggestionsForSource() => item.source.id,
        ChoicePathSuggestionsForAction() => item.action.id,
      };
      final key = [for (final step in item.path) step.relation.id];
      if (expected != query.participantId ||
          !choiceIds.add(item.originChoiceId) ||
          pathKeys.any((previous) => _samePath(previous, key))) {
        throw ArgumentError.value(this.items, 'items');
      }
      pathKeys.add(key);
    }
  }

  static const maxCandidates = 20;
  static const maxSuggestions = 5;

  final ChoicePathSuggestionsQuery query;
  final List<AvailableChoicePathSuggestion> items;
  final GraphRevision revision;

  /// Участники и связи всех проверенных кандидатов, включая исключённые из
  /// выдачи. Нужны для актуализации, если скрытый путь вновь станет допустимым.
  final Set<IntentionId> observedIntentionIds;
  final Set<LongTermRelationId> observedRelationIds;
}

bool _samePath(List<LongTermRelationId> left, List<LongTermRelationId> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}

sealed class ChoicePathSuggestionsFailure implements GraphCommandFailure {
  const ChoicePathSuggestionsFailure();
}

final class ChoicePathSuggestionsIntentionNotFoundFailure
    extends ChoicePathSuggestionsFailure {
  const ChoicePathSuggestionsIntentionNotFoundFailure();

  @override
  GraphFailureCategory get category => GraphFailureCategory.notFound;
}

final class ChoicePathSuggestionsUnavailableFailure
    extends ChoicePathSuggestionsFailure {
  const ChoicePathSuggestionsUnavailableFailure();

  @override
  GraphFailureCategory get category => GraphFailureCategory.unavailable;
}

final class ChoicePathSuggestionsCorruptionFailure
    extends ChoicePathSuggestionsFailure {
  const ChoicePathSuggestionsCorruptionFailure();

  @override
  GraphFailureCategory get category => GraphFailureCategory.corruption;
}

final class ChoicePathSuggestionsUnexpectedFailure
    extends ChoicePathSuggestionsFailure {
  const ChoicePathSuggestionsUnexpectedFailure();

  @override
  GraphFailureCategory get category => GraphFailureCategory.unexpected;
}

typedef ChoicePathSuggestionsResult =
    GraphResult<ChoicePathSuggestionsSnapshot, ChoicePathSuggestionsFailure>;
typedef ChoicePathSuggestionsSuccess =
    GraphResultSuccess<
      ChoicePathSuggestionsSnapshot,
      ChoicePathSuggestionsFailure
    >;
typedef ChoicePathSuggestionsError =
    GraphResultFailure<
      ChoicePathSuggestionsSnapshot,
      ChoicePathSuggestionsFailure
    >;
