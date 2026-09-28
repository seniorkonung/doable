import 'dart:async';

import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/application/personal_graph_repository.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation_id.dart';
import 'package:doable/src/tag/application/tag_assignment_status.dart';
import 'package:doable/src/tag/application/tag_catalog.dart'
    hide TagCatalogPage;
import 'package:doable/src/tag/application/tag_catalog.dart'
    as data
    show TagCatalogPage;
import 'package:doable/src/tag/application/tag_read_result.dart';
import 'package:doable/src/tag/domain/tag.dart';
import 'package:doable/src/tag/domain/tag_id.dart';
import 'package:doable/src/tag/domain/tag_name.dart';
import 'package:doable/src/tag/domain/tag_target.dart';
import 'package:doable/src/tag/presentation/catalog/tag_catalog_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final (relation, language, scale) in [
    (false, 'ru', 1.0),
    (false, 'en', 2.5),
    (true, 'en', 1.0),
    (true, 'ru', 2.5),
  ]) {
    final description =
        '${relation ? 'долговременная связь' : 'намерение'}, $language, текст $scale';

    testWidgets(
      'быстрый выбор сохраняет строки и прокрутку до ответа наблюдения: $description',
      (tester) async {
        final repository = await _showCatalog(
          tester,
          relation: relation,
          language: language,
          scale: scale,
        );
        final list = find.byKey(const ValueKey('tag-catalog-list'));
        final scrollable = find.descendant(
          of: list,
          matching: find.byType(Scrollable),
        );
        final position = tester.state<ScrollableState>(scrollable).position;
        position.jumpTo(280);
        await tester.pump();

        final listBounds = tester.getRect(list);
        final visible = [
          for (final row in repository.rows)
            if (_row(row.tag).evaluate().isNotEmpty &&
                listBounds.contains(tester.getRect(_row(row.tag)).topLeft) &&
                listBounds.contains(tester.getRect(_row(row.tag)).bottomLeft))
              row,
        ];
        expect(visible.length, greaterThanOrEqualTo(2));
        expect(visible.take(2).map((row) => row.isAssigned).toSet(), {
          false,
          true,
        });
        final bounds = {
          for (final row in visible) row.tag.id: tester.getRect(_row(row.tag)),
        };
        final pixels = position.pixels;

        for (final row in [
          visible[0],
          visible[1],
          visible[0],
          visible[1],
          visible[0],
          visible[0],
          visible[1],
        ]) {
          await tester.tap(_row(row.tag));
          for (final duration in [
            Duration.zero,
            const Duration(milliseconds: 16),
            const Duration(milliseconds: 48),
          ]) {
            await tester.pump(duration);
            expect(
              tester.getRect(list),
              listBounds,
              reason: 'Выбор загруженного тега не меняет границы списка.',
            );
            expect(
              tester.state<ScrollableState>(scrollable).position,
              same(position),
            );
            expect(position.pixels, pixels);
            for (final visibleRow in visible) {
              expect(_row(visibleRow.tag), findsOneWidget);
              expect(
                tester.getRect(_row(visibleRow.tag)),
                bounds[visibleRow.tag.id],
              );
            }
            expect(find.byType(CircularProgressIndicator), findsNothing);
            expect(
              tester.widget<Semantics>(_row(row.tag)).properties.selected,
              isTrue,
            );
            final assign = find.byKey(const ValueKey('tag-catalog-assign'));
            expect(assign, findsOneWidget);
            expect(
              tester.widget<FilledButton>(assign).onPressed,
              row.isAssigned ? isNull : isNotNull,
            );
            expect(repository.catalogModes, hasLength(1));
            expect(repository.assignmentReads, 0);
            expect(repository.commandCount, 0);
            expect(tester.takeException(), isNull);
          }
        }
      },
    );

    testWidgets(
      'область назначения присутствует и отключена до выбора: $description',
      (tester) async {
        final repository = await _showCatalog(
          tester,
          relation: relation,
          language: language,
          scale: scale,
        );
        final assign = find.byKey(const ValueKey('tag-catalog-assign'));
        expect(assign, findsOneWidget);
        expect(tester.widget<FilledButton>(assign).onPressed, isNull);
        expect(repository.commandCount, 0);
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final relation in [false, true]) {
    testWidgets(
      'поздний ответ прежнего выбора не заменяет текущий тег: ${relation ? 'долговременная связь' : 'намерение'}',
      (tester) async {
        final repository = await _showCatalog(
          tester,
          relation: relation,
          language: 'ru',
          scale: 1,
        );
        final first = repository.rows[0].tag;
        final second = repository.rows[1].tag;
        await tester.tap(_row(first));
        await tester.pump();
        final formerObservation = repository.observations[first.id]!.single;
        await tester.tap(_row(second));
        await tester.pump();
        expect(formerObservation.cancelled, isTrue);

        repository.observations[second.id]!.single.deliver(
          TagReadSuccess(
            GraphSnapshot(value: second, revision: const _Revision()),
          ),
        );
        await tester.pump();
        final list = find.byKey(const ValueKey('tag-catalog-list'));
        final listBounds = tester.getRect(list);

        formerObservation.deliver(
          TagReadSuccess(
            GraphSnapshot(
              value: Tag(
                id: first.id,
                name: TagName.fromInput('Поздний ответ'),
              ),
              revision: const _Revision(2),
            ),
          ),
          afterCancellation: true,
        );
        for (final duration in [
          Duration.zero,
          const Duration(milliseconds: 16),
        ]) {
          await tester.pump(duration);
          expect(find.text('Поздний ответ'), findsNothing);
          expect(
            tester.widget<Semantics>(_row(second)).properties.selected,
            isTrue,
          );
          expect(
            tester.widget<Semantics>(_row(first)).properties.selected,
            isFalse,
          );
          expect(tester.getRect(list), listBounds);
          expect(find.byType(CircularProgressIndicator), findsNothing);
          expect(repository.catalogModes, hasLength(1));
          expect(repository.commandCount, 0);
          expect(tester.takeException(), isNull);
        }
      },
    );
  }
}

Future<_ControlledRepository> _showCatalog(
  WidgetTester tester, {
  required bool relation,
  required String language,
  required double scale,
}) async {
  tester.view.physicalSize = const Size(420, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final target = relation
      ? LongTermRelationTagTarget(
          (LongTermRelationId.decode(
            _id(200),
          ) as LongTermRelationIdDecodingSuccess).id,
        )
      : IntentionTagTarget(
          (IntentionId.decode(_id(100)) as IntentionIdDecodingSuccess).id,
        );
  final repository = _ControlledRepository(target);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        personalGraphRepositoryProvider.overrideWithValue(repository),
      ],
      child: MaterialApp(
        locale: Locale(language),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: TagCatalogPage(target: target),
      ),
    ),
  );
  expect(repository.catalogModes, [TagCatalogSelectionMode(target)]);
  repository.catalogRead.complete(
    TagCatalogPageSuccess(
      data.TagCatalogPage.selection(
        target: target,
        rows: repository.rows,
        pageSize: TagCatalogQuery.defaultPageSize,
        nextCursor: null,
        revision: const _Revision(),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
  expect(find.byKey(const ValueKey('tag-catalog-list')), findsOneWidget);
  expect(find.byType(CircularProgressIndicator), findsNothing);
  return repository;
}

Finder _row(Tag tag) =>
    find.byKey(ValueKey('tag-catalog-row-${tag.id.toCanonicalString()}'));

String _id(int number) =>
    '018f0b5d-6b2e-7c80-8000-${number.toRadixString(16).padLeft(12, '0')}';

final class _Revision implements GraphRevision {
  const _Revision([this.number = 1]);

  final int number;

  @override
  GraphRevisionOrder compareTo(GraphRevision other) => switch (other) {
    _Revision(number: final value) when number < value =>
      GraphRevisionOrder.older,
    _Revision(number: final value) when number > value =>
      GraphRevisionOrder.newer,
    _Revision() => GraphRevisionOrder.same,
    _ => GraphRevisionOrder.differentEpoch,
  };
}

final class _ControlledRepository extends Fake
    implements PersonalGraphRepository {
  _ControlledRepository(this.target);

  final TagTarget target;
  final rows = [
    for (var index = 1; index <= 32; index++)
      TagSelectionRow(
        tag: Tag(
          id: (TagId.decode(_id(index)) as TagIdDecodingSuccess).id,
          name: TagName.fromInput('Тег $index'),
        ),
        isAssigned: index.isEven,
      ),
  ];
  final catalogRead = Completer<TagCatalogPageResult>();
  final catalogModes = <TagCatalogMode>[];
  final observations = <TagId, List<_ControlledTagSubscription>>{};
  int assignmentReads = 0;
  int commandCount = 0;

  @override
  Future<TagCatalogPageResult> getTagCatalogPage(TagCatalogQuery query) {
    catalogModes.add(query.mode);
    return catalogRead.future;
  }

  @override
  Future<TagAssignmentStatusResult> getTagAssignmentStatus(
    TagId id,
    TagTarget target,
  ) async {
    assignmentReads++;
    return TagAssignmentStatusSuccess(
      GraphSnapshot(
        value: rows.singleWhere((row) => row.tag.id == id).isAssigned,
        revision: const _Revision(),
      ),
    );
  }

  @override
  Stream<TagReadResult> watchTag(TagId id) =>
      _ControlledTagStream(observations.putIfAbsent(id, () => []));

  @override
  Future<GraphCommandResult<TSuccess, TFailure>> execute<
    TSuccess extends GraphCommandOutcome,
    TFailure extends GraphCommandFailure
  >(GraphCommand<TSuccess, TFailure> command) async {
    commandCount++;
    throw StateError('Выбор тега не должен выполнять команду записи.');
  }
}

final class _ControlledTagStream extends Stream<TagReadResult> {
  _ControlledTagStream(this.subscriptions);

  final List<_ControlledTagSubscription> subscriptions;

  @override
  StreamSubscription<TagReadResult> listen(
    void Function(TagReadResult)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    final subscription = _ControlledTagSubscription(onData);
    subscriptions.add(subscription);
    return subscription;
  }
}

final class _ControlledTagSubscription extends Fake
    implements StreamSubscription<TagReadResult> {
  _ControlledTagSubscription(this._onData);

  final void Function(TagReadResult)? _onData;
  bool cancelled = false;

  void deliver(TagReadResult result, {bool afterCancellation = false}) {
    if (!cancelled || afterCancellation) _onData?.call(result);
  }

  @override
  Future<void> cancel() async => cancelled = true;
}
