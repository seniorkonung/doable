import '../../domain/intention_id.dart';

/// Назначение, ради которого открыт ограниченный каталог намерений.
///
/// Общий просмотр и выбор участника долговременной связи читают одни и те же
/// порции одного источника, но остаются независимыми состояниями: охват,
/// фильтр и загруженная часть одного не изменяют другой.
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

/// Выбор существующего намерения участником долговременной связи.
///
/// Второе намерение пары исключается по идентификатору: прямая самосвязь
/// запрещена, а одноимённые намерения остаются разными участниками.
final class SelectRelationParticipant extends IntentionCatalogPurpose {
  const SelectRelationParticipant({required this.excludedIntentionId});

  final IntentionId excludedIntentionId;

  @override
  bool operator ==(Object other) =>
      other is SelectRelationParticipant &&
      other.excludedIntentionId == excludedIntentionId;

  @override
  int get hashCode =>
      Object.hash(SelectRelationParticipant, excludedIntentionId);
}
