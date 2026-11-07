import '../../../long_term_relation/application/relation_pair_probe.dart';
import '../../domain/intention_id.dart';

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
/// Назначение каталога экрану выбора передать нельзя: оно разбирается по
/// наследнику.
sealed class IntentionPickerPurpose extends IntentionCatalogPurpose {
  const IntentionPickerPurpose();
}

/// Поиск начала пути исключает текущий корень при его замене.
final class SelectPathStart extends IntentionPickerPurpose {
  const SelectPathStart({required this.session, this.currentRoot});

  final IntentionSearchSession session;
  final IntentionId? currentRoot;

  @override
  bool operator ==(Object other) =>
      other is SelectPathStart &&
      identical(other.session, session) &&
      other.currentRoot == currentRoot;

  @override
  int get hashCode =>
      Object.hash(SelectPathStart, identityHashCode(session), currentRoot);
}

/// Выбор существующего активного намерения участником долговременной связи.
///
/// Участник другой роли из [pairProbe] исключается по идентификатору: прямая
/// самосвязь запрещена, а одноимённые намерения остаются разными участниками.
final class SelectRelationParticipant extends IntentionPickerPurpose {
  const SelectRelationParticipant({
    required this.session,
    required this.pairProbe,
  });

  final RelationPairProbe pairProbe;

  final IntentionSearchSession session;

  @override
  bool operator ==(Object other) =>
      other is SelectRelationParticipant &&
      other.pairProbe == pairProbe &&
      identical(other.session, session);

  @override
  int get hashCode => Object.hash(
    SelectRelationParticipant,
    pairProbe,
    identityHashCode(session),
  );
}
