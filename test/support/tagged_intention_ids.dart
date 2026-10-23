import 'package:doable/src/graph/application/personal_graph_repository.dart';
import 'package:doable/src/intention/application/intention_catalog.dart';
import 'package:doable/src/intention/application/intention_result.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/tag/domain/tag_id.dart';
import 'package:flutter_test/flutter_test.dart';

/// Намерения охвата с тегом по выдаче каталога намерений с условием
/// «должен быть» по этому тегу, собранные по всем порциям.
Future<Set<IntentionId>> readTaggedIntentionIds(
  PersonalGraphRepository repository,
  TagId tagId,
  IntentionScope scope,
) async {
  final ids = <IntentionId>{};
  IntentionCatalogCursor? cursor;
  do {
    final result = await repository.getCatalogPage(
      IntentionCatalogQuery(
        scope: scope,
        titleFilter: null,
        tagFilter: IntentionTagFilter(requiredTagIds: [tagId]),
        order: IntentionCatalogOrder.createdAtAscending,
        pageSize: IntentionCatalogQuery.maxPageSize,
        cursor: cursor,
      ),
    );
    final page = switch (result) {
      ResultSuccess(:final value) => value,
      ResultFailure(:final failure) => throw TestFailure(
        'Ожидался успех выдачи по тегу, получен отказ $failure.',
      ),
    };
    ids.addAll(page.items.map((item) => item.id));
    cursor = page.nextCursor;
  } while (cursor != null);
  return ids;
}
