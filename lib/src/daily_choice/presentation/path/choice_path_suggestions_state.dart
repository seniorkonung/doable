import '../../../graph/application/graph_revision.dart';
import '../../application/choice_path_suggestions.dart';
import '../../domain/daily_choice_id.dart';

/// Подтвердить маршрут можно только из актуальной выдачи.
sealed class ChoicePathSuggestionsState {
  const ChoicePathSuggestionsState(this.query);

  final ChoicePathSuggestionsQuery query;
  List<AvailableChoicePathSuggestion> get items => const [];
}

final class ChoicePathSuggestionsLoading extends ChoicePathSuggestionsState {
  const ChoicePathSuggestionsLoading(super.query);
}

sealed class ChoicePathSuggestionsCurrent extends ChoicePathSuggestionsState {
  ChoicePathSuggestionsCurrent(this.snapshot) : super(snapshot.query);

  final ChoicePathSuggestionsSnapshot snapshot;
  GraphRevision get revision => snapshot.revision;

  @override
  List<AvailableChoicePathSuggestion> get items => snapshot.items;
}

final class ChoicePathSuggestionsEmpty extends ChoicePathSuggestionsCurrent {
  ChoicePathSuggestionsEmpty(super.snapshot);
}

final class ChoicePathSuggestionsReady extends ChoicePathSuggestionsCurrent {
  ChoicePathSuggestionsReady(super.snapshot);

  AvailableChoicePathSuggestion? confirmable(DailyChoiceId id) {
    for (final item in items) {
      if (item.originChoiceId == id) {
        return item;
      }
    }
    return null;
  }
}

/// Прежние маршруты можно просмотреть, но подтверждение ждёт нового снимка.
final class ChoicePathSuggestionsUpdating extends ChoicePathSuggestionsState {
  ChoicePathSuggestionsUpdating(this.snapshot) : super(snapshot.query);

  final ChoicePathSuggestionsSnapshot snapshot;

  @override
  List<AvailableChoicePathSuggestion> get items => snapshot.items;
}

final class ChoicePathSuggestionsRefreshFailure
    extends ChoicePathSuggestionsState {
  ChoicePathSuggestionsRefreshFailure(this.snapshot, this.failure)
    : super(snapshot.query);

  final ChoicePathSuggestionsSnapshot snapshot;
  final ChoicePathSuggestionsFailure failure;
  bool get canRetry => failure is ChoicePathSuggestionsUnavailableFailure;

  @override
  List<AvailableChoicePathSuggestion> get items => snapshot.items;
}

final class ChoicePathSuggestionsNotFound extends ChoicePathSuggestionsState {
  const ChoicePathSuggestionsNotFound(super.query);
}

final class ChoicePathSuggestionsLoadFailure
    extends ChoicePathSuggestionsState {
  const ChoicePathSuggestionsLoadFailure(super.query, this.failure);

  final ChoicePathSuggestionsFailure failure;
  bool get canRetry => failure is ChoicePathSuggestionsUnavailableFailure;
}
