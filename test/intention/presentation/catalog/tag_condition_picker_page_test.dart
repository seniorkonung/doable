import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/src/app/navigation/app_destination.dart';
import 'package:doable/src/app/routing/app_router.gr.dart';
import 'package:doable/src/graph/application/graph_command_coordinator.dart';
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/application/personal_graph_repository.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:doable/src/intention/presentation/catalog/intention_tag_conditions_view_model.dart';
import 'package:doable/src/intention/presentation/catalog/tag_condition_picker_page.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/tag/application/tag_assignment_status.dart';
import 'package:doable/src/tag/application/tag_catalog.dart';
import 'package:doable/src/tag/application/tag_change.dart';
import 'package:doable/src/tag/application/tag_command.dart';
import 'package:doable/src/tag/application/tag_read_result.dart';
import 'package:doable/src/tag/application/tag_result.dart';
import 'package:doable/src/tag/domain/tag.dart';
import 'package:doable/src/tag/domain/tag_id.dart';
import 'package:doable/src/tag/domain/tag_name.dart';
import 'package:doable/src/tag/presentation/catalog/tag_catalog_page.dart';
import 'package:doable/src/tag/presentation/catalog/tag_catalog_state.dart';
import 'package:doable/src/tag/presentation/catalog/tag_catalog_view_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/tag_catalog_test_repository.dart';

const _present = IntentionTagRequirement.mustBePresent;
const _absent = IntentionTagRequirement.mustBeAbsent;

final _picker = find.byType(TagConditionPickerPage);
final _search = find.byKey(const ValueKey('tag-condition-picker-search'));
final _list = find.byKey(const ValueKey('tag-condition-picker-list'));

void main() {
  for (final (requirement, label) in [(_present, 'Есть'), (_absent, 'Нет')]) {
    testWidgets(
      'выбор «$label» закрывает экран и возвращает тег, надобность и ревизию снимка',
      (tester) async {
        final h = await _open(tester);
        final sport = _tag(2, 'Спорт');
        h.repository.completePending([_tag(1, 'Здоровье'), sport], revision: 7);
        await tester.pumpAndSettle();

        await tester.tap(_action(sport, requirement));
        await tester.pumpAndSettle();

        final selection = (await h.result)!;
        expect(selection.tag.id, sport.id);
        expect(selection.tag.name.value, 'Спорт');
        expect(selection.requirement, requirement);
        expect(
          selection.snapshotRevision.compareTo(const TagCatalogTestRevision(7)),
          GraphRevisionOrder.same,
        );
        expect(_picker, findsNothing);
        expect(h.repository.commands, isEmpty);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('закрытие без выбора ничего не возвращает', (tester) async {
    final h = await _open(tester);
    h.repository.completePending([_tag(1, 'Здоровье')]);
    await tester.pumpAndSettle();

    await tester.tap(
      find.descendant(of: _picker, matching: find.byType(BackButton)),
    );
    await tester.pumpAndSettle();

    expect(await h.result, isNull);
    expect(_picker, findsNothing);
    expect(h.repository.commands, isEmpty);
  });

  testWidgets(
    'все теги показаны в порядке снимка, а поиск сужает их по названию без учёта регистра',
    (tester) async {
      final h = await _open(tester);
      h.repository.completePending([
        _tag(3, 'Спорт'),
        _tag(1, 'Здоровье'),
        _tag(2, 'Здоровый сон'),
      ]);
      await tester.pumpAndSettle();
      expect(_visibleNames(tester), ['Спорт', 'Здоровье', 'Здоровый сон']);

      await tester.enterText(_search, 'ЗДОРОВ');
      await tester.pump();
      expect(_visibleNames(tester), ['Здоровье', 'Здоровый сон']);

      await tester.tap(find.byTooltip('Очистить поиск тегов'));
      await tester.pump();
      expect(_visibleNames(tester), ['Спорт', 'Здоровье', 'Здоровый сон']);
      // Сужение списка не перечитывает каталог тегов.
      expect(h.repository.reads, hasLength(2));
    },
  );

  testWidgets(
    'недопустимый ввод сохраняет результаты последнего корректного запроса',
    (tester) async {
      final h = await _open(tester);
      h.repository.completePending([_tag(1, 'Здоровье'), _tag(2, 'Спорт')]);
      await tester.pumpAndSettle();
      await tester.enterText(_search, 'спо');
      await tester.pump();

      await tester.enterText(_search, 'спо\u0000');
      await tester.pump();

      expect(_visibleNames(tester), ['Спорт']);
      expect(
        find.textContaining('Недопустимые символы показаны'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('тег из условий вызвавшего поиска отмечен текущей надобностью', (
    tester,
  ) async {
    final health = _tag(1, 'Здоровье');
    final sport = _tag(2, 'Спорт');
    final rest = _tag(3, 'Отдых');
    final h = await _open(
      tester,
      conditions: [_condition(health, _present), _condition(sport, _absent)],
    );
    h.repository.completePending([health, sport, rest]);
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: _row(health),
        matching: find.text('Уже выбран: должен быть'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: _row(sport),
        matching: find.text('Уже выбран: должен отсутствовать'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: _row(rest),
        matching: find.textContaining('Уже выбран'),
      ),
      findsNothing,
    );
    expect(tester.widget<Semantics>(_row(health)).properties.selected, true);
    expect(tester.widget<Semantics>(_row(sport)).properties.selected, true);
    expect(tester.widget<Semantics>(_row(rest)).properties.selected, false);

    // Отмеченный тег можно выбрать снова с другой надобностью.
    await tester.tap(_action(health, _absent));
    await tester.pumpAndSettle();
    final selection = (await h.result)!;
    expect(selection.tag.id, health.id);
    expect(selection.requirement, _absent);
  });

  testWidgets('загрузка и пустой каталог различимы', (tester) async {
    final h = await _open(tester);
    expect(_inPicker('Загружаем теги…'), findsOneWidget);
    expect(_inPicker('Тегов пока нет.'), findsNothing);

    h.repository.completePending([]);
    await tester.pumpAndSettle();
    expect(_inPicker('Тегов пока нет.'), findsOneWidget);
    expect(_inPicker('Теги не найдены'), findsNothing);
    // Пустой каталог сужать нечем: поиск не сообщает об отсутствии совпадений.
    await tester.enterText(_search, 'спорт');
    await tester.pump();
    expect(_inPicker('Тегов пока нет.'), findsOneWidget);
    expect(_inPicker('Теги не найдены'), findsNothing);
  });

  testWidgets('отсутствие совпадений отличается от пустого каталога', (
    tester,
  ) async {
    final h = await _open(tester);
    h.repository.completePending([_tag(1, 'Здоровье')]);
    await tester.pumpAndSettle();

    await tester.enterText(_search, 'спорт');
    await tester.pump();

    expect(_inPicker('Теги не найдены'), findsOneWidget);
    expect(_inPicker('Тегов пока нет.'), findsNothing);
    expect(_visibleNames(tester), isEmpty);
  });

  testWidgets(
    'недоступность хранилища показана с повтором и не выглядит пустым каталогом',
    (tester) async {
      final h = await _open(tester);
      h.repository.failPending(const TagCatalogUnavailableFailure());
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: _picker,
          matching: find.text('Не удалось загрузить теги. Повторите попытку.'),
        ),
        findsOneWidget,
      );
      expect(_inPicker('Тегов пока нет.'), findsNothing);
      final readsBefore = h.repository.reads.length;

      await tester.tap(
        find.descendant(of: _picker, matching: find.text('Повторить')),
      );
      await tester.pump();
      expect(h.repository.reads, hasLength(readsBefore + 1));
      h.repository.completePending([_tag(1, 'Здоровье')]);
      await tester.pumpAndSettle();

      expect(_visibleNames(tester), ['Здоровье']);
      expect(h.repository.commands, isEmpty);
    },
  );

  for (final (failure, message) in <(TagCatalogReadFailure, String)>[
    (
      const TagCatalogCorruptionFailure(),
      'Сохранённые данные тегов повреждены и не могут быть показаны.',
    ),
    (
      const TagCatalogUnexpectedFailure(),
      'Не удалось загрузить теги из-за непредвиденной ошибки.',
    ),
  ]) {
    testWidgets('отказ ${failure.category.name} показан без повтора', (
      tester,
    ) async {
      final h = await _open(tester);
      h.repository.failPending(failure);
      await tester.pumpAndSettle();

      expect(
        find.descendant(of: _picker, matching: find.text(message)),
        findsOneWidget,
      );
      expect(
        find.descendant(of: _picker, matching: find.text('Повторить')),
        findsNothing,
      );
      expect(_inPicker('Тегов пока нет.'), findsNothing);
    });
  }

  testWidgets(
    'отказ обновления сохраняет список и предлагает повтор при недоступности',
    (tester) async {
      final h = await _open(tester);
      final health = _tag(1, 'Здоровье');
      final sport = _tag(2, 'Спорт');
      h.repository.completePending([health, sport]);
      await tester.pumpAndSettle();

      await h.confirm(
        (coordinator) => coordinator.acceptTagDelete(DeleteTag(sport.id)),
        (revision) =>
            TagDeleted(TagDeletedChange(revision: revision, tagId: sport.id)),
        revision: 2,
      );
      await tester.pump();
      h.repository.failPending(const TagCatalogUnavailableFailure());
      await tester.pumpAndSettle();

      expect(_visibleNames(tester), ['Здоровье']);
      expect(
        find.descendant(
          of: _picker,
          matching: find.text('Не удалось загрузить теги. Повторите попытку.'),
        ),
        findsOneWidget,
      );
      await tester.tap(
        find.descendant(of: _picker, matching: find.text('Повторить')),
      );
      await tester.pump();
      h.repository.completePending([health], revision: 2);
      await tester.pumpAndSettle();

      expect(_visibleNames(tester), ['Здоровье']);
      expect(
        find.descendant(of: _picker, matching: find.text('Повторить')),
        findsNothing,
      );
    },
  );

  testWidgets(
    'подтверждённые переименование, удаление и создание согласуют открытый список',
    (tester) async {
      final h = await _open(tester);
      final health = _tag(1, 'Здоровье');
      final sport = _tag(2, 'Спорт');
      h.repository.completePending([health, sport]);
      await tester.pumpAndSettle();

      final renamed = _tag(1, 'Самочувствие');
      await h.confirm(
        (coordinator) => coordinator.acceptTagRename(
          RenameTag(tagId: health.id, name: renamed.name),
        ),
        (revision) => TagRenamed(
          TagRenamedChange(revision: revision, before: health, after: renamed),
        ),
        revision: 2,
      );
      await tester.pump();
      expect(_visibleNames(tester), ['Самочувствие', 'Спорт']);
      h.repository.completePending([renamed, sport], revision: 2);
      await tester.pumpAndSettle();

      await h.confirm(
        (coordinator) => coordinator.acceptTagDelete(DeleteTag(sport.id)),
        (revision) =>
            TagDeleted(TagDeletedChange(revision: revision, tagId: sport.id)),
        revision: 3,
      );
      await tester.pump();
      expect(_visibleNames(tester), ['Самочувствие']);
      h.repository.completePending([renamed], revision: 3);
      await tester.pumpAndSettle();

      final rest = _tag(3, 'Отдых');
      await h.confirm(
        (coordinator) => coordinator.acceptTagCreation(
          TagCreationFormKey(),
          CreateTag(rest.name),
        ),
        (revision) =>
            TagCreated(TagCreatedChange(revision: revision, after: rest)),
        revision: 4,
      );
      await tester.pump();
      h.repository.completePending([renamed, rest], revision: 4);
      await tester.pumpAndSettle();
      expect(_visibleNames(tester), ['Самочувствие', 'Отдых']);

      // Выбор после согласования несёт актуальное название и ревизию снимка.
      await tester.tap(_action(renamed, _present));
      await tester.pumpAndSettle();
      final selection = (await h.result)!;
      expect(selection.tag.name.value, 'Самочувствие');
      expect(
        selection.snapshotRevision.compareTo(const TagCatalogTestRevision(4)),
        GraphRevisionOrder.same,
      );
    },
  );

  testWidgets(
    'состояние экрана не разделяется с каталогом тегов и другими открытиями',
    (tester) async {
      final h = await _open(tester);
      final tags = [_tag(1, 'Здоровье'), _tag(2, 'Спорт')];
      // Каталог тегов под экраном и сам экран читают каталог независимо.
      expect(h.repository.reads, hasLength(2));
      h.repository.completePending(tags);
      await tester.pumpAndSettle();
      await tester.enterText(_search, 'спорт');
      await tester.pump();
      final firstInput = tester.widget<TextField>(_search).controller!;

      unawaited(
        h.router.push<IntentionTagConditionSelection>(
          TagConditionPickerRoute(conditions: const []),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      // Второе открытие получает собственное состояние и собственное чтение.
      expect(h.repository.reads, hasLength(3));
      expect(
        find.descendant(of: _picker, matching: find.text('Загружаем теги…')),
        findsOneWidget,
      );
      h.repository.completePending(tags);
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(_search).controller!.text, isEmpty);
      expect(_visibleNames(tester), ['Здоровье', 'Спорт']);

      await h.router.maybePop();
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(_search).controller, same(firstInput));
      expect(_visibleNames(tester), ['Спорт']);

      // Выбор не выделяет тег в каталоге тегов и не меняет его состояние.
      await tester.tap(_action(tags[1], _present));
      await tester.pumpAndSettle();
      expect((await h.result)!.tag.id, tags[1].id);
      final catalog = ProviderScope.containerOf(
        tester.element(find.byType(TagCatalogPage)),
      ).read(tagCatalogViewModelProvider()) as TagCatalogLoaded;
      expect(catalog.selection, isA<TagCatalogNoSelection>());
      expect(catalog.items.map((tag) => tag.name.value), ['Здоровье', 'Спорт']);
      expect(find.byKey(const ValueKey('tag-catalog-search')), findsOneWidget);
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('tag-catalog-search')))
            .controller!
            .text,
        isEmpty,
      );
    },
  );

  testWidgets('экран не предлагает действий с тегами и не выполняет команд', (
    tester,
  ) async {
    final h = await _open(tester);
    final health = _tag(1, 'Здоровье');
    h.repository.completePending([health]);
    await tester.pumpAndSettle();

    for (final tooltip in ['Создать тег', 'Переименовать тег', 'Удалить тег']) {
      expect(
        find.descendant(of: _picker, matching: find.byTooltip(tooltip)),
        findsNothing,
      );
    }
    expect(
      find.descendant(of: _picker, matching: find.text('Назначить тег')),
      findsNothing,
    );
    // Нажатие на строку вне действий ничего не выбирает.
    await tester.tap(find.descendant(of: _row(health), matching: _name));
    await tester.pumpAndSettle();
    expect(_picker, findsOneWidget);

    await tester.tap(_action(health, _absent));
    await tester.pumpAndSettle();
    expect(await h.result, isNotNull);
    expect(h.repository.commands, isEmpty);
    expect(h.repository.statusQueries, isEmpty);
    expect(h.repository.observations, isEmpty);
  });

  for (final (language, present, absent, title, mark) in [
    (
      'ru',
      'Есть',
      'Нет',
      'Тег для условия поиска',
      'Уже выбран: должен отсутствовать',
    ),
    (
      'en',
      'With',
      'Without',
      'Tag for search condition',
      'Already selected: must be absent',
    ),
  ]) {
    testWidgets(
      '$language: подписи локализованы, диктор читает действия вместе с названием тега',
      (tester) async {
        final handle = tester.ensureSemantics();
        final sport = _tag(2, 'Спорт');
        final h = await _open(
          tester,
          language: language,
          conditions: [_condition(sport, _absent)],
        );
        h.repository.completePending([sport]);
        await tester.pumpAndSettle();

        expect(find.text(title), findsOneWidget);
        expect(find.text(mark), findsOneWidget);
        expect(
          find.descendant(of: _row(sport), matching: find.text(present)),
          findsOneWidget,
        );
        expect(
          find.descendant(of: _row(sport), matching: find.text(absent)),
          findsOneWidget,
        );
        // Название тега выводится без перевода и преобразования.
        expect(
          find.descendant(of: _row(sport), matching: find.text('Спорт')),
          findsOneWidget,
        );
        for (final label in ['$present, Спорт', '$absent, Спорт']) {
          expect(
            tester.getSemantics(find.bySemanticsLabel(label)),
            isSemantics(
              label: label,
              isButton: true,
              hasTapAction: true,
              hasEnabledState: true,
              isEnabled: true,
            ),
          );
        }
        handle.dispose();
      },
    );
  }
}

final _name = find.byKey(const ValueKey('tag-condition-picker-name'));

Finder _inPicker(String text) =>
    find.descendant(of: _picker, matching: find.text(text));

/// Каталог тегов с управляемыми чтениями и учётом всех остальных обращений.
final class _Repository extends Fake implements PersonalGraphRepository {
  final reads = <Completer<TagCatalogResult>>[];
  final commands = <GraphCommand<GraphCommandOutcome, GraphCommandFailure>>[];
  final statusQueries = <(TagId, IntentionId)>[];
  final observations = <TagId>[];
  final _commandResults = <Completer<TagCommandResult>>[];

  @override
  Future<TagCatalogResult> getTagCatalog(TagCatalogMode mode) {
    expect(mode, const TagCatalogBrowseMode());
    final read = Completer<TagCatalogResult>();
    reads.add(read);
    return read.future;
  }

  @override
  Stream<TagReadResult> watchTag(TagId id) {
    observations.add(id);
    return const Stream.empty();
  }

  @override
  Future<TagAssignmentStatusResult> getTagAssignmentStatus(
    TagId tagId,
    IntentionId intentionId,
  ) {
    statusQueries.add((tagId, intentionId));
    return Completer<TagAssignmentStatusResult>().future;
  }

  @override
  Future<GraphCommandResult<TSuccess, TFailure>> execute<
    TSuccess extends GraphCommandOutcome,
    TFailure extends GraphCommandFailure
  >(GraphCommand<TSuccess, TFailure> command) async {
    commands.add(command);
    final result = Completer<TagCommandResult>();
    _commandResults.add(result);
    return await result.future as GraphCommandResult<TSuccess, TFailure>;
  }

  void completeCommand(TagCommandResult result) =>
      _commandResults.last.complete(result);

  Iterable<Completer<TagCatalogResult>> get _pending =>
      reads.where((read) => !read.isCompleted).toList();

  /// Завершает каждое ожидающее чтение каталога одним и тем же снимком.
  void completePending(List<Tag> tags, {int revision = 1}) {
    for (final read in _pending) {
      read.complete(
        TagCatalogSuccess(
          TagCatalogSnapshot(
            items: tags,
            revision: TagCatalogTestRevision(revision),
          ),
        ),
      );
    }
  }

  void failPending(TagCatalogReadFailure failure) {
    for (final read in _pending) {
      read.complete(TagCatalogError(failure));
    }
  }
}

final class _Harness {
  _Harness(this.tester, this.repository, this.router, this.result);

  final WidgetTester tester;
  final _Repository repository;
  final RootStackRouter router;
  final Future<IntentionTagConditionSelection?> result;

  /// Подтверждает команду тега от имени другого экрана приложения.
  Future<void> confirm(
    TagCommandStart Function(GraphCommandCoordinator) accept,
    TagCommandSuccess Function(TagCatalogTestRevision) success, {
    required int revision,
  }) async {
    final coordinator = ProviderScope.containerOf(tester.element(_picker))
        .read(graphCommandCoordinatorProvider.notifier);
    final accepted = accept(coordinator) as TagCommandAccepted;
    await tester.pump();
    final confirmed = TagCatalogTestRevision(revision);
    repository.completeCommand(
      TagCommandSucceeded(
        ConfirmedGraphResult(revision: confirmed, value: success(confirmed)),
      ),
    );
    await accepted.future;
  }
}

Future<_Harness> _open(
  WidgetTester tester, {
  String language = 'ru',
  List<IntentionTagCondition> conditions = const [],
}) async {
  final repository = _Repository();
  final router = RootStackRouter.build(
    routes: [
      AutoRoute(
        page: AppShellRoute.page,
        initial: true,
        children: [
          for (final destination in AppDestination.values)
            NamedRouteDef(
              name: destination.page.name,
              builder: (_, _) => const Scaffold(),
            ),
        ],
      ),
      AutoRoute(page: TagCatalogRoute.page),
      AutoRoute(page: TagConditionPickerRoute.page),
    ],
  );
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    router.dispose();
  });
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        personalGraphRepositoryProvider.overrideWithValue(repository),
      ],
      child: MaterialApp.router(
        locale: Locale(language),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router.config(
          deepLinkBuilder: (_) =>
              DeepLink([const AppShellRoute(), TagCatalogRoute()]),
        ),
      ),
    ),
  );
  await tester.pump();
  final result = router.push<IntentionTagConditionSelection>(
    TagConditionPickerRoute(conditions: conditions),
  );
  // Индикатор загрузки анимируется бесконечно: ждём только переход маршрута.
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
  return _Harness(tester, repository, router, result);
}

List<String> _visibleNames(WidgetTester tester) => [
  for (final text in tester.widgetList<Text>(
    find.descendant(of: _list, matching: _name),
  ))
    text.data!,
];

Finder _row(Tag tag) => find.byKey(
  ValueKey('tag-condition-picker-row-${tag.id.toCanonicalString()}'),
);

Finder _action(Tag tag, IntentionTagRequirement requirement) => find.byKey(
  ValueKey(
    'tag-condition-picker-${requirement.name}-${tag.id.toCanonicalString()}',
  ),
);

IntentionTagCondition _condition(
  Tag tag,
  IntentionTagRequirement requirement,
) => IntentionTagCondition(
  tagId: tag.id,
  requirement: requirement,
  name: tag.name,
  isDeleted: false,
);

TagId _id(int number) => (TagId.decode(
  '018f0b5d-6b2e-7c80-8000-${number.toRadixString(16).padLeft(12, '0')}',
) as TagIdDecodingSuccess).id;

Tag _tag(int number, String name) =>
    Tag(id: _id(number), name: TagName.fromInput(name));
