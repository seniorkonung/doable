import 'dart:async';

import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/src/data/local/app_database.dart' hide Tag;
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/application/personal_graph_repository.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:doable/src/graph/data/drift_personal_graph_repository.dart';
import 'package:doable/src/intention/application/intention_id_generator.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation_id.dart';
import 'package:doable/src/tag/application/tag_assignments_page.dart';
import 'package:doable/src/tag/application/tag_read_result.dart';
import 'package:doable/src/tag/application/tag_result.dart';
import 'package:doable/src/tag/domain/tag.dart';
import 'package:doable/src/tag/domain/tag_id.dart';
import 'package:doable/src/tag/domain/tag_name.dart';
import 'package:doable/src/tag/domain/tag_target.dart';
import 'package:doable/src/tag/presentation/assignments/tag_assignments_section.dart';
import 'package:doable/src/tag/presentation/assignments/tag_assignments_view_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../../../support/in_memory_diagnostics_sink.dart';
import '../../../support/tag_storage_fixture.dart';

TagId _tagId(int number) =>
    (TagId.decode(tagFixtureId(number)) as TagIdDecodingSuccess).id;

TagTarget _target(int number) => IntentionTagTarget(
  (IntentionId.decode(tagFixtureId(number)) as IntentionIdDecodingSuccess).id,
);

TagTarget _relationTarget(int number) => LongTermRelationTagTarget(
  (LongTermRelationId.decode(
    tagFixtureId(number),
  ) as LongTermRelationIdDecodingSuccess).id,
);

Widget _host({
  required PersonalGraphRepository repository,
  required TagTarget target,
  required Locale locale,
  required ValueChanged<TagTarget> onChoose,
  TagReadContract? reads,
  bool largeText = false,
  bool isArchived = false,
}) => ProviderScope(
  overrides: [
    personalGraphRepositoryProvider.overrideWithValue(repository),
    if (reads != null) tagAssignmentsReaderProvider.overrideWithValue(reads),
  ],
  child: MaterialApp(
    locale: locale,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    builder: largeText
        ? (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(3)),
            child: child!,
          )
        : null,
    home: Scaffold(
      body: SingleChildScrollView(
        child: TagAssignmentsSection(
          target: target,
          isArchived: isArchived,
          onChooseTag: onChoose,
        ),
      ),
    ),
  ),
);

void main() {
  late AppDatabase database;
  late sqlite.Database raw;
  late DriftPersonalGraphRepository repository;

  setUp(() async {
    database = AppDatabase(openInMemoryLocalDatabase(setup: (db) => raw = db));
    await database.open();
    seedTagStorageFixture(raw);
    repository = DriftPersonalGraphRepository(
      database,
      UuidV7IntentionIdGenerator(),
      () => DateTime.utc(2026, 9, 27),
      InMemoryDiagnosticsSink(),
    );
  });
  tearDown(() => database.close());

  for (final (locale, chooseText, removeText) in [
    (const Locale('ru'), 'Выбрать тег', 'Снять назначение'),
    (const Locale('en'), 'Choose a tag', 'Remove assignment'),
  ]) {
    testWidgets(
      'снятие последнего назначения сохраняет тег и показывает пустой список: ${locale.languageCode}',
      (tester) async {
        final semantics = tester.ensureSemantics();
        final chosen = <TagTarget>[];
        await tester.pumpWidget(
          _host(
            repository: repository,
            target: _target(3),
            locale: locale,
            onChoose: chosen.add,
          ),
        );
        await _pumpUntil(
          tester,
          () => find.text('Работа').evaluate().isNotEmpty,
        );
        expect(find.text('Работа'), findsOneWidget);
        expect(find.text(chooseText), findsOneWidget);
        expect(find.byTooltip('$removeText: Работа'), findsOneWidget);
        await tester.tap(find.text(chooseText));
        expect(chosen, [_target(3)]);
        await tester.tap(find.byTooltip('$removeText: Работа'));
        await _pumpUntil(
          tester,
          () => raw.select(
            'SELECT * FROM tag_assignments WHERE intention_id = ?',
            [tagFixtureId(3)],
          ).isEmpty,
        );
        expect(raw.select('SELECT * FROM tags'), hasLength(2));
        expect(
          raw.select('SELECT * FROM tag_assignments WHERE intention_id = ?', [
            tagFixtureId(3),
          ]),
          isEmpty,
        );
        expect(find.text('Работа'), findsNothing);
        expect(find.text(chooseText), findsOneWidget);
        semantics.dispose();
      },
    );
  }

  testWidgets('архивная долговременная связь снимает только своё назначение', (
    tester,
  ) async {
    final target = _relationTarget(102);
    final chosen = <TagTarget>[];
    await tester.pumpWidget(
      _host(
        repository: repository,
        target: target,
        locale: const Locale('ru'),
        onChoose: chosen.add,
        isArchived: true,
      ),
    );
    await _pumpUntil(tester, () => find.text('Дом').evaluate().isNotEmpty);
    expect(
      find.byTooltip(
        'Выбрать тег для получателя: долговременная связь, в архиве',
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Выбрать тег'));
    expect(chosen, [target]);
    await tester.tap(find.byTooltip('Снять назначение: Дом'));
    await _pumpUntil(
      tester,
      () => raw.select(
        'SELECT * FROM tag_assignments WHERE long_term_relation_id = ?',
        [tagFixtureId(102)],
      ).isEmpty,
    );
    expect(raw.select('SELECT * FROM tags'), hasLength(2));
    expect(
      raw.select(
        'SELECT * FROM tag_assignments WHERE long_term_relation_id = ?',
        [tagFixtureId(101)],
      ),
      hasLength(1),
    );
  });

  testWidgets('подгрузка сохраняет строки при отказе и даёт явный повтор', (
    tester,
  ) async {
    final reads = _PendingReads();
    await tester.pumpWidget(
      _host(
        repository: repository,
        target: _target(1),
        locale: const Locale('ru'),
        onChoose: (_) {},
        reads: reads,
      ),
    );
    expect(find.text('Загружаем назначения…'), findsOneWidget);
    final cursor = _Cursor();
    reads.page(0, [_tag(301, 'Дом')], cursor: cursor);
    await tester.pumpAndSettle();
    expect(find.text('Дом'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('tag-assignments-load-more')));
    await tester.pump();
    expect(find.text('Загружаем ещё назначения…'), findsOneWidget);
    reads.fail(1, const TagAssignmentsUnavailableFailure());
    await tester.pumpAndSettle();
    expect(find.text('Дом'), findsOneWidget);
    await tester.tap(find.text('Повторить'));
    await tester.pump();
    expect(reads.queries[2].cursor, same(cursor));
    reads.page(2, [_tag(302, 'Работа')]);
    await tester.pumpAndSettle();
    expect(find.text('Работа'), findsOneWidget);
  });

  testWidgets('отсутствие получателя не предлагает повтор', (tester) async {
    final reads = _PendingReads();
    await tester.pumpWidget(
      _host(
        repository: repository,
        target: _target(1),
        locale: const Locale('ru'),
        onChoose: (_) {},
        reads: reads,
      ),
    );
    reads.fail(0, const TagAssignmentsTargetNotFound());
    await tester.pumpAndSettle();
    expect(find.textContaining('получателя больше нет'), findsOneWidget);
    expect(find.text('Повторить'), findsNothing);
  });

  testWidgets(
    'повреждение не предлагает обычный повтор, недоступность предлагает',
    (tester) async {
      final reads = _PendingReads();
      await tester.pumpWidget(
        _host(
          repository: repository,
          target: _target(1),
          locale: const Locale('ru'),
          onChoose: (_) {},
          reads: reads,
        ),
      );
      reads.fail(0, const TagAssignmentsUnavailableFailure());
      await tester.pumpAndSettle();
      expect(find.text('Повторить'), findsOneWidget);
      await tester.tap(find.text('Повторить'));
      await tester.pump();
      reads.fail(1, const TagAssignmentsCorruptionFailure());
      await tester.pumpAndSettle();
      expect(find.textContaining('повреждены'), findsOneWidget);
      expect(find.text('Повторить'), findsNothing);
    },
  );

  testWidgets('отказ снятия показан общим инлайн-предъявлением', (
    tester,
  ) async {
    final reads = _PendingReads();
    await tester.pumpWidget(
      _host(
        repository: _FailingRepository(),
        target: _target(1),
        locale: const Locale('ru'),
        onChoose: (_) {},
        reads: reads,
      ),
    );
    reads.page(0, [_tag(301, 'Дом')]);
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(ValueKey('tag-assignment-remove-${tagFixtureId(301)}')),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('tag-assignments-remove-failure')),
      findsOneWidget,
    );
    expect(find.textContaining('Повторите попытку'), findsOneWidget);
    expect(find.text('Дом'), findsOneWidget);
  });

  testWidgets(
    'архивный контекст и длинное название доступны при большом тексте',
    (tester) async {
      final semantics = tester.ensureSemantics();
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      final reads = _PendingReads();
      final target = _target(1);
      await tester.pumpWidget(
        _host(
          repository: repository,
          target: target,
          locale: const Locale('ru'),
          onChoose: (_) {},
          reads: reads,
          largeText: true,
          isArchived: true,
        ),
      );
      final longName = 'Очень длинное название тега ' * 8;
      reads.page(0, [_tag(301, longName)]);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(
        find.bySemanticsLabel('Назначения тегов: намерение, в архиве'),
        findsOneWidget,
      );
      await tester.ensureVisible(
        find.byKey(ValueKey('tag-assignment-remove-${tagFixtureId(301)}')),
      );
      await tester.pump();
      expect(
        find.byTooltip('Снять назначение: ${longName.trim()}'),
        findsOneWidget,
      );
      semantics.dispose();
    },
  );
}

final class _PendingReads extends Fake implements TagReadContract {
  final queries = <TagAssignmentsQuery>[];
  final pages = <Completer<TagAssignmentsPageResult>>[];

  @override
  Future<TagAssignmentsPageResult> getTagAssignmentsPage(
    TagAssignmentsQuery query,
  ) {
    queries.add(query);
    final page = Completer<TagAssignmentsPageResult>();
    pages.add(page);
    return page.future;
  }

  void page(int index, List<Tag> tags, {TagAssignmentsCursor? cursor}) {
    pages[index].complete(
      TagAssignmentsPageSuccess(
        TagAssignmentsPage(
          target: queries[index].target,
          items: tags,
          pageSize: queries[index].pageSize,
          nextCursor: cursor,
          revision: const _Revision(),
        ),
      ),
    );
  }

  void fail(int index, TagAssignmentsReadFailure failure) =>
      pages[index].complete(TagAssignmentsPageError(failure));
}

final class _Cursor implements TagAssignmentsCursor {}

final class _Revision implements GraphRevision {
  const _Revision();

  @override
  GraphRevisionOrder compareTo(GraphRevision other) => GraphRevisionOrder.same;
}

final class _FailingRepository extends Fake implements PersonalGraphRepository {
  @override
  Future<GraphCommandResult<TSuccess, TFailure>> execute<
    TSuccess extends GraphCommandOutcome,
    TFailure extends GraphCommandFailure
  >(GraphCommand<TSuccess, TFailure> command) async =>
      const TagCommandFailed(TagUnavailableFailure())
          as GraphCommandResult<TSuccess, TFailure>;
}

Tag _tag(int number, String name) =>
    Tag(id: _tagId(number), name: TagName.fromInput(name));

Future<void> _pumpUntil(WidgetTester tester, bool Function() done) async {
  for (var attempt = 0; attempt < 30 && !done(); attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }
  expect(done(), isTrue);
}
