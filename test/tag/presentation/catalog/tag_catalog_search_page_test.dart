import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/src/app/routing/app_router.dart';
import 'package:doable/src/app/routing/app_router.gr.dart';
import 'package:doable/src/data/local/app_database.dart'
    hide Tag, TagAssignment;
import 'package:doable/src/graph/application/graph_command_coordinator.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:doable/src/graph/data/drift_personal_graph_repository.dart';
import 'package:doable/src/intention/application/intention_id_generator.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/tag/application/tag_assignment_status.dart';
import 'package:doable/src/tag/application/tag_catalog.dart';
import 'package:doable/src/tag/application/tag_change.dart';
import 'package:doable/src/tag/application/tag_command.dart';
import 'package:doable/src/tag/application/tag_result.dart';
import 'package:doable/src/tag/domain/tag.dart';
import 'package:doable/src/tag/domain/tag_assignment.dart';
import 'package:doable/src/tag/domain/tag_id.dart';
import 'package:doable/src/tag/domain/tag_name.dart';
import 'package:doable/src/tag/presentation/catalog/tag_catalog_page.dart';
import 'package:doable/src/tag/presentation/catalog/tag_catalog_state.dart';
import 'package:doable/src/tag/presentation/catalog/tag_catalog_view_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../../../support/in_memory_diagnostics_sink.dart';
import '../../../support/tag_catalog_test_repository.dart';
import '../../../support/tag_storage_fixture.dart';
import '../../../support/tag_assignment_changed.dart';

part 'tag_catalog_search_recovery_scenarios.dart';

final _modes = <(String, IntentionId?)>[
  ('каталог', null),
  ('выбор для активного намерения', _intentionId(1)),
  ('выбор для архивированного действия', _intentionId(2)),
];

IntentionId _intentionId(int number) =>
    (IntentionId.decode(_id(number)) as IntentionIdDecodingSuccess).id;

final _search = find.byKey(const ValueKey('tag-catalog-search'));
final _list = find.byKey(const ValueKey('tag-catalog-list'));
final _selected = find.byKey(const ValueKey('tag-catalog-hidden-selection'));
final _assign = find.byKey(const ValueKey('tag-catalog-assign'));
final _editable = find.descendant(
  of: find.byType(TagCatalogPage),
  matching: find.byType(EditableText, skipOffstage: false),
  skipOffstage: false,
);

void main() {
  _registerSearchRecoveryScenarios();
  for (final (description, intentionId) in _modes) {
    testWidgets(
      '$description: поиск использует наблюдаемое имя выбранного тега до обновления полного снимка',
      (tester) async {
        final repository = await _pumpCatalog(tester, intentionId: intentionId);
        final home = _tag(1, 'Дом');
        final renamed = _tag(1, 'Спорт');
        repository.complete([home, _tag(2, 'Для дома'), _tag(3, 'Работа')]);
        await tester.pumpAndSettle();
        final model =
            ProviderScope.containerOf(
              tester.element(find.byType(TagCatalogPage)),
            ).read(
              tagCatalogViewModelProvider(
                mode: intentionId == null
                    ? const TagCatalogBrowseMode()
                    : TagCatalogSelectionMode(intentionId),
              ).notifier,
            );
        model.selectTag(home.id);
        await tester.enterText(_search, 'дом');
        await tester.pump();
        repository.observe(renamed, revision: 2);
        await tester.pumpAndSettle();
        expect(_loaded(tester, intentionId).items.first.name.value, 'Дом');
        expect(_visibleNames(tester), ['Для дома']);
        expect(find.text('Дом'), findsNothing);
        await tester.enterText(_search, 'спорт');
        await tester.pump();
        expect(_visibleNames(tester), ['Спорт']);
        repository.observe(home);
        await tester.pumpAndSettle();
        expect(_visibleNames(tester), ['Спорт']);
        expect(_loaded(tester, intentionId).selection.id, home.id);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      '$description: изменение запроса возвращает начало списка, выбор и обновление сохраняют прокрутку и ввод',
      (tester) async {
        final repository = await _pumpCatalog(tester, intentionId: intentionId);
        final tags = [
          _tag(1, 'Работа'),
          for (var index = 2; index <= 60; index++) _tag(index, 'Дом $index'),
        ];
        repository.complete(tags);
        await tester.pumpAndSettle();
        await tester.enterText(_search, 'дом');
        await tester.pump();
        final editable = tester.state<EditableTextState>(
          find.byType(EditableText),
        );
        final input = tester.widget<TextField>(_search).controller!;
        final editingValue = input.value;
        final scroll = tester.widget<CustomScrollView>(_list).controller!;
        await tester.drag(_list, const Offset(0, -800));
        await tester.pumpAndSettle();
        final offset = scroll.offset;
        expect(offset, greaterThan(0));

        if (intentionId != null) {
          await tester.tap(
            find
                .descendant(of: _list, matching: find.byType(ListTile))
                .hitTestable()
                .first,
          );
          await tester.pump();
          expect(scroll.offset, offset);
        }
        await _reachSearchElement(tester, _editable);
        await tester.showKeyboard(_search);
        await tester.drag(_list, const Offset(0, -800));
        await tester.pumpAndSettle();
        final refreshOffset = scroll.offset;
        expect(refreshOffset, greaterThan(0));
        await _beginRefresh(tester, repository);
        expect(scroll.offset, refreshOffset);
        repository.complete(tags, revision: 2);
        await tester.pumpAndSettle();
        expect(scroll.offset, refreshOffset);
        expect(tester.state<EditableTextState>(_editable), same(editable));
        expect(editable.widget.focusNode.hasFocus, isTrue);
        expect(input.value, editingValue);

        await _reachSearchElement(tester, _editable);
        await tester.enterText(_search, 'Дом');
        await tester.pumpAndSettle();
        expect(scroll.offset, 0);
        expect(_row(tags[1]).hitTestable(), findsOneWidget);
        await tester.drag(_list, const Offset(0, -800));
        await tester.pumpAndSettle();
        await _reachSearchElement(tester, _editable);
        await tester.enterText(_search, 'спорт');
        await tester.pumpAndSettle();
        expect(find.text('Теги не найдены'), findsOneWidget);
        await tester.tap(find.byTooltip('Очистить поиск тегов'));
        await tester.pumpAndSettle();
        expect(scroll.offset, 0);
        expect(_row(tags.first).hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      '$description: одинаковые страницы имеют независимый ввод, новое открытие начинает поиск заново',
      (tester) async {
        final router = AppRouter();
        final repository = await _pumpCatalog(
          tester,
          intentionId: intentionId,
          router: router,
        );
        repository.complete([_tag(1, 'Дом'), _tag(2, 'Работа')]);
        await tester.pumpAndSettle();
        await tester.enterText(_search, 'работ');
        await tester.pump();
        final firstInput = tester.widget<TextField>(_search).controller!;
        unawaited(router.push<void>(TagCatalogRoute(intentionId: intentionId)));
        await tester.pumpAndSettle();
        final secondInput = tester.widget<TextField>(_search).controller!;
        expect(secondInput, isNot(same(firstInput)));
        expect(secondInput.text, isEmpty);
        expect(_visibleNames(tester), ['Дом', 'Работа']);
        await tester.enterText(_search, 'дом');
        await tester.pump();
        expect(firstInput.text, 'работ');
        expect(secondInput.text, 'дом');
        expect(_visibleNames(tester), ['Дом']);
        await router.maybePop();
        await tester.pumpAndSettle();
        expect(tester.widget<TextField>(_search).controller, same(firstInput));
        expect(_visibleNames(tester), ['Работа']);
        expect(() => secondInput.addListener(() {}), throwsFlutterError);
        unawaited(router.push<void>(TagCatalogRoute(intentionId: intentionId)));
        await tester.pumpAndSettle();
        expect(tester.widget<TextField>(_search).controller!.text, isEmpty);
        expect(_visibleNames(tester), ['Дом', 'Работа']);
        await tester.enterText(_search, 'дом');
        await tester.pump();
        await tester.tap(find.byTooltip('Очистить поиск тегов'));
        await tester.pump();
        expect(firstInput.text, 'работ');
        expect(_visibleNames(tester), ['Дом', 'Работа']);
        expect(tester.takeException(), isNull);
      },
    );

    if (intentionId != null) {
      for (final assigned in [false, true]) {
        testWidgets(
          '$description: скрытый ${assigned ? 'назначенный' : 'свободный'} выбор показан у действия, очистка возвращает выделение',
          (tester) async {
            final repository = await _pumpCatalog(
              tester,
              intentionId: intentionId,
            );
            final tags = [
              _tag(1, 'Дом'),
              _tag(2, 'Для дома'),
              _tag(3, 'Работа'),
            ];
            repository.complete(tags);
            await tester.pumpAndSettle();
            final selected = tags[assigned ? 1 : 0];
            await tester.tap(_row(selected));
            await tester.pump();
            expect(repository.commands, isEmpty);

            for (final query in ['работ', 'спорт']) {
              await tester.enterText(_search, query);
              await tester.pump();
              expect(_visibleNames(tester), query == 'работ' ? ['Работа'] : []);
              expect(_row(selected), findsNothing);
              expect(_loaded(tester, intentionId).selection.id, selected.id);
              expect(_selected, findsOneWidget);
              expect(
                find.descendant(
                  of: _selected,
                  matching: find.text(selected.name.value),
                ),
                findsOneWidget,
              );
              expect(
                find.descendant(
                  of: _selected,
                  matching: find.text(
                    assigned ? 'Назначен' : 'Доступен для назначения',
                  ),
                ),
                findsOneWidget,
              );
              expect(
                tester.getRect(_selected).bottom,
                lessThanOrEqualTo(tester.getRect(_assign).top),
              );
              expect(
                tester.widget<FilledButton>(_assign).onPressed,
                assigned ? isNull : isNotNull,
              );
              expect(repository.commands, isEmpty);
              if (query == 'спорт') {
                expect(find.text('Теги не найдены'), findsOneWidget);
                expect(
                  find.byKey(const ValueKey('tag-catalog-create')),
                  findsOneWidget,
                );
              }
            }

            await tester.tap(find.byTooltip('Очистить поиск тегов'));
            await tester.pump();
            expect(_visibleNames(tester), tags.map((tag) => tag.name.value));
            expect(
              tester.widget<Semantics>(_row(selected)).properties.selected,
              isTrue,
            );
            expect(
              _assignment(tester, selected),
              assigned ? 'Назначен' : 'Доступен для назначения',
            );
            expect(_selected, findsNothing);
            expect(repository.commands, isEmpty);
            expect(tester.takeException(), isNull);
          },
        );
      }

      testWidgets(
        '$description: явное назначение скрытого выбора сохраняет идентичность при вводе во время операции',
        (tester) async {
          final repository = await _pumpCatalog(
            tester,
            intentionId: intentionId,
          );
          final home = _tag(1, 'Дом');
          final work = _tag(2, 'Работа');
          repository.complete([home, work]);
          await tester.pumpAndSettle();
          await tester.tap(_row(home));
          await tester.pump();
          await tester.enterText(_search, 'работ');
          await tester.pump();
          expect(
            find.descendant(of: _selected, matching: find.text('Дом')),
            findsOneWidget,
          );
          expect(repository.commands, isEmpty);

          await tester.tap(_assign);
          await tester.pump();
          final command = repository.commands.single as AssignTag;
          expect(command.tagId, home.id);
          expect(command.intentionId, intentionId);
          for (final query in ['спорт', '', 'работ']) {
            await tester.enterText(_search, query);
            await tester.pump();
            expect(_loaded(tester, intentionId).selection.id, home.id);
            expect(tester.widget<FilledButton>(_assign).onPressed, isNull);
            expect(repository.commands.single, same(command));
          }
          final tile = tester.widget<ListTile>(
            find.descendant(of: _row(work), matching: find.byType(ListTile)),
          );
          expect(tile.onTap, isNull);
          repository.command.complete(
            TagCommandSucceeded(
              ConfirmedGraphResult(
                revision: const TagCatalogTestRevision(2),
                value: testTagAssignmentChanged(
                  TagAssignmentChangedChange(
                    revision: const TagCatalogTestRevision(2),
                    assignment: TagAssignment(
                      tagId: home.id,
                      intentionId: intentionId,
                    ),
                    state: TagAssignmentState.assigned,
                  ),
                ),
              ),
            ),
          );
          await tester.pump();
          repository.complete(
            [home, work],
            revision: 2,
            assignedIds: {home.id},
          );
          await tester.pumpAndSettle();
          expect(_visibleNames(tester), ['Работа']);
          expect(
            find.descendant(of: _selected, matching: find.text('Назначен')),
            findsOneWidget,
          );
          expect(tester.widget<FilledButton>(_assign).onPressed, isNull);
          expect(repository.commands, hasLength(1));
          await tester.tap(find.byTooltip('Очистить поиск тегов'));
          await tester.pump();
          expect(_assignment(tester, home), 'Назначен');
          expect(_assignment(tester, work), 'Доступен для назначения');
          expect(
            tester.widget<Semantics>(_row(home)).properties.selected,
            isTrue,
          );
          expect(repository.commands, hasLength(1));
          expect(tester.takeException(), isNull);
        },
      );

      testWidgets(
        '$description: скрытый выбор вне снимка показывает подтверждённое имя, ожидает признак назначения и исчезает после удаления',
        (tester) async {
          final repository = await _pumpCatalog(
            tester,
            intentionId: intentionId,
          );
          repository.complete([_tag(1, 'Работа')]);
          await tester.pumpAndSettle();
          await tester.enterText(_search, 'работ');
          await tester.pump();
          final selected = _tag(99, 'Дом');
          final model =
              ProviderScope.containerOf(
                tester.element(find.byType(TagCatalogPage)),
              ).read(
                tagCatalogViewModelProvider(
                  mode: TagCatalogSelectionMode(intentionId),
                ).notifier,
              );
          model.selectTag(selected.id);
          repository.observe(selected);
          await tester.pumpAndSettle();
          expect(_visibleNames(tester), ['Работа']);
          expect(
            find.descendant(of: _selected, matching: find.text('Дом')),
            findsOneWidget,
          );
          expect(
            find.descendant(
              of: _selected,
              matching: find.text('Назначение ещё не проверено'),
            ),
            findsOneWidget,
          );
          expect(tester.widget<FilledButton>(_assign).onPressed, isNull);
          expect(repository.commands, isEmpty);
          repository.statusReads.single.complete(
            const TagAssignmentStatusError(TagAssignmentStatusUnavailable()),
          );
          await tester.pumpAndSettle();
          final l10n = _localizations(tester);
          expect(find.text(l10n.tagAssignmentsUnavailable), findsOneWidget);
          expect(
            find.descendant(
              of: _selected,
              matching: find.text(l10n.tagCatalogAssignmentUnknown),
            ),
            findsOneWidget,
          );
          expect(tester.widget<FilledButton>(_assign).onPressed, isNull);
          expect(repository.commands, isEmpty);
          await tester.tap(find.text(l10n.commonRetry));
          await tester.pump();
          expect(repository.statusReads, hasLength(2));
          repository.statusReads.last.complete(
            const TagAssignmentStatusSuccess(
              GraphSnapshot(value: false, revision: TagCatalogTestRevision()),
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.widget<FilledButton>(_assign).onPressed, isNotNull);
          final renamed = Tag(
            id: selected.id,
            name: TagName.fromInput('Актуальный дом'),
          );
          repository.observe(renamed, revision: 2);
          await tester.pumpAndSettle();
          expect(
            find.descendant(
              of: _selected,
              matching: find.text('Актуальный дом'),
            ),
            findsOneWidget,
          );
          expect(find.text('Дом'), findsNothing);
          repository.observe(null, id: selected.id, revision: 3);
          await tester.pump();
          await tester.pump();
          expect(
            _loaded(tester, intentionId).selection,
            isA<TagCatalogNoSelection>(),
          );
          expect(_selected, findsNothing);
          expect(tester.widget<FilledButton>(_assign).onPressed, isNull);
          expect(repository.commands, isEmpty);
          expect(tester.takeException(), isNull);
        },
      );

      testWidgets(
        '$description: возврат из редактора сохраняет поиск и показывает выбор до обновления снимка без автоматического назначения',
        (tester) async {
          final router = AppRouter();
          final repository = await _pumpCatalog(
            tester,
            intentionId: intentionId,
            router: router,
          );
          final work = _tag(1, 'Работа');
          final selected = _tag(99, 'Дом');
          repository.complete([work]);
          await tester.pumpAndSettle();
          await tester.enterText(_search, 'работ');
          await tester.pump();
          await tester.tap(find.byKey(const ValueKey('tag-catalog-create')));
          await tester.pumpAndSettle();
          expect(router.current.name, TagEditorRoute.name);

          await router.maybePop<Tag>(selected);
          await tester.pump();
          repository.observe(selected);
          repository.statusReads.single.complete(
            const TagAssignmentStatusSuccess(
              GraphSnapshot(value: false, revision: TagCatalogTestRevision()),
            ),
          );
          await tester.pumpAndSettle();

          expect(tester.widget<TextField>(_search).controller!.text, 'работ');
          expect(_visibleNames(tester), ['Работа']);
          expect(_loaded(tester, intentionId).items, [work]);
          expect(_loaded(tester, intentionId).selection.id, selected.id);
          expect(
            find.descendant(of: _selected, matching: find.text('Дом')),
            findsOneWidget,
          );
          expect(
            find.descendant(
              of: _selected,
              matching: find.text('Доступен для назначения'),
            ),
            findsOneWidget,
          );
          expect(repository.commands, isEmpty);
          expect(tester.widget<FilledButton>(_assign).onPressed, isNotNull);

          await tester.tap(_assign);
          await tester.pump();
          final command = repository.commands.single as AssignTag;
          expect(command.tagId, selected.id);
          expect(command.intentionId, intentionId);
          expect(_loaded(tester, intentionId).selection.id, selected.id);
          expect(tester.takeException(), isNull);
        },
      );
    }

    testWidgets(
      '$description: текущий ввод сразу фильтрует пары в прежнем порядке, очистка возвращает снимок',
      (tester) async {
        final repository = await _pumpCatalog(tester, intentionId: intentionId);
        final tags = [
          _tag(1, 'Работа'),
          _tag(2, 'Дом'),
          _tag(3, 'Для дома'),
          _tag(4, 'Домашнее'),
        ];
        repository.complete(tags);
        await tester.pumpAndSettle();

        await tester.enterText(_search, 'ДОМ');
        await tester.pump();
        expect(_visibleNames(tester), ['Дом', 'Для дома', 'Домашнее']);
        if (intentionId != null) {
          expect(_assignment(tester, tags[1]), 'Назначен');
          expect(_assignment(tester, tags[2]), 'Доступен для назначения');
          expect(_assignment(tester, tags[3]), 'Назначен');
        }

        await tester.enterText(_search, 'работ');
        await tester.pump();
        expect(tester.widget<TextField>(_search).controller!.text, 'работ');
        expect(_visibleNames(tester), ['Работа']);
        if (intentionId != null) {
          expect(_assignment(tester, tags[0]), 'Доступен для назначения');
        }

        await tester.tap(find.byTooltip('Очистить поиск тегов'));
        await tester.pump();
        expect(tester.widget<TextField>(_search).controller!.text, isEmpty);
        expect(_visibleNames(tester), tags.map((tag) => tag.name.value));
        final state = _loaded(tester, intentionId);
        expect(state.items, tags);
        if (intentionId != null) {
          expect(state.selectionRows.map((row) => row.isAssigned), [
            false,
            true,
            false,
            true,
          ]);
        }
      },
    );

    testWidgets('$description: поиск находит тег вне видимой области', (
      tester,
    ) async {
      final repository = await _pumpCatalog(tester, intentionId: intentionId);
      repository.complete([
        for (var index = 1; index <= 132; index++) _tag(index, 'Тег $index'),
        _tag(133, 'Straße'),
      ]);
      await tester.pumpAndSettle();
      expect(find.text('Straße'), findsNothing);

      await tester.enterText(_search, 'STRASS');
      await tester.pump();

      expect(_visibleNames(tester), ['Straße']);
      expect(_loaded(tester, intentionId).items, hasLength(133));
    });

    for (final language in ['ru', 'en']) {
      testWidgets(
        '$description: пустой каталог и отсутствие совпадений различаются на $language',
        (tester) async {
          final repository = await _pumpCatalog(
            tester,
            intentionId: intentionId,
            language: language,
          );
          final l10n = _localizations(tester);
          repository.complete([]);
          await tester.pumpAndSettle();
          expect(find.text(l10n.tagCatalogEmpty), findsOneWidget);
          expect(find.text(l10n.tagCatalogSearch), findsOneWidget);

          await tester.enterText(_search, 'спорт');
          await tester.pump();

          expect(find.text(l10n.tagCatalogNoMatches), findsOneWidget);
          expect(find.text(l10n.tagCatalogEmpty), findsNothing);
          expect(tester.widget<TextField>(_search).controller!.text, 'спорт');
          expect(
            tester
                .widget<IconButton>(
                  find.byKey(const ValueKey('tag-catalog-create')),
                )
                .onPressed,
            isNotNull,
          );
          await tester.tap(find.byTooltip(l10n.tagCatalogClearSearch));
          await tester.pump();
          expect(find.text(l10n.tagCatalogEmpty), findsOneWidget);
          expect(find.text(l10n.tagCatalogNoMatches), findsNothing);
        },
      );

      testWidgets(
        '$description: некорректный ввод сохраняется с последним корректным фильтром на $language',
        (tester) async {
          final semantics = tester.ensureSemantics();
          try {
            final repository = await _pumpCatalog(
              tester,
              intentionId: intentionId,
              language: language,
            );
            final l10n = _localizations(tester);
            for (final explanation
                in language == 'ru'
                    ? ['не применён', 'последнего корректного запроса']
                    : ['wasn’t applied', 'last valid query']) {
              expect(l10n.tagCatalogInvalidSearch, contains(explanation));
            }
            final tags = [
              _tag(1, 'Работа'),
              _tag(2, 'Дом'),
              _tag(3, 'Для дома'),
            ];
            repository.complete(tags);
            await tester.pumpAndSettle();

            await tester.enterText(_search, '\u0000');
            await tester.pump();
            expect(
              tester.widget<TextField>(_search).controller!.text,
              '\u0000',
            );
            expect(_visibleNames(tester), ['Работа', 'Дом', 'Для дома']);
            expect(find.text(l10n.tagCatalogNoMatches), findsNothing);
            expect(find.text(l10n.tagCatalogInvalidSearch), findsOneWidget);

            await tester.enterText(_search, 'дом');
            await tester.pump();
            for (final input in ['спорт\u0000', '\ud800', '\udc00']) {
              await tester.enterText(_search, input);
              await tester.pump();

              expect(tester.widget<TextField>(_search).controller!.text, input);
              expect(find.text(l10n.tagCatalogInvalidSearch), findsOneWidget);
              await tester.pumpAndSettle();
              expect(
                tester
                    .getSemantics(find.text(l10n.tagCatalogInvalidSearch))
                    .label,
                contains(l10n.tagCatalogInvalidSearch),
              );
              expect(_visibleNames(tester), ['Дом', 'Для дома']);
              expect(find.text(l10n.tagCatalogNoMatches), findsNothing);
              if (intentionId != null) {
                expect(_assignment(tester, tags[1]), l10n.tagCatalogAssigned);
                expect(_assignment(tester, tags[2]), l10n.tagCatalogAvailable);
              }
            }

            await tester.enterText(_search, 'работ');
            await tester.pump();
            expect(find.text(l10n.tagCatalogInvalidSearch), findsNothing);
            expect(_visibleNames(tester), ['Работа']);

            await tester.enterText(_search, '\u0000');
            await tester.pump();
            await tester.tap(find.byTooltip(l10n.tagCatalogClearSearch));
            await tester.pump();
            expect(tester.widget<TextField>(_search).controller!.text, isEmpty);
            expect(find.text(l10n.tagCatalogInvalidSearch), findsNothing);
            expect(_visibleNames(tester), ['Работа', 'Дом', 'Для дома']);

            await tester.enterText(_search, 'спорт');
            await tester.pump();
            await tester.enterText(_search, '\u0000');
            await tester.pump();
            expect(find.text(l10n.tagCatalogNoMatches), findsOneWidget);
            expect(find.text(l10n.tagCatalogInvalidSearch), findsOneWidget);
            expect(_visibleNames(tester), isEmpty);
            expect(tester.takeException(), isNull);
          } finally {
            semantics.dispose();
          }
        },
      );
    }

    testWidgets(
      '$description: некорректный ввод и фильтр сохраняются после редактора, переименования и назначения',
      (tester) async {
        final router = await _pumpStoredCatalog(
          tester,
          intentionId: intentionId,
        );
        final l10n = _localizations(tester);
        final home = _tag(firstTagNumber, 'Дом 🏷️');
        final unused = _tag(303, 'Дом без назначений');
        const invalid = 'спорт\u0000\ud800\udc00\udc00';
        await tester.enterText(_search, 'дом');
        await tester.pump();
        await tester.enterText(_search, invalid);
        await tester.pump();
        final editingValue = tester
            .widget<TextField>(_search)
            .controller!
            .value;
        expect(_visibleNames(tester), [
          'Дом 🏷️',
          'Дом без назначений',
          'Дом в архиве',
        ]);

        await tester.tap(find.byKey(const ValueKey('tag-catalog-create')));
        await tester.pumpAndSettle();
        expect(router.current.name, TagEditorRoute.name);
        await tester.tap(find.byKey(const ValueKey('tag-editor-cancel')));
        await tester.pumpAndSettle();
        expect(
          tester.widget<TextField>(_search).controller!.value,
          editingValue,
        );
        expect(find.text(l10n.tagCatalogInvalidSearch), findsOneWidget);
        expect(_visibleNames(tester), [
          'Дом 🏷️',
          'Дом без назначений',
          'Дом в архиве',
        ]);

        await tester.tap(find.byKey(const ValueKey('tag-catalog-create')));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const ValueKey('tag-editor-name')),
          'Новый дом',
        );
        await tester.tap(find.byKey(const ValueKey('tag-editor-submit')));
        await _pumpUntil(
          tester,
          () =>
              router.current.name == TagCatalogRoute.name &&
              _loaded(tester, intentionId).canUseCurrentItems &&
              _visibleNames(tester).contains('Новый дом'),
        );
        expect(
          tester.widget<TextField>(_search).controller!.value,
          editingValue,
        );
        expect(find.text(l10n.tagCatalogInvalidSearch), findsOneWidget);
        expect(_visibleNames(tester), [
          'Дом 🏷️',
          'Дом без назначений',
          'Дом в архиве',
          'Новый дом',
        ]);
        final container = ProviderScope.containerOf(
          tester.element(find.byType(TagCatalogPage)),
        );
        final rename = container
            .read(graphCommandCoordinatorProvider.notifier)
            .acceptTagRename(
              RenameTag(tagId: home.id, name: TagName.fromInput('Спорт')),
            );
        expect(rename, isA<TagCommandAccepted>());
        await tester.runAsync(() => (rename as TagCommandAccepted).future);
        await _pumpUntil(
          tester,
          () =>
              _loaded(tester, intentionId).canUseCurrentItems &&
              _loaded(tester, intentionId).items.first.name.value == 'Спорт',
        );
        await tester.pumpAndSettle();
        expect(router.current.name, TagCatalogRoute.name);
        expect(
          tester.widget<TextField>(_search).controller!.value,
          editingValue,
        );
        expect(find.text(l10n.tagCatalogInvalidSearch), findsOneWidget);
        expect(_visibleNames(tester), [
          'Дом без назначений',
          'Дом в архиве',
          'Новый дом',
        ]);
        expect(find.text(l10n.tagCatalogNoMatches), findsNothing);

        if (intentionId != null) {
          expect(_assignment(tester, unused), l10n.tagCatalogAvailable);
          await tester.tap(_row(unused));
          await tester.pump();
          await tester.tap(_assign);
          await _pumpUntil(
            tester,
            () =>
                _loaded(tester, intentionId).canUseCurrentItems &&
                _loaded(tester, intentionId).selectedAssignment ==
                    TagCatalogSelectedAssignment.assigned,
          );
          await tester.pumpAndSettle();
          expect(_assignment(tester, unused), l10n.tagCatalogAssigned);
          expect(_visibleNames(tester), [
            'Дом без назначений',
            'Дом в архиве',
            'Новый дом',
          ]);
          expect(
            tester.widget<TextField>(_search).controller!.value,
            editingValue,
          );
          expect(find.text(l10n.tagCatalogInvalidSearch), findsOneWidget);
        }

        await tester.enterText(_search, 'спорт');
        await tester.pump();
        expect(_visibleNames(tester), ['Спорт']);
        expect(find.text(l10n.tagCatalogInvalidSearch), findsNothing);
        if (intentionId != null) {
          expect(_assignment(tester, home), l10n.tagCatalogAssigned);
        }
        await tester.enterText(_search, invalid);
        await tester.pump();
        await tester.tap(find.byTooltip(l10n.tagCatalogClearSearch));
        await tester.pump();
        expect(_visibleNames(tester), [
          'Спорт',
          'Дом без назначений',
          'Дом в архиве',
          'Работа',
          'Новый дом',
        ]);
        expect(tester.widget<TextField>(_search).controller!.text, isEmpty);
        expect(find.text(l10n.tagCatalogInvalidSearch), findsNothing);
        if (intentionId != null) {
          expect(_assignment(tester, unused), l10n.tagCatalogAssigned);
        }
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      '$description: отказ и повтор обновления сохраняют некорректный ввод и применённый фильтр',
      (tester) async {
        final repository = await _pumpCatalog(tester, intentionId: intentionId);
        final l10n = _localizations(tester);
        final home = _tag(2, 'Дом');
        final forHome = _tag(3, 'Для дома');
        repository.complete([_tag(1, 'Работа'), home, forHome]);
        await tester.pumpAndSettle();
        await tester.enterText(_search, 'дом');
        await tester.pump();
        const invalid = 'работ\udc00';
        await tester.enterText(_search, invalid);
        await tester.pump();
        await _beginRefresh(tester, repository);
        repository.reads.last.complete(
          const TagCatalogError(TagCatalogUnavailableFailure()),
        );
        await tester.pumpAndSettle();
        expect(find.text(l10n.tagCatalogUnavailable), findsOneWidget);
        expect(find.text(l10n.tagCatalogInvalidSearch), findsOneWidget);
        expect(find.text(l10n.tagCatalogNoMatches), findsNothing);
        expect(tester.widget<TextField>(_search).controller!.text, invalid);
        expect(_visibleNames(tester), ['Дом', 'Для дома']);

        await tester.tap(find.text(l10n.commonRetry));
        await tester.pump();
        repository.complete([_tag(1, 'Рабочее'), home, forHome], revision: 2);
        await tester.pumpAndSettle();
        expect(find.text(l10n.tagCatalogUnavailable), findsNothing);
        expect(find.text(l10n.tagCatalogInvalidSearch), findsOneWidget);
        expect(find.text(l10n.tagCatalogNoMatches), findsNothing);
        expect(tester.widget<TextField>(_search).controller!.text, invalid);
        expect(_visibleNames(tester), ['Дом', 'Для дома']);
        if (intentionId != null) {
          expect(_assignment(tester, home), l10n.tagCatalogAssigned);
          expect(_assignment(tester, forHome), l10n.tagCatalogAvailable);
        }
        await tester.enterText(_search, 'раб');
        await tester.pump();
        expect(_visibleNames(tester), ['Рабочее']);
        expect(find.text(l10n.tagCatalogInvalidSearch), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      '$description: загрузка и отказ первоначального чтения имеют приоритет перед отсутствием совпадений',
      (tester) async {
        final repository = await _pumpCatalog(tester, intentionId: intentionId);
        final l10n = _localizations(tester);
        await tester.enterText(_search, 'спорт');
        await tester.pump();
        expect(find.text(l10n.tagCatalogLoading), findsOneWidget);
        expect(find.text(l10n.tagCatalogNoMatches), findsNothing);

        repository.reads.last.complete(
          const TagCatalogError(TagCatalogUnavailableFailure()),
        );
        await tester.pumpAndSettle();
        expect(find.text(l10n.tagCatalogUnavailable), findsOneWidget);
        expect(find.text(l10n.tagCatalogNoMatches), findsNothing);
        expect(tester.widget<TextField>(_search).controller!.text, 'спорт');

        await tester.tap(find.text(l10n.commonRetry));
        await tester.pump();
        expect(find.text(l10n.tagCatalogLoading), findsOneWidget);
        expect(find.text(l10n.tagCatalogNoMatches), findsNothing);
        repository.complete([_tag(1, 'Дом')]);
        await tester.pumpAndSettle();
        expect(find.text(l10n.tagCatalogNoMatches), findsOneWidget);
      },
    );

    testWidgets(
      '$description: при отказе обновления поиск сохраняет неактуальные строки и ограничения действий',
      (tester) async {
        final repository = await _pumpCatalog(tester, intentionId: intentionId);
        final l10n = _localizations(tester);
        repository.complete([_tag(1, 'Работа'), _tag(2, 'Дом')]);
        await tester.pumpAndSettle();
        await tester.enterText(_search, 'дом');
        await tester.pump();
        await _beginRefresh(tester, repository);
        expect(find.text(l10n.tagCatalogRefreshing), findsOneWidget);
        expect(_visibleNames(tester), ['Дом']);

        repository.reads.last.complete(
          const TagCatalogError(TagCatalogUnavailableFailure()),
        );
        await tester.pumpAndSettle();

        expect(find.text(l10n.tagCatalogUnavailable), findsOneWidget);
        expect(_visibleNames(tester), ['Дом']);
        final tile = tester.widget<ListTile>(
          find.descendant(of: _list, matching: find.byType(ListTile)),
        );
        expect(tile.onTap, isNull);
        expect(tile.trailing, isNull);
        if (intentionId != null) {
          expect(_assignment(tester, _tag(2, 'Дом')), l10n.tagCatalogAssigned);
          expect(
            tester
                .widget<FilledButton>(
                  find.byKey(const ValueKey('tag-catalog-assign')),
                )
                .onPressed,
            isNull,
          );
        }

        await tester.enterText(_search, 'спорт');
        await tester.pump();
        expect(_visibleNames(tester), isEmpty);
        expect(find.text(l10n.tagCatalogUnavailable), findsOneWidget);
        expect(find.text(l10n.tagCatalogNoMatches), findsNothing);
        await tester.tap(find.text(l10n.commonRetry));
        await tester.pump();
        expect(find.text(l10n.tagCatalogRefreshing), findsOneWidget);
        expect(find.text(l10n.tagCatalogNoMatches), findsNothing);
        repository.complete([_tag(1, 'Рабочее'), _tag(2, 'Дом')], revision: 2);
        await tester.pumpAndSettle();
        expect(find.text(l10n.tagCatalogNoMatches), findsOneWidget);
        expect(tester.widget<TextField>(_search).controller!.text, 'спорт');
      },
    );

    testWidgets(
      '$description: реальный каталог включает неиспользуемые теги и назначения только в архиве, создание доступно из пустого результата',
      (tester) async {
        final router = await _pumpStoredCatalog(
          tester,
          intentionId: intentionId,
        );
        await tester.enterText(_search, 'дом');
        await tester.pump();
        expect(_visibleNames(tester), [
          'Дом 🏷️',
          'Дом без назначений',
          'Дом в архиве',
        ]);
        if (intentionId != null) {
          expect(_assignment(tester, _tag(301, 'Дом 🏷️')), 'Назначен');
          expect(
            _assignment(tester, _tag(303, 'Дом без назначений')),
            'Доступен для назначения',
          );
          expect(
            _assignment(tester, _tag(304, 'Дом в архиве')),
            intentionId == _intentionId(2)
                ? 'Назначен'
                : 'Доступен для назначения',
          );
        }

        await tester.enterText(_search, 'спорт');
        await tester.pump();
        expect(find.text('Теги не найдены'), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('tag-catalog-create')));
        await tester.pumpAndSettle();
        expect(router.current.name, TagEditorRoute.name);
        expect(find.byKey(const ValueKey('tag-editor-name')), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      '$description: ввод с emoji сохраняет область набора и исправляется после непарного surrogate',
      (tester) async {
        final repository = await _pumpCatalog(tester, intentionId: intentionId);
        repository.complete([_tag(1, 'Дом 😀'), _tag(2, 'Работа')]);
        await tester.pumpAndSettle();
        await tester.showKeyboard(_search);
        const input = TextEditingValue(
          text: 'ДОМ 😀',
          selection: TextSelection.collapsed(offset: 6),
          composing: TextRange(start: 4, end: 6),
        );
        tester.testTextInput.updateEditingValue(input);
        await tester.pump();
        expect(tester.widget<TextField>(_search).controller!.value, input);
        expect(_visibleNames(tester), ['Дом 😀']);

        final invalid = input.copyWith(
          text: 'ДОМ 😀\ud800',
          selection: const TextSelection.collapsed(offset: 7),
          composing: const TextRange(start: 4, end: 7),
        );
        tester.testTextInput.updateEditingValue(invalid);
        await tester.pump();
        expect(tester.widget<TextField>(_search).controller!.value, invalid);
        expect(_visibleNames(tester), ['Дом 😀']);
        expect(
          find.text(_localizations(tester).tagCatalogInvalidSearch),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);

        tester.testTextInput.updateEditingValue(input);
        await tester.pump();
        expect(tester.widget<TextField>(_search).controller!.value, input);
        expect(
          find.text(_localizations(tester).tagCatalogInvalidSearch),
          findsNothing,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  final secondIntention = _intentionId(2);
  for (final (description, before, after) in [
    ('из каталога в выбор', null, _modes[1].$2),
    ('другое намерение', _modes[1].$2, secondIntention),
    ('из выбора в каталог', _modes[2].$2, null),
  ]) {
    testWidgets('$description: смена экранной сессии сбрасывает поиск', (
      tester,
    ) async {
      final sessionIntention = ValueNotifier<IntentionId?>(before);
      addTearDown(sessionIntention.dispose);
      final repository = await _pumpCatalog(
        tester,
        intentionId: before,
        sessionIntention: sessionIntention,
      );
      final tags = [_tag(1, 'Дом'), _tag(2, 'Работа')];
      repository.complete(tags);
      await tester.pumpAndSettle();
      await tester.enterText(_search, 'дом');
      await tester.pump();
      final input = tester.widget<TextField>(_search).controller!;
      sessionIntention.value = after;
      await tester.pump();
      expect(tester.widget<TextField>(_search).controller, same(input));
      expect(input.text, isEmpty);
      repository.complete(tags, assignedIds: {tags.first.id});
      await tester.pumpAndSettle();
      expect(_visibleNames(tester), ['Дом', 'Работа']);
      if (after != null) {
        expect(_assignment(tester, tags.first), 'Назначен');
        expect(_assignment(tester, tags.last), 'Доступен для назначения');
      }
      expect(tester.takeException(), isNull);
    });
  }
}

AppLocalizations _localizations(WidgetTester tester) =>
    AppLocalizations.of(tester.element(find.byType(TagCatalogPage)));

Future<void> _pumpUntil(WidgetTester tester, bool Function() condition) async {
  for (var attempt = 0; attempt < 100 && !condition(); attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 20));
  }
  expect(condition(), isTrue);
}

Future<void> _beginRefresh(
  WidgetTester tester,
  TagCatalogTestRepository repository,
) async {
  final before = _tag(1, 'Работа');
  final after = _tag(1, 'Рабочее');
  final container = ProviderScope.containerOf(
    tester.element(find.byType(TagCatalogPage)),
  );
  final accepted =
      container
              .read(graphCommandCoordinatorProvider.notifier)
              .acceptTagRename(RenameTag(tagId: before.id, name: after.name))
          as TagCommandAccepted;
  repository.command.complete(
    TagCommandSucceeded(
      ConfirmedGraphResult(
        revision: const TagCatalogTestRevision(2),
        value: TagRenamed(
          TagRenamedChange(
            revision: const TagCatalogTestRevision(2),
            before: before,
            after: after,
          ),
        ),
      ),
    ),
  );
  await accepted.future;
  await tester.pump();
}

Future<AppRouter> _pumpStoredCatalog(
  WidgetTester tester, {
  IntentionId? intentionId,
}) async {
  late sqlite.Database raw;
  final database = AppDatabase(
    openInMemoryLocalDatabase(setup: (db) => raw = db),
  );
  await database.open();
  seedTagNavigationFixture(raw, extraPairsPerScope: 0);
  for (final (number, name) in [
    (303, 'Дом без назначений'),
    (304, 'Дом в архиве'),
  ]) {
    raw.execute('UPDATE tags SET name = ? WHERE id = ?', [name, _id(number)]);
  }
  final repository = DriftPersonalGraphRepository(
    database,
    UuidV7IntentionIdGenerator(),
    () => DateTime.utc(2026, 9, 28),
    InMemoryDiagnosticsSink(),
  );
  final router = AppRouter();
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    router.dispose();
    await database.close();
  });
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        personalGraphRepositoryProvider.overrideWithValue(repository),
      ],
      child: MaterialApp.router(
        locale: const Locale('ru'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router.config(
          deepLinkBuilder: (_) =>
              DeepLink([TagCatalogRoute(intentionId: intentionId)]),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return router;
}

Future<TagCatalogTestRepository> _pumpCatalog(
  WidgetTester tester, {
  IntentionId? intentionId,
  String language = 'ru',
  double scale = 1,
  AppRouter? router,
  ValueNotifier<IntentionId?>? sessionIntention,
}) async {
  final repository = TagCatalogTestRepository();
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    router?.dispose();
    await repository.dispose();
  });
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        personalGraphRepositoryProvider.overrideWithValue(repository),
      ],
      child: router == null
          ? MaterialApp(
              locale: Locale(language),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(scale)),
                child: child!,
              ),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: sessionIntention == null
                  ? TagCatalogPage(intentionId: intentionId)
                  : ValueListenableBuilder<IntentionId?>(
                      valueListenable: sessionIntention,
                      builder: (context, currentIntention, _) =>
                          TagCatalogPage(intentionId: currentIntention),
                    ),
            )
          : MaterialApp.router(
              locale: Locale(language),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              routerConfig: router.config(
                deepLinkBuilder: (_) =>
                    DeepLink([TagCatalogRoute(intentionId: intentionId)]),
              ),
            ),
    ),
  );
  if (router != null) await tester.pump();
  return repository;
}

Future<void> _reachSearchElement(WidgetTester tester, Finder finder) async {
  final scrollable = find
      .descendant(of: _list, matching: find.byType(Scrollable))
      .first;
  await tester.scrollUntilVisible(finder, 120, scrollable: scrollable);
  await Scrollable.ensureVisible(tester.element(finder), alignment: 0.5);
  await tester.pumpAndSettle();
  expect(finder.hitTestable(), findsOneWidget);
}

List<String> _visibleNames(WidgetTester tester) => [
  for (final tile in tester.widgetList<ListTile>(
    find.descendant(of: _list, matching: find.byType(ListTile)),
  ))
    (tile.title! as Text).data!,
];

Finder _row(Tag tag) =>
    find.byKey(ValueKey('tag-catalog-row-${tag.id.toCanonicalString()}'));

String _assignment(WidgetTester tester, Tag tag) =>
    (tester
                .widget<ListTile>(
                  find.descendant(
                    of: find.byKey(
                      ValueKey('tag-catalog-row-${tag.id.toCanonicalString()}'),
                    ),
                    matching: find.byType(ListTile),
                  ),
                )
                .subtitle!
            as Text)
        .data!;

TagCatalogLoaded _loaded(WidgetTester tester, IntentionId? intentionId) =>
    ProviderScope.containerOf(tester.element(find.byType(TagCatalogPage))).read(
      tagCatalogViewModelProvider(
        mode: intentionId == null
            ? const TagCatalogBrowseMode()
            : TagCatalogSelectionMode(intentionId),
      ),
    ) as TagCatalogLoaded;

String _id(int number) =>
    '018f0b5d-6b2e-7c80-8000-${number.toRadixString(16).padLeft(12, '0')}';

Tag _tag(int number, String name) => Tag(
  id: (TagId.decode(_id(number)) as TagIdDecodingSuccess).id,
  name: TagName.fromInput(name),
);
