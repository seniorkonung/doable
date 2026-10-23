import 'dart:async';

import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/src/design_system/components/tag_dot.dart';
import 'package:doable/src/design_system/components/tag_row.dart';
import 'package:doable/src/design_system/doable_theme.dart';
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/application/personal_graph_repository.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:doable/src/intention/application/intention_catalog.dart';
import 'package:doable/src/intention/application/intention_result.dart';
import 'package:doable/src/intention/presentation/catalog/intention_catalog_purpose.dart';
import 'package:doable/src/intention/presentation/catalog/intention_catalog_view_model.dart';
import 'package:doable/src/intention/presentation/catalog/intention_tag_conditions_section.dart';
import 'package:doable/src/intention/presentation/catalog/intention_tag_conditions_view_model.dart';
import 'package:doable/src/tag/application/tag_catalog.dart';
import 'package:doable/src/tag/domain/tag.dart';
import 'package:doable/src/tag/domain/tag_color.dart';
import 'package:doable/src/tag/domain/tag_id.dart';
import 'package:doable/src/tag/domain/tag_name.dart';
import 'package:doable/src/tag/presentation/panel/tags_panel_view_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/tag_catalog_test_repository.dart';
import '../../../support/inline_text.dart';
import '../../../support/tag_positions.dart';
import '../../../support/tag_condition_cycles.dart';

const _present = IntentionTagRequirement.mustBePresent;
const _absent = IntentionTagRequirement.mustBeAbsent;
const _purpose = BrowseIntentionCatalog();

final _section = find.byType(IntentionTagConditionsSection);
final _panel = find.byType(TagRow);
final _add = find.byKey(const ValueKey('intention-tag-conditions-add'));

void main() {
  testWidgets(
    'точки цветного и бесцветного тегов стоят перед названием при смене надобности',
    (tester) async {
      final h = await _open(tester);
      final home = _tag(1, 'Дом', color: TagColor.blue);
      final work = _tag(2, 'Работа');
      await h.select(home, _present);
      await h.select(work, _absent);

      void expectLabels(List<String> labels) {
        for (final (tag, color) in [
          (home, DoableTagColor.blue),
          (work, null),
        ]) {
          final dot = tester.widget<TagDot>(
            find.descendant(of: _chip(tag), matching: find.byType(TagDot)),
          );
          expect(dot.color, color);
          expect(dot.size, TagDotSize.medium);
        }
        expect([
          for (final text in tester.widgetList<Text>(
            find.byKey(const ValueKey('intention-tag-condition-label')),
          ))
            text.textSpan!.toPlainText(includeSemanticsLabels: false),
        ], labels);
      }

      expectLabels(['\uFFFCДом', 'не \uFFFCРабота']);

      await tester.tap(_toggle(home));
      await tester.tap(_toggle(work));
      await tester.pump();
      expectLabels(['не \uFFFCДом', '\uFFFCРабота']);
    },
  );

  testWidgets('без условий раздел показывает только кнопку «+ Тег»', (
    tester,
  ) async {
    final h = await _open(tester);

    expect(h.shown, isEmpty);
    expect(_add, findsOneWidget);
    expect(find.descendant(of: _add, matching: find.text('Тег')), findsOne);
    expect(
      find.descendant(of: _add, matching: find.byIcon(Icons.add)),
      findsOne,
    );
    expect(h.repository.tagCatalogReads, isEmpty);
  });

  testWidgets(
    'условия показаны чипами в порядке добавления со значком и текстом надобности',
    (tester) async {
      final h = await _open(tester);
      final health = _tag(1, 'Здоровье');
      final sport = _tag(2, 'Спорт');

      await h.select(sport, _absent);
      await h.select(health, _present);

      expect(h.shown, ['не Спорт', 'Здоровье']);
      // Надобность различима значком и словом «не», а не только цветом.
      expect(_chipIcon(health, Icons.check), findsOneWidget);
      expect(_chipIcon(health, Icons.block), findsNothing);
      expect(_chipIcon(sport, Icons.block), findsOneWidget);
      expect(_chipIcon(sport, Icons.check), findsNothing);
    },
  );

  testWidgets('много чипов и длинное название не выходят за ширину раздела', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(320, 800)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final h = await _open(tester);
    final long = _tag(9, 'Очень длинное название тега ' * 4);
    final tags = [
      for (var number = 1; number <= 6; number++) _tag(number, 'Тег $number'),
    ];
    for (final tag in tags) {
      await h.select(tag, _present);
    }
    await h.select(long, _absent);

    expect(tester.takeException(), isNull);
    final sectionRect = tester.getRect(_section);
    for (final tag in [...tags, long]) {
      final rect = tester.getRect(_chip(tag));
      expect(rect.left, greaterThanOrEqualTo(sectionRect.left));
      expect(rect.right, lessThanOrEqualTo(sectionRect.right));
    }
  });

  testWidgets(
    'нажатие на чип переключает надобность на прежнем месте и сразу применяет поиск',
    (tester) async {
      final h = await _open(tester);
      final health = _tag(1, 'Здоровье');
      final sport = _tag(2, 'Спорт');
      await h.select(health, _present);
      await h.select(sport, _absent);

      await tester.tap(_toggle(health));
      await tester.pump();

      expect(h.shown, ['не Здоровье', 'не Спорт']);
      expect(
        h.appliedFilter,
        IntentionTagFilter(excludedTagIds: [health.id, sport.id]),
      );

      await tester.tap(_toggle(health));
      await tester.pump();

      expect(h.shown, ['Здоровье', 'не Спорт']);
      expect(
        h.appliedFilter,
        IntentionTagFilter(
          requiredTagIds: [health.id],
          excludedTagIds: [sport.id],
        ),
      );
    },
  );

  testWidgets('крестик снимает условие', (tester) async {
    final h = await _open(tester);
    final health = _tag(1, 'Здоровье');
    final sport = _tag(2, 'Спорт');
    await h.select(health, _present);
    await h.select(sport, _absent);

    await tester.tap(_remove(sport));
    await tester.pump();
    expect(h.shown, ['Здоровье']);
    expect(h.appliedFilter, IntentionTagFilter(requiredTagIds: [health.id]));

    await tester.tap(_remove(health));
    await tester.pump();
    expect(h.shown, isEmpty);
    expect(h.appliedFilter, IntentionTagFilter.empty);
    expect(_add, findsOneWidget);
  });

  testWidgets(
    'кнопка «+ Тег» открывает панель фильтра с отметками текущих условий, а нажатия сразу применяют поиск',
    (tester) async {
      final h = await _open(tester);
      final health = _tag(1, 'Здоровье');
      final sport = _tag(2, 'Спорт');
      await h.select(sport, _absent);

      await h.openPanel([health, sport]);

      expect(find.text('Фильтр по тегам'), findsOneWidget);
      expect(h.marks, [TagRowFilterMark.none, TagRowFilterMark.mustBeAbsent]);

      // Первое нажатие добавляет условие в конец, второе меняет надобность
      // на прежнем месте.
      await tester.tap(_panelRow(health));
      await tester.pump();

      expect(h.marks, [
        TagRowFilterMark.mustBePresent,
        TagRowFilterMark.mustBeAbsent,
      ]);
      expect(h.shown, ['не Спорт', 'Здоровье']);
      expect(
        h.appliedFilter,
        IntentionTagFilter(
          requiredTagIds: [health.id],
          excludedTagIds: [sport.id],
        ),
      );

      await tester.tap(_panelRow(health));
      await tester.pump();

      expect(h.shown, ['не Спорт', 'не Здоровье']);
      expect(
        h.appliedFilter,
        IntentionTagFilter(excludedTagIds: [sport.id, health.id]),
      );
      expect(h.repository.commands, isEmpty);
    },
  );

  testWidgets(
    'закрытие панели фильтра без нажатий сохраняет условия и выдачу',
    (tester) async {
      final h = await _open(tester);
      final health = _tag(1, 'Здоровье');
      await h.select(health, _present);
      final queriesBefore = h.repository.queries.length;

      await h.openPanel([health]);
      await tester.tap(find.text('Готово'));
      await tester.pumpAndSettle();

      expect(_panel, findsNothing);
      expect(h.shown, ['Здоровье']);
      expect(h.repository.queries, hasLength(queriesBefore));
    },
  );

  testWidgets('раздел не читает каталог тегов и не выполняет команд тегов', (
    tester,
  ) async {
    final h = await _open(tester);
    final health = _tag(1, 'Здоровье');
    await h.select(health, _present);

    await tester.tap(_toggle(health));
    await tester.pump();
    await tester.tap(_remove(health));
    await tester.pump();

    expect(h.repository.tagCatalogReads, isEmpty);
    expect(h.repository.commands, isEmpty);
  });

  for (final (
        language,
        presentLabel,
        absentLabel,
        toggleHint,
        removeLabel,
        addLabel,
        visible,
      )
      in [
        (
          'ru',
          'Здоровье, должен быть',
          'Спорт, должен отсутствовать',
          'Переключить надобность: должен быть или должен отсутствовать',
          'Снять условие: Спорт',
          'Добавить условие по тегу',
          ['Здоровье', 'не Спорт'],
        ),
        (
          'en',
          'Здоровье, must be present',
          'Спорт, must be absent',
          'Toggle requirement: must be present or must be absent',
          'Remove condition: Спорт',
          'Add tag condition',
          ['Здоровье', 'not Спорт'],
        ),
      ]) {
    testWidgets(
      '$language: диктор читает надобность и назначение действий, ориентиры доступности выполнены',
      (tester) async {
        final handle = tester.ensureSemantics();
        final h = await _open(tester, language: language);
        await h.select(_tag(1, 'Здоровье'), _present);
        await h.select(_tag(2, 'Спорт'), _absent);

        // Названия тегов выводятся без перевода и преобразования.
        expect(h.shown, visible);
        for (final label in [presentLabel, absentLabel]) {
          expect(
            tester.getSemantics(find.bySemanticsLabel(label)),
            isSemantics(
              label: label,
              hint: toggleHint,
              isButton: true,
              hasTapAction: true,
            ),
          );
        }
        expect(
          tester.getSemantics(find.byTooltip(removeLabel)),
          isSemantics(
            tooltip: removeLabel,
            isButton: true,
            hasTapAction: true,
            hasEnabledState: true,
            isEnabled: true,
          ),
        );
        expect(
          tester.getSemantics(find.bySemanticsLabel(addLabel)),
          isSemantics(
            label: addLabel,
            isButton: true,
            hasTapAction: true,
            hasEnabledState: true,
            isEnabled: true,
          ),
        );

        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        await expectLater(tester, meetsGuideline(textContrastGuideline));
        handle.dispose();
      },
    );
  }
}

/// Личный граф с управляемыми чтениями и учётом всех команд.
final class _Repository extends Fake implements PersonalGraphRepository {
  final queries = <IntentionCatalogQuery>[];
  final tagCatalogReads = <Completer<TagCatalogResult>>[];
  final commands = <GraphCommand<GraphCommandOutcome, GraphCommandFailure>>[];

  @override
  Future<Result<IntentionCatalogPage>> getCatalogPage(
    IntentionCatalogQuery query,
  ) {
    queries.add(query);
    return Completer<Result<IntentionCatalogPage>>().future;
  }

  @override
  Future<TagCatalogResult> getTagCatalog(TagCatalogMode mode) {
    expect(mode, const TagCatalogBrowseMode());
    final read = Completer<TagCatalogResult>();
    tagCatalogReads.add(read);
    return read.future;
  }

  @override
  Future<GraphCommandResult<TSuccess, TFailure>> execute<
    TSuccess extends GraphCommandOutcome,
    TFailure extends GraphCommandFailure
  >(GraphCommand<TSuccess, TFailure> command) {
    commands.add(command);
    return Completer<GraphCommandResult<TSuccess, TFailure>>().future;
  }

  void completeTagCatalog(List<Tag> tags) {
    for (final read in tagCatalogReads.where((read) => !read.isCompleted)) {
      read.complete(
        TagCatalogSuccess(
          TagCatalogSnapshot(
            items: tags,
            revision: const TagCatalogTestRevision(),
          ),
        ),
      );
    }
  }
}

final class _Harness {
  _Harness(this.tester, this.repository);

  final WidgetTester tester;
  final _Repository repository;

  ProviderContainer get _container =>
      ProviderScope.containerOf(tester.element(_section));

  /// Тексты чипов в порядке показа.
  List<String> get shown => [
    for (final text in tester.widgetList<Text>(
      find.descendant(
        of: _section,
        matching: find.byKey(const ValueKey('intention-tag-condition-label')),
      ),
    ))
      textIgnoringInlineWidgets(text),
  ];

  /// Условия, с которыми модель каталога того же назначения читает выдачу.
  IntentionTagFilter get appliedFilter {
    final filter = _container
        .read(intentionCatalogViewModelProvider(_purpose).notifier)
        .selection
        .tagFilter;
    expect(repository.queries.last.tagFilter, filter);
    return filter;
  }

  /// Задаёт условие переключениями модели, как нажатиями в панели тегов:
  /// «должен отсутствовать» требует второго переключения.
  Future<void> select(Tag tag, IntentionTagRequirement requirement) async {
    final conditions = _container.read(
      intentionTagConditionsViewModelProvider(_purpose).notifier,
    );
    for (var i = 0; i < tagConditionCycles(requirement); i++) {
      conditions.cycle(tag, snapshotRevision: const TagCatalogTestRevision());
      await tester.pump();
    }
  }

  /// Отметки строк панели тегов в порядке показа.
  List<TagRowMark> get marks => [
    for (final row in tester.widgetList<TagRow>(_panel)) row.mark,
  ];

  Future<void> openPanel(List<Tag> tags) async {
    await tester.tap(_add);
    // Индикатор загрузки анимируется бесконечно: ждём только открытие панели.
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Фильтр по тегам'), findsOneWidget);
    repository.completeTagCatalog(tags);
    await tester.pumpAndSettle();
  }
}

Future<_Harness> _open(WidgetTester tester, {String language = 'ru'}) async {
  final repository = _Repository();
  final changes = StreamController<ConfirmedGraphChangePackage>.broadcast(
    sync: true,
  );
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await changes.close();
  });
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        personalGraphRepositoryProvider.overrideWithValue(repository),
        intentionTagConditionsChangesProvider.overrideWithValue(changes.stream),
        tagsPanelChangesProvider.overrideWithValue(changes.stream),
      ],
      child: MaterialApp(
        theme: doableTheme(Brightness.light),
        locale: Locale(language),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(
          body: SingleChildScrollView(
            padding: EdgeInsets.all(16),
            child: IntentionTagConditionsSection(purpose: _purpose),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  return _Harness(tester, repository);
}

Finder _chip(Tag tag) => find.byKey(
  ValueKey('intention-tag-condition-${tag.id.toCanonicalString()}'),
);

Finder _chipIcon(Tag tag, IconData icon) =>
    find.descendant(of: _toggle(tag), matching: find.byIcon(icon));

Finder _toggle(Tag tag) => find.byKey(
  ValueKey('intention-tag-condition-toggle-${tag.id.toCanonicalString()}'),
);

Finder _remove(Tag tag) => find.byKey(
  ValueKey('intention-tag-condition-remove-${tag.id.toCanonicalString()}'),
);

Finder _panelRow(Tag tag) =>
    find.byKey(ValueKey('tags-panel-row-${tag.id.toCanonicalString()}'));

TagId _id(int number) => (TagId.decode(
  '018f0b5d-6b2e-7c80-8000-${number.toRadixString(16).padLeft(12, '0')}',
) as TagIdDecodingSuccess).id;

Tag _tag(int number, String name, {TagColor? color}) => Tag(
  id: _id(number),
  name: TagName.fromInput(name),
  color: color,
  position: tagPositionAt(number),
);
