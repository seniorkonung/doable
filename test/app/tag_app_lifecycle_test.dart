import 'dart:async';

import 'package:doable/main.dart';
import 'package:doable/src/app/app_runtime.dart';
import 'package:doable/src/data/local/app_database.dart';
import 'package:doable/src/graph/application/graph_command_coordinator.dart';
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/application/personal_graph_repository.dart';
import 'package:doable/src/graph/data/drift_personal_graph_repository.dart';
import 'package:doable/src/intention/application/intention_catalog.dart';
import 'package:doable/src/intention/application/intention_id_generator.dart';
import 'package:doable/src/intention/application/intention_result.dart';
import 'package:doable/src/tag/application/tag_catalog.dart';
import 'package:doable/src/tag/application/tag_command.dart';
import 'package:doable/src/tag/application/tag_read_result.dart';
import 'package:doable/src/tag/domain/tag_id.dart';
import 'package:doable/src/tag/domain/tag_name.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../support/in_memory_diagnostics_sink.dart';

Future<void> _until(WidgetTester tester, bool Function() done) async {
  for (var attempt = 0; attempt < 100 && !done(); attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 20));
  }
  expect(done(), isTrue);
}

Future<void> _tap(WidgetTester tester, String key) async {
  final finder = find.byKey(ValueKey(key));
  await _until(tester, () => finder.evaluate().isNotEmpty);
  await tester.pumpAndSettle();
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pump();
}

void main() {
  testWidgets('повтор, уход, фон и очередь результатов не повторяют запись', (
    tester,
  ) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    tester.binding.platformDispatcher.localesTestValue = const [Locale('ru')];
    addTearDown(tester.binding.platformDispatcher.clearLocalesTestValue);
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    late sqlite.Database raw;
    late _ControlledRepository repository;
    final diagnostics = InMemoryDiagnosticsSink();
    final runtime = AppRuntime(
      connectionFactory: () =>
          openInMemoryLocalDatabase(setup: (database) => raw = database),
      diagnosticsSink: diagnostics,
      repositoryFactory: (database) => repository = _ControlledRepository(
        DriftPersonalGraphRepository(
          database,
          UuidV7IntentionIdGenerator(),
          () => DateTime.utc(2026, 9, 25),
          diagnostics,
        ),
      ),
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await runtime.shutdown();
    });
    await tester.pumpWidget(MainApp(runtime: runtime));
    await _tap(tester, 'catalog-open-tags');
    await _tap(tester, 'tag-catalog-create');
    await _until(
      tester,
      () => find.byKey(const ValueKey('tag-editor-name')).evaluate().isNotEmpty,
    );
    await tester.enterText(
      find.byKey(const ValueKey('tag-editor-name')),
      'Дом',
    );
    repository.holdNextCreate();
    await _tap(tester, 'tag-editor-submit');
    await _until(tester, () => repository.createAttempts == 1);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const ValueKey('tag-editor-submit')))
          .onPressed,
      isNull,
    );
    await tester.tap(find.byKey(const ValueKey('tag-editor-submit')));
    await tester.pump();
    expect(repository.createAttempts, 1);

    await _tap(tester, 'tag-editor-cancel');
    await _until(
      tester,
      () => find
          .byKey(const ValueKey('tag-catalog-create'))
          .evaluate()
          .isNotEmpty,
    );
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    repository.releaseCreate();
    await _until(tester, () => raw.select('SELECT id FROM tags').length == 1);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('graph-operation-message')), findsNothing);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await _until(
      tester,
      () => find.textContaining('Тег создан.').evaluate().isNotEmpty,
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .getSemantics(
            find.byKey(const ValueKey('graph-operation-message')).first,
          )
          .label,
      contains('Тег создан.'),
    );
    if (find.byKey(const ValueKey('catalog-open-tags')).evaluate().isNotEmpty) {
      await _tap(tester, 'catalog-open-tags');
    }
    await _until(tester, () => find.text('Дом').evaluate().isNotEmpty);
    expect(repository.createAttempts, 1);

    final tagId = (TagId.decode(
      raw.select('SELECT id FROM tags').single['id'] as String,
    ) as TagIdDecodingSuccess).id;
    final second = runtime.commandCoordinator.acceptTagRename(
      RenameTag(tagId: tagId, name: TagName.fromInput('Работа')),
    );
    expect(second, isA<TagCommandAccepted>());
    await (second as TagCommandAccepted).future;
    await _until(
      tester,
      () => raw.select('SELECT name FROM tags').single['name'] == 'Работа',
    );
    expect(find.textContaining('Тег создан.'), findsWidgets);
    expect(find.textContaining('Тег переименован.'), findsNothing);
    ScaffoldMessenger.of(
      tester.element(find.byKey(const ValueKey('tag-catalog-create'))),
    ).removeCurrentSnackBar();
    await _until(
      tester,
      () => find.textContaining('Тег переименован.').evaluate().isNotEmpty,
    );
    await _until(tester, () => find.text('Работа').evaluate().isNotEmpty);
    expect(repository.createAttempts, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'после commit ошибка чтения сохраняет ввод и не повторяет создание',
    (tester) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      tester.binding.platformDispatcher.localesTestValue = const [Locale('en')];
      addTearDown(tester.binding.platformDispatcher.clearLocalesTestValue);
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      late sqlite.Database raw;
      late _ControlledRepository repository;
      final diagnostics = InMemoryDiagnosticsSink();
      final runtime = AppRuntime(
        connectionFactory: () =>
            openInMemoryLocalDatabase(setup: (database) => raw = database),
        diagnosticsSink: diagnostics,
        repositoryFactory: (database) => repository = _ControlledRepository(
          DriftPersonalGraphRepository(
            database,
            UuidV7IntentionIdGenerator(),
            () => DateTime.utc(2026, 9, 25),
            diagnostics,
          ),
        ),
      );
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await runtime.shutdown();
      });
      await tester.pumpWidget(MainApp(runtime: runtime));
      await _tap(tester, 'catalog-open-tags');
      await _tap(tester, 'tag-catalog-create');
      await _until(
        tester,
        () =>
            find.byKey(const ValueKey('tag-editor-name')).evaluate().isNotEmpty,
      );
      await tester.enterText(
        find.byKey(const ValueKey('tag-editor-name')),
        'Straße',
      );
      repository.failNextTagRead = true;
      repository.failNextCatalogRead = true;
      await _tap(tester, 'tag-editor-submit');
      await _until(
        tester,
        () => find
            .byKey(const ValueKey('tag-editor-retry-committed'))
            .evaluate()
            .isNotEmpty,
      );
      expect(raw.select('SELECT name FROM tags').single['name'], 'Straße');
      expect(repository.createAttempts, 1);
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('tag-editor-name')))
            .controller!
            .text,
        'Straße',
      );
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('tag-editor-submit')),
            )
            .onPressed,
        isNull,
      );
      await _tap(tester, 'tag-editor-retry-committed');
      await _until(
        tester,
        () => find.byKey(const ValueKey('tag-editor-name')).evaluate().isEmpty,
      );
      await _until(
        tester,
        () => find.textContaining('couldn’t be loaded').evaluate().isNotEmpty,
      );
      await tester.tap(find.text('Try again'));
      await _until(tester, () => find.text('Straße').evaluate().isNotEmpty);
      expect(repository.createAttempts, 1);
      expect(raw.select('SELECT id FROM tags'), hasLength(1));
      expect(tester.takeException(), isNull);
    },
  );
}

final class _ControlledRepository extends Fake
    implements PersonalGraphRepository {
  _ControlledRepository(this.delegate);

  final PersonalGraphRepository delegate;
  Completer<void>? _heldCreate;
  bool failNextTagRead = false;
  bool failNextCatalogRead = false;
  int createAttempts = 0;

  void holdNextCreate() => _heldCreate = Completer<void>();
  void releaseCreate() => _heldCreate!.complete();

  @override
  Future<Result<IntentionCatalogPage>> getCatalogPage(
    IntentionCatalogQuery query,
  ) => delegate.getCatalogPage(query);

  @override
  Future<TagCatalogPageResult> getTagCatalogPage(TagCatalogQuery query) =>
      failNextCatalogRead
      ? _failCatalogRead()
      : delegate.getTagCatalogPage(query);

  Future<TagCatalogPageResult> _failCatalogRead() async {
    failNextCatalogRead = false;
    return const TagCatalogPageError(TagCatalogUnavailableFailure());
  }

  @override
  Stream<TagReadResult> watchTag(TagId id) {
    if (failNextTagRead) {
      failNextTagRead = false;
      return Stream.value(const TagReadError(TagReadUnavailableFailure()));
    }
    return delegate.watchTag(id);
  }

  @override
  Future<GraphCommandResult<TSuccess, TFailure>> execute<
    TSuccess extends GraphCommandOutcome,
    TFailure extends GraphCommandFailure
  >(GraphCommand<TSuccess, TFailure> command) async {
    if (command is CreateTag) {
      createAttempts++;
      final gate = _heldCreate;
      if (gate != null) {
        await gate.future;
        _heldCreate = null;
      }
    }
    return delegate.execute(command);
  }
}
