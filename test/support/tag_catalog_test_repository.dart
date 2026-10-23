import 'dart:async';

import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/application/personal_graph_repository.dart';
import 'package:doable/src/intention/application/intention_catalog.dart';
import 'package:doable/src/intention/application/intention_result.dart';
import 'package:doable/src/tag/application/tag_catalog.dart';
import 'package:doable/src/tag/application/tag_read_result.dart';
import 'package:doable/src/tag/application/tag_result.dart';
import 'package:doable/src/tag/domain/tag.dart';
import 'package:doable/src/tag/domain/tag_id.dart';
import 'package:flutter_test/flutter_test.dart';

final class TagCatalogTestRevision implements GraphRevision {
  const TagCatalogTestRevision([this.number = 1]);

  final int number;

  @override
  GraphRevisionOrder compareTo(GraphRevision other) => switch (other) {
    TagCatalogTestRevision(number: final value) when number < value =>
      GraphRevisionOrder.older,
    TagCatalogTestRevision(number: final value) when number > value =>
      GraphRevisionOrder.newer,
    TagCatalogTestRevision() => GraphRevisionOrder.same,
    _ => GraphRevisionOrder.differentEpoch,
  };
}

final class TagCatalogTestRepository extends Fake
    implements PersonalGraphRepository {
  final reads = <Completer<TagCatalogResult>>[];
  final readModes = <TagCatalogMode>[];
  final commands = <GraphCommand<GraphCommandOutcome, GraphCommandFailure>>[];

  /// Результаты команд в порядке исполнения: каждая команда ждёт свой.
  final commandResults = <Completer<TagCommandResult>>[];
  final observations = <TagId, StreamController<TagReadResult>>{};

  @override
  Future<GraphCommandResult<TSuccess, TFailure>> execute<
    TSuccess extends GraphCommandOutcome,
    TFailure extends GraphCommandFailure
  >(GraphCommand<TSuccess, TFailure> command) async {
    commands.add(command);
    final result = Completer<TagCommandResult>();
    commandResults.add(result);
    return await result.future as GraphCommandResult<TSuccess, TFailure>;
  }

  /// Результат последней исполняемой команды.
  Completer<TagCommandResult> get command => commandResults.last;

  @override
  Stream<TagReadResult> watchTag(TagId id) => observations
      .putIfAbsent(id, () => StreamController<TagReadResult>.broadcast())
      .stream;

  void observe(Tag? tag, {TagId? id, int revision = 1}) =>
      observations[tag?.id ?? id]!.add(
        TagReadSuccess(
          GraphSnapshot(value: tag, revision: TagCatalogTestRevision(revision)),
        ),
      );

  Future<void> dispose() async {
    for (final observation in observations.values) {
      await observation.close();
    }
  }

  /// Запросы выдачи поиска намерений, над условиями которого открыта панель
  /// фильтра. Выдача не завершается: проверки панели читают только запросы.
  final catalogQueries = <IntentionCatalogQuery>[];

  @override
  Future<Result<IntentionCatalogPage>> getCatalogPage(
    IntentionCatalogQuery query,
  ) {
    catalogQueries.add(query);
    return Completer<Result<IntentionCatalogPage>>().future;
  }

  @override
  Future<TagCatalogResult> getTagCatalog(TagCatalogMode mode) {
    final read = Completer<TagCatalogResult>();
    reads.add(read);
    readModes.add(mode);
    return read.future;
  }

  void fail(TagCatalogReadFailure failure) =>
      reads.last.complete(TagCatalogError(failure));

  void complete(List<Tag> tags, {int revision = 1, Set<TagId>? assignedIds}) =>
      reads.last.complete(
        TagCatalogSuccess(switch (readModes.last) {
          TagCatalogBrowseMode() => TagCatalogSnapshot(
            items: tags,
            revision: TagCatalogTestRevision(revision),
          ),
          TagCatalogSelectionMode(:final intentionId) =>
            TagCatalogSnapshot.selection(
              intentionId: intentionId,
              rows: [
                for (var index = 0; index < tags.length; index++)
                  TagSelectionRow(
                    tag: tags[index],
                    isAssigned:
                        assignedIds?.contains(tags[index].id) ?? index.isOdd,
                  ),
              ],
              revision: TagCatalogTestRevision(revision),
            ),
        }),
      );
}
