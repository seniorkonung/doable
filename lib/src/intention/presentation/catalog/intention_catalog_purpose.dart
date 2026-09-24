import '../../application/intention_catalog.dart';
import '../../domain/intention_id.dart';

/// Назначение, ради которого открыт ограниченный каталог намерений.
///
/// Общий просмотр, выбор участника связи и выбор действия читают одни и те же
/// порции одного источника, но остаются независимыми состояниями: охват,
/// фильтр и загруженная часть одного не изменяют другие.
sealed class IntentionCatalogPurpose {
  const IntentionCatalogPurpose();
}

/// Просмотр каталога намерений как самостоятельного списка.
final class BrowseIntentionCatalog extends IntentionCatalogPurpose {
  const BrowseIntentionCatalog();

  @override
  bool operator ==(Object other) => other is BrowseIntentionCatalog;

  @override
  int get hashCode => (BrowseIntentionCatalog).hashCode;
}

/// Выбор существующего активного действия для дневного выбора.
///
/// Охват и готовность закреплены назначением: вызывающая сторона не может
/// превратить этот список в выбор архивного или неготового намерения.
final class SelectDailyChoiceAction extends IntentionCatalogPurpose {
  const SelectDailyChoiceAction();

  @override
  bool operator ==(Object other) => other is SelectDailyChoiceAction;

  @override
  int get hashCode => (SelectDailyChoiceAction).hashCode;
}

/// Выбор существующего намерения участником долговременной связи.
///
/// Второе намерение пары исключается по идентификатору: прямая самосвязь
/// запрещена, а одноимённые намерения остаются разными участниками. Контекст
/// редактируемой связи задаёт допустимый архивный охват и не позволяет
/// вызывающей стороне составить режим выбора только архивных намерений.
final class SelectRelationParticipant extends IntentionCatalogPurpose {
  const SelectRelationParticipant({
    required this.excludedIntentionId,
    required this.selectionContext,
  });

  final IntentionId excludedIntentionId;
  final RelationParticipantSelectionContext selectionContext;

  IntentionScope get scope => selectionContext.catalogScope;

  @override
  bool operator ==(Object other) =>
      other is SelectRelationParticipant &&
      other.excludedIntentionId == excludedIntentionId &&
      other.selectionContext == selectionContext;

  @override
  int get hashCode => Object.hash(
    SelectRelationParticipant,
    excludedIntentionId,
    selectionContext,
  );
}

/// Допустимый охват каталога при выборе участника связи.
///
/// Создаваемая и активная связи соединяют только активные намерения.
/// Архивная связь может сохранить либо явно выбрать как активного, так и
/// архивированного участника; отдельный режим «только архивные» ей не нужен.
enum RelationParticipantSelectionContext {
  activeRelation(IntentionScope.active),
  archivedRelation(IntentionScope.all);

  const RelationParticipantSelectionContext(this.catalogScope);

  final IntentionScope catalogScope;
}
