import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/src/app/routing/app_router.gr.dart';
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
import 'package:doable/src/intention/presentation/catalog/tag_condition_picker_page.dart';
import 'package:doable/src/tag/application/tag_catalog.dart';
import 'package:doable/src/tag/application/tag_change.dart';
import 'package:doable/src/tag/application/tag_read_result.dart';
import 'package:doable/src/tag/domain/tag.dart';
import 'package:doable/src/tag/domain/tag_id.dart';
import 'package:doable/src/tag/domain/tag_name.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/tag_catalog_test_repository.dart';

const _present = IntentionTagRequirement.mustBePresent;
const _absent = IntentionTagRequirement.mustBeAbsent;
const _purpose = BrowseIntentionCatalog();

final _section = find.byType(IntentionTagConditionsSection);
final _picker = find.byType(TagConditionPickerPage);
final _add = find.byKey(const ValueKey('intention-tag-conditions-add'));

void main() {
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
      // Кнопка добавления стоит после чипов.
      expect(_precedes(tester, _chip(health), _add), isTrue);
    },
  );

  testWidgets(
    'удалённый тег показан последним известным названием с пометкой и прежней надобностью',
    (tester) async {
      final h = await _open(tester);
      final health = _tag(1, 'Здоровье');
      final sport = _tag(2, 'Спорт');
      await h.select(health, _present);
      await h.select(sport, _absent);

      await h.delete(health, revision: 2);
      await h.delete(sport, revision: 3);

      expect(h.shown, ['Здоровье (тег удалён)', 'не Спорт (тег удалён)']);
      expect(_chipIcon(health, Icons.check), findsOneWidget);
      expect(_chipIcon(sport, Icons.block), findsOneWidget);
    },
  );

  testWidgets(
    'чипы переносятся на новые строки, а длинное название не выходит за ширину',
    (tester) async {
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
      final tops = {for (final tag in tags) tester.getTopLeft(_chip(tag)).dy};
      expect(tops.length, greaterThan(1));
      for (var index = 1; index < tags.length; index++) {
        expect(
          _precedes(tester, _chip(tags[index - 1]), _chip(tags[index])),
          isTrue,
        );
      }
      final sectionRect = tester.getRect(_section);
      for (final tag in [...tags, long]) {
        final rect = tester.getRect(_chip(tag));
        expect(rect.left, greaterThanOrEqualTo(sectionRect.left));
        expect(rect.right, lessThanOrEqualTo(sectionRect.right));
      }
      // Длинное название переносится внутри чипа и не обрезается.
      expect(
        tester.getSize(_chip(long)).height,
        greaterThan(tester.getSize(_chip(tags.first)).height),
      );
      expect(_precedes(tester, _chip(long), _add), isTrue);
    },
  );

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
      expect(h.repository.commands, isEmpty);
    },
  );

  testWidgets('крестик снимает условие, в том числе удалённого тега', (
    tester,
  ) async {
    final h = await _open(tester);
    final health = _tag(1, 'Здоровье');
    final sport = _tag(2, 'Спорт');
    await h.select(health, _present);
    await h.select(sport, _absent);
    await h.delete(health, revision: 2);

    await tester.tap(_remove(sport));
    await tester.pump();
    expect(h.shown, ['Здоровье (тег удалён)']);
    expect(h.appliedFilter, IntentionTagFilter(requiredTagIds: [health.id]));

    await tester.tap(_remove(health));
    await tester.pump();
    expect(h.shown, isEmpty);
    expect(h.appliedFilter, IntentionTagFilter.empty);
    expect(_add, findsOneWidget);
    expect(h.repository.commands, isEmpty);
  });

  testWidgets(
    'кнопка «+ Тег» открывает экран поиска тега с текущими условиями и передаёт выбор модели',
    (tester) async {
      final h = await _open(tester);
      final health = _tag(1, 'Здоровье');
      final sport = _tag(2, 'Спорт');
      await h.select(sport, _absent);

      await h.openPicker([health, sport]);

      expect(
        tester
            .widget<TagConditionPickerPage>(_picker)
            .conditions
            .map((condition) => (condition.tagId, condition.requirement)),
        [(sport.id, _absent)],
      );
      expect(
        find.descendant(
          of: _picker,
          matching: find.text('Уже выбран: должен отсутствовать'),
        ),
        findsOneWidget,
      );

      await tester.tap(_pickerAction(health, _present));
      await tester.pumpAndSettle();

      expect(_picker, findsNothing);
      expect(h.shown, ['не Спорт', 'Здоровье']);
      expect(
        h.appliedFilter,
        IntentionTagFilter(
          requiredTagIds: [health.id],
          excludedTagIds: [sport.id],
        ),
      );
      expect(h.repository.commands, isEmpty);
    },
  );

  testWidgets(
    'повторный выбор тега на экране поиска меняет надобность существующего чипа',
    (tester) async {
      final h = await _open(tester);
      final health = _tag(1, 'Здоровье');
      final sport = _tag(2, 'Спорт');
      await h.select(health, _present);
      await h.select(sport, _absent);

      await h.openPicker([health, sport]);
      await tester.tap(_pickerAction(health, _absent));
      await tester.pumpAndSettle();

      expect(h.shown, ['не Здоровье', 'не Спорт']);
    },
  );

  testWidgets('закрытие экрана поиска тега без выбора сохраняет условия', (
    tester,
  ) async {
    final h = await _open(tester);
    final health = _tag(1, 'Здоровье');
    await h.select(health, _present);
    final queriesBefore = h.repository.queries.length;

    await h.openPicker([health]);
    await tester.tap(
      find.descendant(of: _picker, matching: find.byType(BackButton)),
    );
    await tester.pumpAndSettle();

    expect(_picker, findsNothing);
    expect(h.shown, ['Здоровье']);
    expect(h.repository.queries, hasLength(queriesBefore));
    expect(h.repository.commands, isEmpty);
  });

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
        deletedLabel,
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
          'Отдых, должен отсутствовать, тег удалён',
          'Переключить надобность: должен быть или должен отсутствовать',
          'Снять условие: Спорт',
          'Добавить условие по тегу',
          ['Здоровье', 'не Спорт', 'не Отдых (тег удалён)'],
        ),
        (
          'en',
          'Здоровье, must be present',
          'Спорт, must be absent',
          'Отдых, must be absent, tag deleted',
          'Toggle requirement: must be present or must be absent',
          'Remove condition: Спорт',
          'Add tag condition',
          ['Здоровье', 'not Спорт', 'not Отдых (tag deleted)'],
        ),
      ]) {
    testWidgets(
      '$language: диктор читает надобность, пометку удаления и назначение действий, ориентиры доступности выполнены',
      (tester) async {
        final handle = tester.ensureSemantics();
        final h = await _open(tester, language: language);
        final rest = _tag(3, 'Отдых');
        await h.select(_tag(1, 'Здоровье'), _present);
        await h.select(_tag(2, 'Спорт'), _absent);
        await h.select(rest, _absent);
        await h.delete(rest, revision: 2);

        // Названия тегов выводятся без перевода и преобразования.
        expect(h.shown, visible);
        for (final label in [presentLabel, absentLabel, deletedLabel]) {
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

  /// Уточнение выбора из снимка остаётся без ответа: условие не меняется.
  @override
  Stream<TagReadResult> watchTag(TagId id) => const Stream.empty();

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

/// Раздел на странице, с которой доступен настоящий маршрут поиска тега.
final class _Router extends RootStackRouter {
  @override
  List<AutoRoute> get routes => [
    NamedRouteDef(
      name: 'ConditionsHostRoute',
      path: '/',
      builder: (_, _) => const Scaffold(
        body: SingleChildScrollView(
          padding: EdgeInsets.all(16),
          child: IntentionTagConditionsSection(purpose: _purpose),
        ),
      ),
    ),
    AutoRoute(page: TagConditionPickerRoute.page),
  ];
}

final class _Harness {
  _Harness(this.tester, this.repository, this.changes);

  final WidgetTester tester;
  final _Repository repository;
  final StreamController<ConfirmedGraphChangePackage> changes;

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
      text.data!,
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

  /// Передаёт модели выбор так же, как его возвращает экран поиска тега.
  Future<void> select(Tag tag, IntentionTagRequirement requirement) async {
    _container
        .read(intentionTagConditionsViewModelProvider(_purpose).notifier)
        .applySelection(
          IntentionTagConditionSelection(
            tag: tag,
            requirement: requirement,
            snapshotRevision: const TagCatalogTestRevision(),
          ),
        );
    await tester.pump();
  }

  /// Подтверждает физическое удаление тега другим экраном приложения.
  Future<void> delete(Tag tag, {required int revision}) async {
    final confirmed = TagCatalogTestRevision(revision);
    changes.add(
      _Package(confirmed, [
        TagDeletedChange(revision: confirmed, tagId: tag.id),
      ]),
    );
    await tester.pump();
  }

  Future<void> openPicker(List<Tag> tags) async {
    await tester.tap(_add);
    // Индикатор загрузки анимируется бесконечно: ждём только переход маршрута.
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(_picker, findsOneWidget);
    repository.completeTagCatalog(tags);
    await tester.pumpAndSettle();
  }
}

Future<_Harness> _open(WidgetTester tester, {String language = 'ru'}) async {
  final repository = _Repository();
  final changes = StreamController<ConfirmedGraphChangePackage>.broadcast(
    sync: true,
  );
  final router = _Router();
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    router.dispose();
    await changes.close();
  });
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        personalGraphRepositoryProvider.overrideWithValue(repository),
        intentionTagConditionsChangesProvider.overrideWithValue(changes.stream),
      ],
      child: MaterialApp.router(
        locale: Locale(language),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router.config(),
      ),
    ),
  );
  await tester.pump();
  return _Harness(tester, repository, changes);
}

final class _Package implements ConfirmedGraphChangePackage {
  const _Package(this.revision, this.changes);
  @override
  final GraphRevision revision;
  @override
  final List<GraphChange> changes;
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

Finder _pickerAction(Tag tag, IntentionTagRequirement requirement) =>
    find.byKey(
      ValueKey(
        'tag-condition-picker-${requirement.name}-'
        '${tag.id.toCanonicalString()}',
      ),
    );

/// Первый элемент стоит раньше второго в порядке чтения: выше либо левее.
bool _precedes(WidgetTester tester, Finder first, Finder second) {
  final a = tester.getRect(first);
  final b = tester.getRect(second);
  return a.bottom <= b.top || (a.top < b.bottom && a.left < b.left);
}

TagId _id(int number) => (TagId.decode(
  '018f0b5d-6b2e-7c80-8000-${number.toRadixString(16).padLeft(12, '0')}',
) as TagIdDecodingSuccess).id;

Tag _tag(int number, String name) =>
    Tag(id: _id(number), name: TagName.fromInput(name));
