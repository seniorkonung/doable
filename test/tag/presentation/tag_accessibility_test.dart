import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/src/app/routing/app_router.dart';
import 'package:doable/src/data/local/app_database.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:doable/src/graph/data/drift_personal_graph_repository.dart';
import 'package:doable/src/intention/application/intention_id_generator.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../../support/in_memory_diagnostics_sink.dart';

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

void main() {
  for (final locale in [const Locale('ru'), const Locale('en')]) {
    testWidgets(
      'диктор и увеличенный текст сохраняют ввод, действия и подтверждение — ${locale.languageCode}',
      (tester) async {
        tester.view.physicalSize = const Size(420, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final semantics = tester.ensureSemantics();
        late sqlite.Database raw;
        final database = AppDatabase(
          openInMemoryLocalDatabase(setup: (connection) => raw = connection),
        );
        await database.open();
        addTearDown(database.close);
        final repository = DriftPersonalGraphRepository(
          database,
          UuidV7IntentionIdGenerator(),
          () => DateTime.utc(2026, 9, 25),
          InMemoryDiagnosticsSink(),
        );
        final router = AppRouter();
        addTearDown(router.dispose);
        final l10n = await AppLocalizations.delegate.load(locale);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              personalGraphRepositoryProvider.overrideWithValue(repository),
            ],
            child: MaterialApp.router(
              locale: locale,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: const TextScaler.linear(2.5)),
                child: child!,
              ),
              routerConfig: router.config(),
            ),
          ),
        );
        addTearDown(() => tester.pumpWidget(const SizedBox.shrink()));
        await _tap(tester, find.byKey(const ValueKey('catalog-open-tags')));
        final create = find.byKey(const ValueKey('tag-catalog-create'));
        await _until(tester, create);
        await tester.pumpAndSettle();
        expect(tester.getSemantics(create).tooltip, l10n.tagCatalogCreate);
        await _tap(tester, create);
        final nameField = find.byKey(const ValueKey('tag-editor-name'));
        await _until(tester, nameField);
        expect(
          find.bySemanticsLabel(RegExp(l10n.tagEditorNameLabel)),
          findsWidgets,
        );

        final invalid = '🙂' * 256;
        await tester.enterText(nameField, invalid);
        await _tap(tester, find.byKey(const ValueKey('tag-editor-submit')));
        final failure = find.byKey(const ValueKey('tag-editor-field-failure'));
        await _until(tester, failure);
        await tester.pumpAndSettle();
        expect(tester.getSemantics(failure).label, isNotEmpty);
        expect(tester.widget<TextField>(nameField).controller!.text, invalid);
        expect(raw.select('SELECT * FROM tags'), isEmpty);

        final corrected =
            'Straße 🏠é ${('Длинное название ' * 8).trimRight()}';
        await tester.enterText(nameField, corrected);
        await _tap(tester, find.byKey(const ValueKey('tag-editor-submit')));
        await _until(tester, find.text(corrected));
        final id = raw.select('SELECT id FROM tags').single['id'] as String;
        final delete = find.byKey(ValueKey('tag-catalog-delete-$id'));
        await _until(tester, delete);
        await tester.pumpAndSettle();
        await tester.ensureVisible(delete);
        expect(tester.getSemantics(delete).tooltip, l10n.tagCatalogDelete);
        await _tap(tester, delete);
        final scope = find.byKey(const ValueKey('tag-delete-scope'));
        await _until(tester, scope);
        await tester.pumpAndSettle();
        expect(find.textContaining(corrected), findsWidgets);
        expect(
          tester.getSemantics(scope).label,
          contains(l10n.tagDeleteConfirmationScope),
        );
        final cancel = find.byKey(const ValueKey('tag-delete-cancel'));
        final confirm = find.byKey(const ValueKey('tag-delete-confirm'));
        await tester.ensureVisible(cancel);
        expect(tester.getSemantics(cancel).label, l10n.tagDeleteCancel);
        await tester.ensureVisible(confirm);
        expect(tester.getSemantics(confirm).label, l10n.tagDeleteConfirm);
        expect(tester.takeException(), isNull);
        await tester.tap(cancel);
        await tester.pumpAndSettle();
        expect(raw.select('SELECT id FROM tags'), hasLength(1));
        semantics.dispose();
      },
    );
  }
}
