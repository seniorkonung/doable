import '../../../graph/application/graph_command_coordinator.dart';
import '../../../intention/domain/intention_id.dart';
import '../../../intention/presentation/editor/intention_draft_tag_set.dart';
import '../../application/tag_catalog.dart';
import 'tag_catalog_view_model.dart';

/// Контекст интерфейса общего выбора тегов.
///
/// Определяет смысл явного действия над кандидатом и отделён от режима
/// чтения хранилища: черновик читает обычный полный каталог, а его набор
/// принадлежит сессии создания. Данные сессии и идентификатор ещё не
/// созданного намерения в контракт хранилища не попадают. Контекст собирает
/// вызывающий сценарий из явных зависимостей; общий выбор не решает, когда
/// создавать намерение.
sealed class TagSelectionContext {
  const TagSelectionContext();

  /// Режим чтения каталога из хранилища.
  TagCatalogMode get readMode;
}

/// Просмотр каталога без явного действия выбора.
final class TagBrowseContext extends TagSelectionContext {
  const TagBrowseContext();

  @override
  TagCatalogMode get readMode => const TagCatalogBrowseMode();

  @override
  bool operator ==(Object other) => other is TagBrowseContext;

  @override
  int get hashCode => (TagBrowseContext).hashCode;
}

/// Постоянное назначение тега существующему намерению.
final class TagAssignmentContext extends TagSelectionContext {
  const TagAssignmentContext(this.intentionId);

  final IntentionId intentionId;

  @override
  TagCatalogMode get readMode => TagCatalogSelectionMode(intentionId);

  @override
  bool operator ==(Object other) =>
      other is TagAssignmentContext && other.intentionId == intentionId;

  @override
  int get hashCode => Object.hash(TagAssignmentContext, intentionId);
}

/// Добавление тегов в набор черновика создаваемого намерения.
///
/// Контекст определяется сессией: два контекста равны, только если
/// принадлежат одному набору черновика.
final class TagDraftContext extends TagSelectionContext {
  const TagDraftContext(this.tagSet);

  final IntentionDraftTagSet tagSet;

  @override
  TagCatalogMode get readMode => const TagCatalogBrowseMode();

  @override
  bool operator ==(Object other) =>
      other is TagDraftContext && identical(other.tagSet, tagSet);

  @override
  int get hashCode => identityHashCode(tagSet);
}

/// Явное действие контекста над подтверждённым кандидатом общего выбора.
///
/// Варианты различают момент записи: [TagAssignmentAction] отправляет
/// постоянную команду, [TagDraftAdditionAction] меняет только набор
/// черновика. Выбор кандидата сам по себе действие не выполняет.
sealed class TagSelectionAction {
  const TagSelectionAction();

  /// Разрешено ли действие над текущим кандидатом.
  bool get canPerform;
}

/// Постоянное назначение кандидата существующему намерению.
///
/// Сохраняет проверки общего выбора: тег подтверждён наблюдением и
/// актуальным снимком, статус пары подтверждён свободным, а отказ и успех
/// предъявляются по протоколу координатора. Неизвестный статус пары запись
/// не разрешает.
final class TagAssignmentAction extends TagSelectionAction {
  const TagAssignmentAction(this._catalog);

  final TagCatalogViewModel _catalog;

  @override
  bool get canPerform => _catalog.canAssignSelected;

  /// Передаёт координатору `AssignTag`; `null` — действие недоступно.
  TagCommandStart? perform() => _catalog.assignSelected();
}

/// Добавление кандидата в набор черновика.
///
/// Меняет только набор сессии через её контракт: команд графа не
/// отправляет, назначений не записывает и статус назначения не проверяет.
/// Закрытая сессия и выполняющаяся отправка добавление отвергают.
final class TagDraftAdditionAction extends TagSelectionAction {
  const TagDraftAdditionAction(this._catalog, this._tagSet);

  final TagCatalogViewModel _catalog;
  final IntentionDraftTagSet _tagSet;

  @override
  bool get canPerform {
    final candidate = _catalog.actionableCandidate;
    final current = _tagSet.current;
    return candidate != null &&
        !current.tagIds.contains(candidate.id) &&
        switch (current.availability) {
          IntentionDraftAvailability.editable => true,
          IntentionDraftAvailability.submitting ||
          IntentionDraftAvailability.closed => false,
        };
  }

  /// Добавляет кандидата в набор черновика; `null` — нет подтверждённого
  /// кандидата. Повторное добавление, отправка и закрытие сессии набор не
  /// меняют и различаются результатом.
  IntentionDraftTagAddition? perform() {
    final candidate = _catalog.actionableCandidate;
    return candidate == null ? null : _tagSet.add(candidate);
  }
}
