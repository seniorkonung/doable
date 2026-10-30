import '../../../long_term_relation/application/relation_pair_probe.dart';
import '../../application/intention_catalog.dart';

/// Идентичность одного поиска на всё время жизни его страницы.
///
/// Создаётся при монтировании и передаётся всем секциям того же поиска.
/// Новый экземпляр всегда обозначает отдельную сессию.
final class IntentionSearchSession {
  IntentionSearchSession();
}

/// Назначение, ради которого открыт ограниченный каталог намерений.
///
/// Все назначения читают одни и те же порции одного источника, но остаются
/// независимыми состояниями: охват, фильтр и загруженная часть одного не
/// изменяют другие.
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

/// Назначение поиска, который показывает экран выбора намерения.
///
/// Вид выбираемого — действие или намерение — выводится разбором наследника,
/// поэтому назначение каталога экрану выбора передать нельзя.
sealed class IntentionPickerPurpose extends IntentionCatalogPurpose {
  const IntentionPickerPurpose();
}

/// Выбор существующего активного действия для дневного выбора.
///
/// Охват и готовность закреплены назначением: вызывающая сторона не может
/// превратить этот список в выбор архивного или неготового намерения.
final class SelectDailyChoiceAction extends IntentionPickerPurpose {
  const SelectDailyChoiceAction({required this.session});

  final IntentionSearchSession session;

  @override
  bool operator ==(Object other) =>
      other is SelectDailyChoiceAction && identical(other.session, session);

  @override
  int get hashCode =>
      Object.hash(SelectDailyChoiceAction, identityHashCode(session));
}

/// Выбор нового исходного намерения при замене пути дневного выбора.
///
/// Любое активное намерение допустимо как основание, независимо от готовности.
/// Прежние участники не исключаются: новый путь заменяет обоих участников.
final class SelectDailyChoiceSource extends IntentionPickerPurpose {
  const SelectDailyChoiceSource({required this.session});

  final IntentionSearchSession session;

  @override
  bool operator ==(Object other) =>
      other is SelectDailyChoiceSource && identical(other.session, session);

  @override
  int get hashCode =>
      Object.hash(SelectDailyChoiceSource, identityHashCode(session));
}

/// Выбор существующего намерения участником долговременной связи.
///
/// Участник другой роли из [pairProbe] исключается по идентификатору: прямая
/// самосвязь запрещена, а одноимённые намерения остаются разными участниками.
/// Без пробы ничего не исключается: второй участник ещё не выбран. Контекст
/// редактируемой связи задаёт допустимый архивный охват и не позволяет
/// вызывающей стороне составить режим выбора только архивных намерений.
final class SelectRelationParticipant extends IntentionPickerPurpose {
  const SelectRelationParticipant({
    required this.selectionContext,
    required this.session,
    this.pairProbe,
  });

  final RelationPairProbe? pairProbe;
  final RelationParticipantSelectionContext selectionContext;

  final IntentionSearchSession session;

  IntentionScope get scope => selectionContext.catalogScope;

  @override
  bool operator ==(Object other) =>
      other is SelectRelationParticipant &&
      other.pairProbe == pairProbe &&
      other.selectionContext == selectionContext &&
      identical(other.session, session);

  @override
  int get hashCode => Object.hash(
    SelectRelationParticipant,
    pairProbe,
    selectionContext,
    identityHashCode(session),
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
