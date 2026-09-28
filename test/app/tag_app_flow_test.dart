import 'package:doable/main.dart';
import 'package:doable/src/app/app_runtime.dart';
import 'package:doable/src/data/local/app_database.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../support/in_memory_diagnostics_sink.dart';

Future<void> _until(WidgetTester tester, Finder finder) async {
  for (var attempt = 0; attempt < 100; attempt++) {
    if (finder.evaluate().isNotEmpty) return;
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 20));
  }
  fail('Не появился элемент: $finder');
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await _until(tester, finder);
  await tester.pumpAndSettle();
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pump();
}

Future<void> _saveName(WidgetTester tester, String name) async {
  await _until(tester, find.byKey(const ValueKey('tag-editor-name')));
  await tester.enterText(find.byKey(const ValueKey('tag-editor-name')), name);
  await _tap(tester, find.byKey(const ValueKey('tag-editor-submit')));
  for (var attempt = 0; attempt < 100; attempt++) {
    if (find.byKey(const ValueKey('tag-editor-name')).evaluate().isEmpty) {
      return;
    }
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 20));
  }
  fail('Форма не закрылась после сохранения');
}

void main() {
  for (final locale in [const Locale('ru'), const Locale('en')]) {
    testWidgets(
      'каталог: вход, создание, переименование, отмена удаления, удаление и повтор имени — ${locale.languageCode}',
      (tester) async {
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        tester.binding.platformDispatcher.localesTestValue = [locale];
        addTearDown(tester.binding.platformDispatcher.clearLocalesTestValue);
        tester.view.physicalSize = const Size(1200, 2400);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);

        late sqlite.Database raw;
        final runtime = AppRuntime(
          connectionFactory: () =>
              openInMemoryLocalDatabase(setup: (database) => raw = database),
          diagnosticsSink: InMemoryDiagnosticsSink(),
        );
        addTearDown(() async {
          await tester.pumpWidget(const SizedBox.shrink());
          await runtime.shutdown();
        });
        await tester.pumpWidget(MainApp(runtime: runtime));
        await _tap(tester, find.byKey(const ValueKey('catalog-open-tags')));
        await _until(tester, find.byKey(const ValueKey('tag-catalog-create')));

        await _tap(tester, find.byKey(const ValueKey('tag-catalog-create')));
        await _saveName(tester, '  Straße  ');
        await _until(tester, find.text('Straße'));
        final firstId = raw.select('SELECT id FROM tags').single['id'];
        expect(raw.select('SELECT name FROM tags').single['name'], 'Straße');

        await _tap(tester, find.byKey(const ValueKey('tag-catalog-create')));
        await _until(tester, find.byKey(const ValueKey('tag-editor-name')));
        await tester.enterText(
          find.byKey(const ValueKey('tag-editor-name')),
          'STRASSE',
        );
        await _tap(tester, find.byKey(const ValueKey('tag-editor-submit')));
        await _until(
          tester,
          find.byKey(const ValueKey('tag-editor-use-existing')),
        );
        expect(raw.select('SELECT id FROM tags'), hasLength(1));
        expect(
          tester
              .widget<TextField>(find.byKey(const ValueKey('tag-editor-name')))
              .controller!
              .text,
          'STRASSE',
        );
        await _tap(tester, find.byKey(const ValueKey('tag-editor-cancel')));
        await _until(tester, find.text('Straße'));

        await _tap(tester, find.byIcon(Icons.edit_outlined));
        await _saveName(tester, 'Быт 🏠');
        await _until(tester, find.text('Быт 🏠'));
        expect(find.text('Straße'), findsNothing);
        expect(raw.select('SELECT id FROM tags').single['id'], firstId);

        final delete = find.byKey(ValueKey('tag-catalog-delete-$firstId'));
        await _tap(tester, delete);
        await _until(tester, find.byKey(const ValueKey('tag-delete-scope')));
        expect(find.textContaining('Быт 🏠'), findsWidgets);
        await _tap(tester, find.byKey(const ValueKey('tag-delete-cancel')));
        expect(raw.select('SELECT id FROM tags').single['id'], firstId);
        await _tap(tester, delete);
        await _tap(tester, find.byKey(const ValueKey('tag-delete-confirm')));
        for (
          var attempt = 0;
          attempt < 100 && raw.select('SELECT id FROM tags').isNotEmpty;
          attempt++
        ) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)),
          );
          await tester.pump(const Duration(milliseconds: 20));
        }
        expect(raw.select('SELECT id FROM tags'), isEmpty);
        await tester.pumpAndSettle();
        expect(find.text('Быт 🏠'), findsNothing);
        expect(delete, findsNothing);

        await _tap(tester, find.byKey(const ValueKey('tag-catalog-create')));
        await _saveName(tester, 'Быт 🏠');
        await _until(tester, find.text('Быт 🏠'));
        expect(raw.select('SELECT id FROM tags'), hasLength(1));
        expect(raw.select('SELECT id FROM tags').single['id'], isNot(firstId));
        tester.binding.platformDispatcher.localesTestValue = [
          locale.languageCode == 'ru' ? const Locale('en') : const Locale('ru'),
        ];
        await tester.pumpAndSettle();
        expect(find.text('Быт 🏠'), findsOneWidget);
        expect(raw.select('SELECT name FROM tags').single['name'], 'Быт 🏠');
        expect(
          find.text(locale.languageCode == 'ru' ? 'Tags' : 'Теги'),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
}
