import 'package:doable/src/data/local/app_database.dart';
import 'package:doable/src/graph/data/drift_personal_graph_repository.dart';
import 'package:doable/src/intention/application/intention_command.dart';
import 'package:doable/src/intention/application/intention_id_generator.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/tag/application/tag_id_generator.dart';
import 'package:doable/src/tag/domain/tag_id.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import 'favorite_storage_fixture.dart';
import 'in_memory_diagnostics_sink.dart';
import 'tag_storage_fixture.dart';

/// Намерение, которое создаётся сразу с тегами, готовностью и отметкой
/// избранного.
const creationDurabilityIntentionNumber = 5;

/// Самостоятельный тег, который создаётся отдельной командой до создания
/// намерения и выбирается для него.
const creationDurabilityStandaloneTagNumber = 305;

/// Единственное показание часов репозитория полного создания.
final creationDurabilityTime = DateTime.utc(2026, 10, 4, 9);

IntentionId get creationDurabilityIntentionId => (IntentionId.decode(
  tagFixtureId(creationDurabilityIntentionNumber),
) as IntentionIdDecodingSuccess).id;

TagId get creationDurabilityStandaloneTagId =>
    _tagId(creationDurabilityStandaloneTagNumber);

/// Тег фикстуры, уже назначенный активному и архивированному намерениям.
TagId get creationDurabilityExistingTagId => _tagId(firstTagNumber);

/// Прежний граф тегов, связей и дневных выборов фикстуры тегов. Активное
/// намерение 1 отмечено на месте 2, архивированное намерение 2 — на
/// последнем месте 5: новое избранное встаёт за максимумом всего порядка.
void seedCreationDurabilityGraph(sqlite.Database database) {
  seedTagStorageFixture(database);
  storeFavoriteMark(database, intentionId: tagFixtureId(1), position: 2);
  storeFavoriteMark(database, intentionId: tagFixtureId(2), position: 5);
}

/// Репозиторий с детерминированными идентификаторами нового намерения и
/// самостоятельного тега и единым показанием часов.
DriftPersonalGraphRepository creationDurabilityRepository(
  AppDatabase database,
) => DriftPersonalGraphRepository(
  database,
  _FixedIntentionIds(creationDurabilityIntentionId),
  () => creationDurabilityTime,
  InMemoryDiagnosticsSink(),
  tagIdGenerator: _FixedTagIds(creationDurabilityStandaloneTagId),
);

/// Полное начальное состояние: готовность, избранное и два тега — уже
/// назначенный другим намерениям и самостоятельный.
CreateIntention creationDurabilityCommand() => CreateIntention.withInitialState(
  title: 'Полное намерение',
  description: '  Подробное\nописание  ',
  readiness: IntentionReadiness.ready,
  favoriteMark: FavoriteMark.favorite,
  tagIds: [creationDurabilityStandaloneTagId, creationDurabilityExistingTagId],
);

TagId _tagId(int number) =>
    (TagId.decode(tagFixtureId(number)) as TagIdDecodingSuccess).id;

final class _FixedIntentionIds implements IntentionIdGenerator {
  const _FixedIntentionIds(this._id);

  final IntentionId _id;

  @override
  IntentionId generate() => _id;
}

final class _FixedTagIds implements TagIdGenerator {
  const _FixedTagIds(this._id);

  final TagId _id;

  @override
  TagId generate() => _id;
}
