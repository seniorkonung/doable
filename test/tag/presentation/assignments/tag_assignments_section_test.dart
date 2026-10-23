import 'dart:async';

import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/src/data/local/app_database.dart'
    hide Tag, TagAssignment;
import 'package:doable/src/design_system/components/tag_dot.dart';
import 'package:doable/src/design_system/doable_colors.dart';
import 'package:doable/src/graph/application/graph_command_coordinator.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/application/personal_graph_repository.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:doable/src/graph/data/drift_personal_graph_repository.dart';
import 'package:doable/src/intention/application/intention_id_generator.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/tag/application/tag_assignments.dart';
import 'package:doable/src/tag/application/tag_change.dart';
import 'package:doable/src/tag/application/tag_command.dart';
import 'package:doable/src/tag/application/tag_read_result.dart';
import 'package:doable/src/tag/application/tag_result.dart';
import 'package:doable/src/tag/domain/tag.dart';
import 'package:doable/src/tag/domain/tag_assignment.dart';
import 'package:doable/src/tag/domain/tag_color.dart';
import 'package:doable/src/tag/domain/tag_id.dart';
import 'package:doable/src/tag/domain/tag_name.dart';
import 'package:doable/src/tag/presentation/assignments/tag_assignments_section.dart';
import 'package:doable/src/tag/presentation/assignments/tag_assignments_view_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../../../support/in_memory_diagnostics_sink.dart';
import '../../../support/tag_storage_fixture.dart';
import '../../../support/tag_assignment_changed.dart';
import '../../../support/tag_positions.dart';

TagId _tagId(int number) =>
    (TagId.decode(tagFixtureId(number)) as TagIdDecodingSuccess).id;

IntentionId _intentionId(int number) =>
    (IntentionId.decode(tagFixtureId(number)) as IntentionIdDecodingSuccess).id;

Widget _host({
  required PersonalGraphRepository repository,
  required IntentionId intentionId,
  required Locale locale,
  required ValueChanged<IntentionId> onChoose,
  TagReadContract? reads,
  Stream<ConfirmedGraphChangePackage>? changes,

  bool isArchived = false,
  bool showSection = true,
}) => ProviderScope(
  overrides: [
    personalGraphRepositoryProvider.overrideWithValue(repository),
    if (reads != null) tagAssignmentsReaderProvider.overrideWithValue(reads),
    if (changes != null)
      tagAssignmentsChangesProvider.overrideWithValue(changes),
  ],
  child: MaterialApp(
    locale: locale,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: SingleChildScrollView(
        child: showSection
            ? TagAssignmentsSection(
                intentionId: intentionId,
                isArchived: isArchived,
                onChooseTag: onChoose,
              )
            : const SizedBox.shrink(),
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

  testWidgets('назначения показывают точку и кольцо перед названиями', (
    tester,
  ) async {
    final reads = _PendingReads();
    await tester.pumpWidget(
      _host(
        repository: repository,
        intentionId: _intentionId(1),
        locale: const Locale('ru'),
        onChoose: (_) {},
        reads: reads,
      ),
    );
    reads.page(0, [
      _tag(301, 'Дом', color: TagColor.blue),
      _tag(302, 'Работа'),
    ]);
    await tester.pumpAndSettle();

    for (final (number, name, color, style) in [
      (301, 'Дом', DoableColors.light.tagBlue, PaintingStyle.fill),
      (302, 'Работа', DoableColors.light.grip, PaintingStyle.stroke),
    ]) {
      final title = find.text(name);
      final row = find.byKey(
        ValueKey('tag-assignment-row-${tagFixtureId(number)}'),
      );
      final dot = find.descendant(of: row, matching: find.byType(TagDot));
      expect(dot, findsOneWidget);
      expect(tester.getSize(dot), const Size.square(8));
      expect(tester.getTopRight(dot).dx, lessThan(tester.getTopLeft(title).dx));
      expect(
        tester.renderObject(dot),
        paints..circle(color: color, style: style),
      );
      final text = tester.widget<RichText>(
        find.descendant(of: title, matching: find.byType(RichText)),
      );
      expect(
        text.text.style!.color,
        Theme.of(tester.element(title)).textTheme.bodyMedium!.color,
      );
    }
  });

  for (final (locale, removeText) in [
    (const Locale('ru'), 'Снять назначение'),
    (const Locale('en'), 'Remove assignment'),
  ]) {
    testWidgets(
      'строка назначения показывает точку, название и снятие без перехода к тегу: ${locale.languageCode}',
      (tester) async {
        final semantics = tester.ensureSemantics();
        await tester.pumpWidget(
          _host(
            repository: repository,
            intentionId: _intentionId(1),
            locale: locale,
            onChoose: (_) {},
          ),
        );
        final row = find.byKey(
          ValueKey('tag-assignment-row-${tagFixtureId(firstTagNumber)}'),
        );
        await _pumpUntil(tester, () => row.evaluate().isNotEmpty);
        expect(
          find.descendant(of: row, matching: find.byType(TagDot)),
          findsOneWidget,
        );
        expect(
          find.descendant(of: row, matching: find.text('Дом')),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: row,
            matching: find.byWidgetPredicate(
              (widget) => widget is ButtonStyleButton,
            ),
          ),
          findsOneWidget,
        );
        final remove = find.descendant(
          of: row,
          matching: find.byTooltip('$removeText: Дом'),
        );
        expect(remove, findsOneWidget);
        expect(tester.getSemantics(remove).tooltip, '$removeText: Дом');
        expect(find.byIcon(Icons.arrow_forward), findsNothing);
        semantics.dispose();
      },
    );
  }

  testWidgets(
    'снятие последнего назначения сохраняет тег и показывает пустой список',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final chosen = <IntentionId>[];
      await tester.pumpWidget(
        _host(
          repository: repository,
          intentionId: _intentionId(3),
          locale: const Locale('ru'),
          onChoose: chosen.add,
        ),
      );
      await _pumpUntil(tester, () => find.text('Работа').evaluate().isNotEmpty);
      expect(find.text('Работа'), findsOneWidget);
      expect(find.text('Выбрать тег'), findsOneWidget);
      expect(find.byTooltip('Снять назначение: Работа'), findsOneWidget);
      await tester.tap(find.text('Выбрать тег'));
      expect(chosen, [_intentionId(3)]);
      await tester.tap(find.byTooltip('Снять назначение: Работа'));
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
      expect(find.text('Выбрать тег'), findsOneWidget);
      semantics.dispose();
    },
  );

  testWidgets('архивированное действие снимает только своё назначение', (
    tester,
  ) async {
    final intentionId = _intentionId(2);
    final chosen = <IntentionId>[];
    await tester.pumpWidget(
      _host(
        repository: repository,
        intentionId: intentionId,
        locale: const Locale('ru'),
        onChoose: chosen.add,
        isArchived: true,
      ),
    );
    await _pumpUntil(tester, () => find.text('Дом').evaluate().isNotEmpty);
    expect(
      find.byTooltip('Выбрать тег для получателя: намерение, в архиве'),
      findsOneWidget,
    );
    await tester.tap(find.text('Выбрать тег'));
    expect(chosen, [intentionId]);
    await tester.tap(find.byTooltip('Снять назначение: Дом'));
    await _pumpUntil(
      tester,
      () => raw.select('SELECT * FROM tag_assignments WHERE intention_id = ?', [
        tagFixtureId(2),
      ]).isEmpty,
    );
    expect(raw.select('SELECT * FROM tags'), hasLength(2));
    expect(
      raw.select('SELECT * FROM tag_assignments WHERE intention_id = ?', [
        tagFixtureId(1),
      ]),
      hasLength(1),
    );
  });

  testWidgets('актуализация сохраняет строки при отказе и даёт явный повтор', (
    tester,
  ) async {
    final reads = _PendingReads();
    final chosen = <IntentionId>[];
    final changes = StreamController<ConfirmedGraphChangePackage>.broadcast(
      sync: true,
    );
    addTearDown(changes.close);
    await tester.pumpWidget(
      _host(
        repository: repository,
        intentionId: _intentionId(1),
        locale: const Locale('ru'),
        onChoose: chosen.add,
        reads: reads,
        changes: changes.stream,
      ),
    );
    expect(find.text('Загружаем назначения…'), findsOneWidget);
    reads.page(0, [_tag(301, 'Дом')]);
    await tester.pumpAndSettle();
    expect(find.text('Дом'), findsOneWidget);
    final previousChoose = tester
        .widget<TextButton>(
          find.byKey(const ValueKey('tag-assignments-choose')),
        )
        .onPressed!;
    changes.add(
      _Package(const _Revision(1), [
        TagDeletedChange(revision: const _Revision(1), tagId: _tagId(302)),
      ]),
    );
    previousChoose();
    expect(chosen, isEmpty);
    await tester.pump();
    expect(find.text('Дом'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('tag-assignments-load-more')),
      findsNothing,
    );
    reads.fail(1, const TagAssignmentsUnavailableFailure());
    await tester.pumpAndSettle();
    previousChoose();
    expect(chosen, isEmpty);
    expect(find.text('Дом'), findsOneWidget);
    await tester.tap(find.text('Повторить'));
    await tester.pump();
    expect(reads.queries, [_intentionId(1), _intentionId(1), _intentionId(1)]);
    reads.page(2, [_tag(301, 'Дом'), _tag(302, 'Работа')], revision: 1);
    await tester.pumpAndSettle();
    expect(find.text('Работа'), findsOneWidget);
  });

  testWidgets('отсутствие намерения не предлагает повтор', (tester) async {
    final reads = _PendingReads();
    await tester.pumpWidget(
      _host(
        repository: repository,
        intentionId: _intentionId(1),
        locale: const Locale('ru'),
        onChoose: (_) {},
        reads: reads,
      ),
    );
    reads.fail(0, const TagAssignmentsIntentionNotFound());
    await tester.pumpAndSettle();
    expect(find.textContaining('намерения больше нет'), findsOneWidget);
    expect(find.text('Повторить'), findsNothing);
  });

  testWidgets(
    'повреждение не предлагает обычный повтор, недоступность предлагает',
    (tester) async {
      final reads = _PendingReads();
      await tester.pumpWidget(
        _host(
          repository: repository,
          intentionId: _intentionId(1),
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

  testWidgets('отказ снятия принадлежит общей поверхности, а секция его не '
      'рисует', (tester) async {
    final reads = _PendingReads();
    await tester.pumpWidget(
      _host(
        repository: _FailingRepository(),
        intentionId: _intentionId(1),
        locale: const Locale('ru'),
        onChoose: (_) {},
        reads: reads,
      ),
    );
    reads.page(0, [_tag(301, 'Дом')]);
    await tester.pumpAndSettle();
    final coordinator = ProviderScope.containerOf(
      tester.element(find.byType(TagAssignmentsSection)),
    ).read(graphCommandCoordinatorProvider.notifier);
    final registration = coordinator.registerAppPresentation();
    addTearDown(registration.release);
    GraphAppPresentationClaim? app;
    unawaited(registration.nextClaim().then((claim) => app = claim));

    await tester.tap(
      find.byKey(ValueKey('tag-assignment-remove-${tagFixtureId(301)}')),
    );
    await tester.pumpAndSettle();

    expect(app?.completions.single.isFailure, isTrue);
    expect(
      find.byKey(const ValueKey('tag-assignments-remove-failure')),
      findsNothing,
    );
    expect(find.textContaining('Повторите попытку'), findsNothing);
    expect(find.text('Дом'), findsOneWidget);
  });

  testWidgets('прежние действия не применяются к другому намерению', (
    tester,
  ) async {
    final reads = _PendingReads();
    final pending = _PendingRepository();
    final chosen = <IntentionId>[];
    Widget host(IntentionId intentionId) => _host(
      repository: pending,
      intentionId: intentionId,
      locale: const Locale('ru'),
      onChoose: chosen.add,
      reads: reads,
    );
    await tester.pumpWidget(host(_intentionId(1)));
    reads.page(0, [_tag(301, 'Дом')]);
    await tester.pumpAndSettle();
    final previousChoose = tester
        .widget<TextButton>(
          find.byKey(const ValueKey('tag-assignments-choose')),
        )
        .onPressed!;
    final previousRemove = tester
        .widget<TextButton>(
          find.byKey(ValueKey('tag-assignment-remove-${tagFixtureId(301)}')),
        )
        .onPressed!;

    await tester.pumpWidget(host(_intentionId(2)));
    reads.page(1, [_tag(301, 'Дом')]);
    await tester.pumpAndSettle();
    previousChoose();
    previousRemove();
    expect(chosen, isEmpty);
    expect(pending.commands, isEmpty);
    await tester.tap(find.byKey(const ValueKey('tag-assignments-choose')));
    expect(chosen, [_intentionId(2)]);
  });

  testWidgets(
    'позднее чтение другой страницы не заменяет назначения намерения',
    (tester) async {
      final reads = _PendingReads();
      final chosen = <IntentionId>[];
      Widget host(IntentionId intentionId) => _host(
        repository: repository,
        intentionId: intentionId,
        locale: const Locale('ru'),
        onChoose: chosen.add,
        reads: reads,
      );
      await tester.pumpWidget(host(_intentionId(1)));
      await tester.pumpWidget(host(_intentionId(2)));
      expect(reads.queries, [_intentionId(1), _intentionId(2)]);
      reads.page(1, [_tag(302, 'Работа')]);
      await tester.pumpAndSettle();
      reads.page(0, [_tag(301, 'Дом')]);
      await tester.pumpAndSettle();
      expect(find.text('Работа'), findsOneWidget);
      expect(find.text('Дом'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('tag-assignments-choose')));
      expect(chosen, [_intentionId(2)]);
    },
  );

  for (final succeeds in [false, true]) {
    testWidgets(
      'снятие после ухода завершается, а предъявляется только отказ: ${succeeds ? 'успех' : 'отказ'}',
      (tester) async {
        final pending = _PendingRepository();
        final reads = _PendingReads();
        Widget host({bool showSection = true}) => _host(
          repository: pending,
          intentionId: _intentionId(1),
          locale: const Locale('ru'),
          onChoose: (_) {},
          reads: reads,
          showSection: showSection,
        );
        await tester.pumpWidget(host());
        reads.page(0, [_tag(301, 'Дом')]);
        await tester.pumpAndSettle();
        final container = ProviderScope.containerOf(
          tester.element(find.byType(TagAssignmentsSection)),
        );
        final coordinator = container.read(
          graphCommandCoordinatorProvider.notifier,
        );
        final registration = coordinator.registerAppPresentation();
        final claims = <GraphAppPresentationClaim?>[];
        unawaited(registration.nextClaim().then(claims.add));
        await tester.tap(
          find.byKey(ValueKey('tag-assignment-remove-${tagFixtureId(301)}')),
        );
        await tester.pump();
        expect(pending.commands.single.intentionId, _intentionId(1));
        expect(pending.commands.single.tagId, _tagId(301));
        expect(coordinator.isRunning(_intentionId(1)), isTrue);
        expect(
          tester
              .widget<TextButton>(
                find.byKey(const ValueKey('tag-assignments-choose')),
              )
              .onPressed,
          isNull,
        );

        await tester.pumpWidget(host(showSection: false));
        expect(coordinator.isRunning(_intentionId(1)), isTrue);
        if (succeeds) {
          pending.result.complete(
            TagCommandSucceeded(
              ConfirmedGraphResult(
                revision: const _Revision(1),
                value: testTagAssignmentChanged(
                  TagAssignmentChangedChange(
                    revision: const _Revision(1),
                    assignment: TagAssignment(
                      tagId: _tagId(301),
                      intentionId: _intentionId(1),
                    ),
                    state: TagAssignmentState.absent,
                  ),
                ),
              ),
            ),
          );
        } else {
          pending.result.complete(
            const TagCommandFailed(TagUnavailableFailure()),
          );
        }
        await tester.pumpAndSettle();
        expect(
          claims.map((claim) => claim?.completions.single.isFailure),
          succeeds ? isEmpty : [isTrue],
        );
        expect(coordinator.isRunning(_intentionId(1)), isFalse);

        await tester.pumpWidget(host());
        reads.page(
          reads.pages.length - 1,
          succeeds ? [] : [_tag(301, 'Дом')],
          revision: 1,
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('tag-assignments-remove-failure')),
          findsNothing,
        );
        expect(find.text('Дом'), succeeds ? findsNothing : findsOneWidget);
        if (claims.singleOrNull case final claim?) {
          coordinator.confirmAppPresentation(
            claim,
            claim.completions.map((completion) => completion.token),
          );
          var repeated = false;
          final nextClaim = registration.nextClaim().then((value) {
            repeated = value != null;
          });
          await tester.pump();
          expect(repeated, isFalse);
          registration.release();
          await nextClaim;
        } else {
          registration.release();
        }
        expect(pending.commands, hasLength(1));
      },
    );
  }

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
      final intentionId = _intentionId(1);
      await tester.pumpWidget(
        _host(
          repository: repository,
          intentionId: intentionId,
          locale: const Locale('ru'),
          onChoose: (_) {},
          reads: reads,
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
  final queries = <IntentionId>[];
  final pages = <Completer<TagAssignmentsResult>>[];

  @override
  Future<TagAssignmentsResult> getTagAssignments(IntentionId intentionId) {
    queries.add(intentionId);
    final page = Completer<TagAssignmentsResult>();
    pages.add(page);
    return page.future;
  }

  void page(int index, List<Tag> tags, {int revision = 0}) {
    pages[index].complete(
      TagAssignmentsSuccess(
        TagAssignmentsSnapshot(
          intentionId: queries[index],
          items: tags,

          revision: _Revision(revision),
        ),
      ),
    );
  }

  void fail(int index, TagAssignmentsReadFailure failure) =>
      pages[index].complete(TagAssignmentsError(failure));
}

final class _Package implements ConfirmedGraphChangePackage {
  const _Package(this.revision, this.changes);

  @override
  final GraphRevision revision;
  @override
  final List<GraphChange> changes;
}

final class _Revision implements GraphRevision {
  const _Revision(this.number);

  final int number;

  @override
  GraphRevisionOrder compareTo(GraphRevision other) => switch (other) {
    _Revision(number: final n) when number < n => GraphRevisionOrder.older,
    _Revision(number: final n) when number > n => GraphRevisionOrder.newer,
    _Revision() => GraphRevisionOrder.same,
    _ => GraphRevisionOrder.differentEpoch,
  };
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

final class _PendingRepository extends Fake implements PersonalGraphRepository {
  final commands = <RemoveTagAssignment>[];
  final result = Completer<TagCommandResult>();

  @override
  Future<GraphCommandResult<TSuccess, TFailure>> execute<
    TSuccess extends GraphCommandOutcome,
    TFailure extends GraphCommandFailure
  >(GraphCommand<TSuccess, TFailure> command) async {
    expect(command, isA<RemoveTagAssignment>());
    commands.add(command as RemoveTagAssignment);
    return await result.future as GraphCommandResult<TSuccess, TFailure>;
  }
}

Tag _tag(int number, String name, {TagColor? color}) => Tag(
  id: _tagId(number),
  name: TagName.fromInput(name),
  color: color,
  position: tagPositionAt(number),
);

Future<void> _pumpUntil(WidgetTester tester, bool Function() done) async {
  for (var attempt = 0; attempt < 30 && !done(); attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }
  expect(done(), isTrue);
}
