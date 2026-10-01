import 'intention_id.dart';
import 'intention_text.dart';

enum IntentionReadiness { notReady, ready }

enum IntentionArchiveState { active, archived }

/// Отметка избранного намерения: явное решение человека держать намерение
/// на Главной. Отметка не выражает приоритет и не является редактируемым
/// полем намерения, поэтому в [Intention] не входит.
enum FavoriteMark { notFavorite, favorite }

final class IntentionTimestamp {
  IntentionTimestamp(DateTime value) : value = value.toUtc();

  final DateTime value;

  @override
  bool operator ==(Object other) =>
      other is IntentionTimestamp && other.value == value;

  @override
  int get hashCode => value.hashCode;
}

final class Intention {
  factory Intention({
    required IntentionId id,
    required String title,
    required String? description,
    required IntentionReadiness readiness,
    required IntentionArchiveState archiveState,
    required IntentionTimestamp createdAt,
    required IntentionTimestamp updatedAt,
  }) => Intention._(
    id: id,
    title: IntentionText.normalizeTitle(title),
    description: description == null
        ? null
        : IntentionText.normalizeDescription(description),
    readiness: readiness,
    archiveState: archiveState,
    createdAt: createdAt,
    updatedAt: updatedAt,
  );

  const Intention._({
    required this.id,
    required this.title,
    required this.description,
    required this.readiness,
    required this.archiveState,
    required this.createdAt,
    required this.updatedAt,
  });

  final IntentionId id;
  final String title;
  final String? description;
  final IntentionReadiness readiness;
  final IntentionArchiveState archiveState;
  final IntentionTimestamp createdAt;
  final IntentionTimestamp updatedAt;
}
