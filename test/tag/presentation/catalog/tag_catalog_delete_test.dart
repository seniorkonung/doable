import 'dart:async';

import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/application/personal_graph_repository.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:doable/src/graph/presentation/graph_operation_presenter.dart';
import 'package:doable/src/tag/application/tag_catalog.dart';
import 'package:doable/src/tag/application/tag_change.dart';
import 'package:doable/src/tag/application/tag_result.dart';
import 'package:doable/src/tag/domain/tag.dart';
import 'package:doable/src/tag/domain/tag_id.dart';
import 'package:doable/src/tag/domain/tag_name.dart';
import 'package:doable/src/tag/presentation/catalog/tag_catalog_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/ordinary_page_test_app.dart';
import '../../../support/in_memory_quick_creation_mode_store.dart';
import '../../../support/tag_positions.dart';

String _id(int number) =>
    '018f0b5d-6b2e-7c80-8000-${number.toRadixString(16).padLeft(12, '0')}';

TagId _tagId(int number) =>
    (TagId.decode(_id(number)) as TagIdDecodingSuccess).id;

void main() {
  setUp(() {
    WidgetsBinding.instance.handleAppLifecycleStateChanged(
      AppLifecycleState.resumed,
    );
  });

  const locale = Locale('ru');
  const busyMessage =
      'Изменение этого тега уже выполняется. Дождитесь результата.';
  const failureMessage = 'Не удалось выполнить действие с тегом.';

  for (final succeeds in [true, false]) {
    testWidgets(
      'занятое удаление исчезает после ${succeeds ? 'успеха' : 'отказа'}',
      (tester) async {
        final semantics = tester.ensureSemantics();
        final repository = _PendingRepository();
        final container = ProviderContainer(
          overrides: [
            inMemoryQuickCreationModeOverride,
            personalGraphRepositoryProvider.overrideWithValue(repository),
          ],
        );
        addTearDown(container.dispose);
        Widget host(Widget child) => UncontrolledProviderScope(
          container: container,
          child: OrdinaryPageTestApp(
            key: ObjectKey(child),
            locale: locale,
            home: GraphOperationPresenter(child: child),
          ),
        );

        await tester.pumpWidget(host(const TagCatalogPage()));
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(ValueKey('tag-catalog-delete-${_id(301)}')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('tag-delete-confirm')));
        await tester.pump();
        expect(repository.commands, 1);

        await tester.pumpWidget(host(const SizedBox.shrink()));
        await tester.pumpWidget(host(const TagCatalogPage()));
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(ValueKey('tag-catalog-delete-${_id(301)}')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('tag-delete-confirm')));
        await tester.pumpAndSettle();

        final notice = find.text(busyMessage);
        expect(notice, findsOneWidget);
        expect(
          tester.getSemantics(notice),
          isSemantics(label: busyMessage, isLiveRegion: true),
        );
        expect(repository.commands, 1);

        repository.finish(succeeds: succeeds);
        await tester.pumpAndSettle();
        expect(notice, findsNothing);
        if (succeeds) {
          expect(find.byType(SnackBar), findsNothing);
        } else {
          final result = find.textContaining(failureMessage);
          expect(result, findsOneWidget);
          expect(tester.getSemantics(result).label, contains(failureMessage));
        }
        expect(repository.commands, 1);
        semantics.dispose();
      },
    );
  }
}

final class _PendingRepository extends Fake implements PersonalGraphRepository {
  final _pending = Completer<TagCommandResult>();
  int commands = 0;
  bool deleted = false;

  @override
  Future<TagCatalogResult> getTagCatalog(TagCatalogMode mode) async =>
      TagCatalogSuccess(
        TagCatalogSnapshot(
          items: deleted
              ? []
              : [
                  Tag(
                    id: _tagId(301),
                    name: TagName.fromInput('Дом'),
                    color: null,
                    position: tagPositionAt(1000),
                  ),
                ],

          revision: const _Revision(),
        ),
      );

  @override
  Future<GraphCommandResult<TSuccess, TFailure>> execute<
    TSuccess extends GraphCommandOutcome,
    TFailure extends GraphCommandFailure
  >(GraphCommand<TSuccess, TFailure> command) async {
    commands++;
    return await _pending.future as GraphCommandResult<TSuccess, TFailure>;
  }

  void finish({required bool succeeds}) {
    if (succeeds) {
      deleted = true;
      _pending.complete(
        TagCommandSucceeded(
          ConfirmedGraphResult(
            revision: const _Revision(),
            value: TagDeleted(
              TagDeletedChange(revision: const _Revision(), tagId: _tagId(301)),
            ),
          ),
        ),
      );
    } else {
      _pending.complete(const TagCommandFailed(TagUnavailableFailure()));
    }
  }
}

final class _Revision implements GraphRevision {
  const _Revision();
  @override
  GraphRevisionOrder compareTo(GraphRevision other) => GraphRevisionOrder.same;
}
