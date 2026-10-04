import 'dart:async';

import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/tag/application/tag_assignment_status.dart';
import 'package:doable/src/tag/application/tag_change.dart';
import 'package:doable/src/tag/application/tag_command.dart';
import 'package:doable/src/tag/application/tag_result.dart';
import 'package:doable/src/tag/domain/tag.dart';
import 'package:doable/src/tag/domain/tag_id.dart';
import 'package:doable/src/tag/domain/tag_name.dart';
import 'package:doable/src/tag/presentation/catalog/tag_catalog_view.dart';
import 'package:doable/src/tag/presentation/catalog/tag_selection_context.dart';
import 'package:doable/src/tag/presentation/editor/tag_editor_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/tag_catalog_test_repository.dart';
import '../../../support/tag_assignment_changed.dart';

void main() {
  testWidgets(
    'поиск сохраняет явное назначение скрытого тега тому же намерению',
    (tester) async {
      final h = await _show(tester);
      await tester.tap(_row(h.home));
      await tester.enterText(_search, 'работ');
      await tester.pump();
      expect(_row(h.home), findsNothing);
      expect(_row(h.work), findsOneWidget);
      expect(find.text('Дом'), findsOneWidget);
      expect(h.repository.commands, isEmpty);
      expect(h.repository.reads, hasLength(1));

      await tester.tap(_assign);
      await tester.pump();
      final command = h.repository.commands.single as AssignTag;
      expect(command.tagId, h.home.id);
      expect(command.intentionId, h.intention.value);
      h.repository.command.complete(
        TagCommandSucceeded(
          ConfirmedGraphResult(
            revision: const TagCatalogTestRevision(2),
            value: testTagAssignmentChanged(
              TagAssignmentChangedChange(
                revision: const TagCatalogTestRevision(2),
                assignment: command.assignment,
                state: TagAssignmentState.assigned,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      h.repository.complete(
        [h.home, h.work],
        revision: 2,
        assignedIds: {h.home.id},
      );
      await tester.pump();
      expect(tester.widget<TextField>(_search).controller!.text, 'работ');
      expect(_row(h.home), findsNothing);
      expect(find.text('Дом'), findsOneWidget);
      expect(find.text('Назначен'), findsOneWidget);
      expect(tester.widget<FilledButton>(_assign).onPressed, isNull);
      expect(h.repository.commands, hasLength(1));
    },
  );

  testWidgets('отказ назначения сохраняет скрытый выбор для явного повтора', (
    tester,
  ) async {
    final h = await _show(tester);
    await tester.tap(_row(h.home));
    await tester.enterText(_search, 'нет совпадений');
    await tester.pump();
    expect(find.text('Теги не найдены'), findsOneWidget);
    await tester.tap(_assign);
    await tester.pump();
    h.repository.command.complete(
      const TagCommandFailed(TagUnavailableFailure()),
    );
    await tester.pump();
    expect(find.text('Дом'), findsOneWidget);
    expect(
      tester.widget<TextField>(_search).controller!.text,
      'нет совпадений',
    );
    expect(tester.widget<FilledButton>(_assign).onPressed, isNotNull);
    expect(h.repository.commands, hasLength(1));
    expect(h.repository.reads, hasLength(1));

    await tester.tap(find.byTooltip('Очистить поиск тегов'));
    await tester.pump();
    expect(tester.widget<Semantics>(_row(h.home)).properties.selected, isTrue);
    expect(h.repository.commands, hasLength(1));
  });

  testWidgets('выбор из редактора подтверждает пару до явного назначения', (
    tester,
  ) async {
    final editor = Completer<Tag?>();
    final h = await _show(tester, onOpenEditor: (_) => editor.future);
    final created = _tag(52, 'Из редактора');
    await tester.enterText(_search, 'работ');
    await tester.tap(find.byKey(const ValueKey('tag-catalog-create')));
    editor.complete(created);
    await tester.pump();
    h.repository.observe(created);
    h.repository.statusReads.single.complete(
      const TagAssignmentStatusError(TagAssignmentStatusUnavailable()),
    );
    await tester.pump();
    expect(h.repository.statusQueries.single, (created.id, h.intention.value));
    expect(find.text('Из редактора'), findsOneWidget);
    expect(_row(created), findsNothing);
    expect(tester.widget<FilledButton>(_assign).onPressed, isNull);
    expect(h.repository.commands, isEmpty);
    expect(tester.widget<TextField>(_search).controller!.text, 'работ');

    await tester.tap(find.text('Повторить'));
    await tester.pump();
    expect(tester.widget<FilledButton>(_assign).onPressed, isNull);
    h.repository.statusReads.last.complete(
      const TagAssignmentStatusSuccess(
        GraphSnapshot(value: false, revision: TagCatalogTestRevision()),
      ),
    );
    await tester.pump();
    expect(tester.widget<FilledButton>(_assign).onPressed, isNotNull);
    expect(h.repository.reads, hasLength(1));
    expect(h.repository.commands, isEmpty);
  });

  testWidgets('возврат редактора прежнего открытия не меняет новый выбор', (
    tester,
  ) async {
    final editor = Completer<Tag?>();
    final h = await _show(tester, onOpenEditor: (_) => editor.future);
    final firstIntention = h.intention.value;
    await tester.tap(find.byKey(const ValueKey('tag-catalog-create')));
    h.intention.value = _intentionId(200);
    await tester.pump();
    h.repository.complete([h.home, h.work], assignedIds: {});
    await tester.pump();
    h.intention.value = firstIntention;
    await tester.pump();
    h.repository.complete([h.home, h.work], assignedIds: {});
    await tester.pump();
    await tester.enterText(_search, 'дом');
    await tester.tap(_row(h.home));
    await tester.pump();

    editor.complete(_tag(52, 'Прежний редактор'));
    await tester.pump();
    expect(tester.widget<Semantics>(_row(h.home)).properties.selected, isTrue);
    expect(h.repository.statusReads, isEmpty);
    expect(h.repository.commands, isEmpty);
    expect(tester.widget<TextField>(_search).controller!.text, 'дом');
  });

  testWidgets('команда прежнего намерения не блокирует выбор нового', (
    tester,
  ) async {
    final h = await _show(tester);
    final firstIntention = h.intention.value;
    await tester.tap(_row(h.home));
    await tester.pump();
    await tester.tap(_assign);
    await tester.pump();
    h.intention.value = _intentionId(200);
    await tester.pump();
    h.repository.complete([h.home, h.work], assignedIds: {});
    await tester.pump();
    await tester.tap(_row(h.work));
    await tester.pump();
    expect(tester.widget<Semantics>(_row(h.work)).properties.selected, isTrue);

    h.repository.command.complete(
      TagCommandFailed(TagIntentionNotFoundFailure(firstIntention)),
    );
    await tester.pump();
    expect(tester.widget<Semantics>(_row(h.work)).properties.selected, isTrue);
    expect(
      find.byKey(const ValueKey('tag-catalog-assign-failure')),
      findsNothing,
    );
    expect(tester.widget<FilledButton>(_assign).onPressed, isNotNull);
    expect(h.repository.commands, hasLength(1));
  });
}

final _search = find.byKey(const ValueKey('tag-catalog-search'));
final _assign = find.byKey(const ValueKey('tag-catalog-assign'));
Finder _row(Tag tag) =>
    find.byKey(ValueKey('tag-catalog-row-${tag.id.toCanonicalString()}'));

Future<_Harness> _show(
  WidgetTester tester, {
  Future<Tag?> Function(TagEditorContext)? onOpenEditor,
}) async {
  final h = _Harness();
  addTearDown(h.repository.dispose);
  addTearDown(h.intention.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        personalGraphRepositoryProvider.overrideWithValue(h.repository),
      ],
      child: MaterialApp(
        locale: const Locale('ru'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: ValueListenableBuilder(
          valueListenable: h.intention,
          builder: (_, intentionId, _) => TagCatalogView(
            selectionContext: TagAssignmentContext(intentionId),
            onOpenEditor: onOpenEditor ?? (_) async => null,
            onOpenNavigation: (_) {},
          ),
        ),
      ),
    ),
  );
  h.repository.complete([h.home, h.work], assignedIds: {});
  await tester.pump();
  return h;
}

final class _Harness {
  final repository = TagCatalogTestRepository();
  final intention = ValueNotifier(_intentionId(100));
  final home = _tag(1, 'Дом');
  final work = _tag(2, 'Работа');
}

String _id(int number) =>
    '018f0b5d-6b2e-7c80-8000-${number.toRadixString(16).padLeft(12, '0')}';
IntentionId _intentionId(int number) =>
    (IntentionId.decode(_id(number)) as IntentionIdDecodingSuccess).id;
Tag _tag(int number, String name) => Tag(
  id: (TagId.decode(_id(number)) as TagIdDecodingSuccess).id,
  name: TagName.fromInput(name),
);
