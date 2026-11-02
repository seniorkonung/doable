import '../../../intention/domain/intention_id.dart';

/// Отмеченное намерение и его актуальное название.
final class RelationBatchSelection {
  const RelationBatchSelection({required this.id, required this.title});

  final IntentionId id;
  final String title;
}

/// Состояние отметок одного экземпляра поиска.
final class RelationBatchState {
  RelationBatchState({
    required this.pageTitle,
    required Iterable<RelationBatchSelection> selected,
  }) : selected = List.unmodifiable(selected);

  final String pageTitle;
  final List<RelationBatchSelection> selected;
}
