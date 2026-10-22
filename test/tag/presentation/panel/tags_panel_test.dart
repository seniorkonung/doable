import 'dart:async';

import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/src/design_system/components/empty_state.dart';
import 'package:doable/src/design_system/components/list_state.dart';
import 'package:doable/src/design_system/components/notice.dart';
import 'package:doable/src/design_system/components/sheet.dart';
import 'package:doable/src/design_system/components/tag_dot.dart';
import 'package:doable/src/design_system/components/tag_row.dart';
import 'package:doable/src/design_system/doable_theme.dart';
import 'package:doable/src/graph/application/graph_change.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:doable/src/graph/presentation/graph_operation_presenter.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/tag/application/tag_catalog.dart';
import 'package:doable/src/tag/application/tag_change.dart';
import 'package:doable/src/tag/application/tag_command.dart';
import 'package:doable/src/tag/application/tag_result.dart';
import 'package:doable/src/tag/domain/tag.dart';
import 'package:doable/src/tag/domain/tag_color.dart';
import 'package:doable/src/tag/domain/tag_id.dart';
import 'package:doable/src/tag/domain/tag_name.dart';
import 'package:doable/src/tag/presentation/panel/tags_panel.dart';
import 'package:doable/src/tag/presentation/panel/tags_panel_context.dart';
import 'package:doable/src/tag/presentation/panel/tags_panel_view_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/tag_catalog_test_repository.dart';
import '../../../support/tag_positions.dart';

const _screen = Size(390, 844);
const _statusBar = 47.0;

void main() {
  for (final (locale, texts) in [
    (
      const Locale('ru'),
      (
        title: 'Теги',
        hint: 'Выберите сколько нужно',
        search: 'Найти или создать тег',
        done: 'Готово',
        expand: 'Раскрыть панель тегов',
        collapse: 'Свернуть панель тегов',
      ),
    ),
    (
      const Locale('en'),
      (
        title: 'Tags',
        hint: 'Choose as many as you need',
        search: 'Find or create a tag',
        done: 'Done',
        expand: 'Expand tags panel',
        collapse: 'Collapse tags panel',
      ),
    ),
  ]) {
    testWidgets('${locale.languageCode}: Панель со страницы намерения '
        'показывает весь каталог в ручном порядке и отмечает назначенные '
        'теги', (tester) async {
      final semantics = tester.ensureSemantics();
      final h = await _pumpApp(tester, locale: locale);
      await h.open();

      expect(find.text(texts.title), findsOne);
      expect(find.text(texts.hint), findsOne);
      expect(find.text(texts.search), findsOne);
      expect(find.text(texts.done), findsOne);
      expect(h.repository.readModes.single, isA<TagCatalogSelectionMode>());

      // «Работа» не используется, «Выходные» назначен только архивированному
      // намерению: в выборе оба лишь не назначены этому намерению.
      h.repository.complete(
        [_tag(1, 'Дом'), _tag(2, 'Работа'), _tag(3, 'Выходные')],
        assignedIds: {_id(1)},
      );
      await tester.pump();

      expect(_rowNames(tester), ['Дом', 'Работа', 'Выходные']);
      expect(_marks(tester), [
        TagRowMark.checked,
        TagRowMark.none,
        TagRowMark.none,
      ]);
      // Отметка объявляется один раз: в названии строки только название
      // тега, а отметку передаёт состояние отметки.
      expect(
        tester.getSemantics(_row(1)),
        isSemantics(
          label: 'Дом',
          hasCheckedState: true,
          isChecked: true,
          isEnabled: true,
          hasTapAction: true,
        ),
      );
      expect(
        tester.getSemantics(_row(2)),
        isSemantics(
          label: 'Работа',
          hasCheckedState: true,
          isChecked: false,
          isEnabled: true,
          hasTapAction: true,
        ),
      );

      final handle = find.bySemanticsLabel(texts.expand);
      expect(
        tester.getSemantics(handle),
        isSemantics(isButton: true, hasExpandedState: true),
      );
      await tester.tap(handle);
      await tester.pumpAndSettle();
      expect(
        tester.getSemantics(find.bySemanticsLabel(texts.collapse)),
        isSemantics(isButton: true, hasExpandedState: true, isExpanded: true),
      );
      semantics.dispose();
    });
  }

  testWidgets('Большой каталог получен целиком', (tester) async {
    final h = await _pumpApp(tester);
    await h.open();
    final tags = [for (var i = 1; i <= 40; i++) _tag(i, 'Тег $i')];
    h.repository.complete(tags, assignedIds: {});
    await tester.pump();

    final names = [for (final tag in tags) tag.name.value];
    // Каждый кадр строит непрерывный отрезок каталога без повторов, а
    // прокрутка сдвигает его без пропусков до последнего тега.
    var reached = 0;
    void collect() {
      final rows = _rowNames(tester);
      final start = names.indexOf(rows.first);
      expect(start, inInclusiveRange(0, reached));
      expect(rows, names.sublist(start, start + rows.length));
      reached = start + rows.length;
    }

    collect();
    expect(reached, lessThan(names.length), reason: 'каталог длиннее листа');
    for (var drags = 0; reached < names.length && drags < 10; drags++) {
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -200));
      await tester.pump();
      collect();
    }
    expect(reached, names.length);

    expect(h.repository.reads, hasLength(1));
  });

  testWidgets('Пустой каталог отличается от отсутствия совпадений', (
    tester,
  ) async {
    final h = await _pumpApp(tester);
    await h.open();
    expect(_listState, findsOne);
    expect(find.text('Загружаем теги…'), findsOne);

    h.repository.complete([], assignedIds: {});
    await tester.pump();

    expect(find.byType(EmptyState), findsOne);
    expect(find.text('Тегов пока нет'), findsOne);
    expect(
      find.text('Введите название в поиске, чтобы создать первый'),
      findsOne,
    );
    expect(_listState, findsNothing);
    expect(find.byType(Notice), findsNothing);
  });

  testWidgets('Цветной и бесцветный теги в каталоге', (tester) async {
    final h = await _pumpApp(tester);
    await h.open();
    h.repository.complete([
      _tag(1, 'Дом', color: TagColor.blue),
      _tag(2, 'Работа'),
    ], assignedIds: {});
    await tester.pump();

    final dots = tester.widgetList<TagDot>(find.byType(TagDot)).toList();
    expect(dots.map((dot) => dot.color), [DoableTagColor.blue, null]);
  });

  testWidgets('Поиск при назначении намерению', (tester) async {
    final h = await _pumpApp(tester);
    await h.open();
    h.repository.complete(
      [_tag(1, 'Работа'), _tag(2, 'Дом'), _tag(3, 'Для дома')],
      assignedIds: {_id(2)},
    );
    await tester.pump();

    await tester.enterText(_search, 'дом');
    await tester.pump();

    expect(_rowNames(tester), ['Дом', 'Для дома']);
    expect(_marks(tester), [TagRowMark.checked, TagRowMark.none]);

    await tester.tap(_row(3));
    await tester.pump();
    final assign = h.repository.commands.single as AssignTag;
    expect((assign.tagId, assign.intentionId), (_id(3), _intentionId));
  });

  testWidgets('Назначенный тег скрыт фильтром', (tester) async {
    final h = await _pumpApp(tester);
    await h.open();
    h.repository.complete(
      [_tag(1, 'Дом'), _tag(2, 'Работа')],
      assignedIds: {_id(1)},
    );
    await tester.pump();

    await tester.enterText(_search, 'работ');
    await tester.pump();
    expect(_rowNames(tester), ['Работа']);
    expect(_marks(tester), [TagRowMark.none]);

    await tester.tap(find.bySemanticsLabel('Очистить поиск тегов'));
    await tester.pump();
    expect(_rowNames(tester), ['Дом', 'Работа']);
    expect(_marks(tester), [TagRowMark.checked, TagRowMark.none]);
    expect(h.repository.commands, isEmpty);
  });

  testWidgets('некорректный ввод показывает ошибку под полем и сохраняет '
      'последний корректный фильтр', (tester) async {
    final h = await _pumpApp(tester);
    await h.open();
    h.repository.complete([_tag(1, 'Работа'), _tag(2, 'Дом')], assignedIds: {});
    await tester.pump();
    const error =
        'Недопустимые символы показаны как �. Ввод сохранён, но не '
        'применён; показаны результаты последнего корректного запроса.';

    await tester.enterText(_search, 'дом');
    await tester.enterText(_search, 'до\u0000м');
    await tester.pump();

    expect(find.text(error), findsOne);
    expect(_rowNames(tester), ['Дом']);
    expect(
      tester.getRect(find.text(error)).top,
      greaterThan(tester.getRect(_search).bottom),
    );
  });

  testWidgets('Новое открытие начинает поиск заново', (tester) async {
    final h = await _pumpApp(tester);
    await h.open();
    h.repository.complete([_tag(1, 'Работа'), _tag(2, 'Дом')], assignedIds: {});
    await tester.pump();
    await tester.enterText(_search, 'до\u0000м');
    await tester.pump();
    await tester.tap(find.text('Готово'));
    await tester.pumpAndSettle();

    await h.open();
    h.repository.complete([_tag(1, 'Работа'), _tag(2, 'Дом')], assignedIds: {});
    await tester.pump();

    expect(tester.widget<TextField>(_search).controller!.text, isEmpty);
    expect(find.textContaining('Недопустимые символы'), findsNothing);
    expect(_rowNames(tester), ['Работа', 'Дом']);
    expect(h.repository.reads, hasLength(2));
  });

  testWidgets('Фоновое обновление сохраняет список и прокрутку при отказе и '
      'повторе', (tester) async {
    final h = await _pumpApp(tester);
    await h.open();
    final tags = [for (var i = 1; i <= 40; i++) _tag(i, 'Тег $i')];
    h.repository.complete(tags, assignedIds: {_id(15)});
    await tester.pump();
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -500));
    await tester.pumpAndSettle();
    final offset = _scrollOffset(tester);
    final shown = _rowNames(tester);
    expect(shown.first, isNot('Тег 1'));
    expect(offset, greaterThan(0));

    h.changes.add(ConfirmedGraphReplacement(const TagCatalogTestRevision(2)));
    await tester.pump();
    expect(h.repository.reads, hasLength(2));
    _expectSameRows(tester, shown);
    expect(_scrollOffset(tester), offset);

    h.repository.fail(const TagCatalogUnavailableFailure());
    await tester.pumpAndSettle();
    expect(
      find.text('Не удалось обновить теги. Список может быть устаревшим.'),
      findsOne,
    );
    _expectSameRows(tester, shown);
    expect(_scrollOffset(tester), offset);
    expect(
      tester
          .widgetList<TagRow>(find.byType(TagRow))
          .map((row) => row.onPressed),
      everyElement(isNull),
      reason: 'неактуальные строки не принимают нажатия',
    );

    await tester.tap(find.text('Повторить'));
    await tester.pump();
    expect(h.repository.reads, hasLength(3));
    _expectSameRows(tester, shown);
    expect(_scrollOffset(tester), offset);

    h.repository.complete(tags, revision: 2, assignedIds: {_id(15)});
    await tester.pumpAndSettle();
    expect(find.byType(Notice), findsNothing);
    _expectSameRows(tester, shown);
    expect(_scrollOffset(tester), offset);
  });

  testWidgets('доказанно устранимый отказ первоначального чтения повторяется, '
      'а повреждение не предлагает повтор', (tester) async {
    final h = await _pumpApp(tester);
    await h.open();
    h.repository.fail(const TagCatalogUnavailableFailure());
    await tester.pump();
    expect(find.text('Не удалось загрузить теги.'), findsOne);

    await tester.tap(find.text('Повторить'));
    await tester.pump();
    expect(find.text('Загружаем теги…'), findsOne);
    h.repository.fail(const TagCatalogCorruptionFailure());
    await tester.pump();

    expect(
      find.text(
        'Сохранённые данные тегов повреждены и не могут быть показаны.',
      ),
      findsOne,
    );
    expect(find.text('Повторить'), findsNothing);
    expect(find.byType(TagRow), findsNothing);
  });

  testWidgets('панель сообщает об отсутствии намерения', (tester) async {
    final h = await _pumpApp(tester);
    await h.open();
    h.repository.fail(const TagCatalogIntentionNotFound());
    await tester.pump();

    expect(find.text('Этого намерения больше нет.'), findsOne);
    expect(find.text('Повторить'), findsNothing);
    expect(find.byType(TagRow), findsNothing);
  });

  testWidgets('Отказ записи оставляет прежнюю отметку и виден поверх панели '
      'над «Готово»', (tester) async {
    final h = await _pumpApp(tester);
    await h.open();
    h.repository.complete([_tag(1, 'Работа')], assignedIds: {});
    await tester.pump();

    await tester.tap(_row(1));
    await tester.pump();
    h.repository.command.complete(
      const TagCommandFailed(TagUnavailableFailure()),
    );
    await tester.pumpAndSettle();
    final message = find.descendant(
      of: find.byType(Sheet),
      matching: find.textContaining(
        'Не удалось изменить назначение тега. Повторите попытку.',
      ),
    );
    expect(message, findsOne);
    expect(
      tester
          .getRect(
            find.descendant(
              of: find.byType(Sheet),
              matching: find.byType(SnackBar),
            ),
          )
          .bottom,
      lessThanOrEqualTo(tester.getRect(find.text('Готово')).top),
    );
    expect(_marks(tester), [TagRowMark.none]);
  });

  for (final (name, close) in <(String, Future<void> Function(WidgetTester))>[
    ('«Готово»', (tester) => tester.tap(find.text('Готово'))),
    (
      'свайп вниз',
      (tester) =>
          tester.drag(find.text('Выберите сколько нужно'), const Offset(0, 80)),
    ),
    ('касание затемнения', (tester) => tester.tapAt(const Offset(195, 120))),
    ('«назад»', (tester) => tester.binding.handlePopRoute()),
  ]) {
    testWidgets('$name только закрывает панель без подтверждения', (
      tester,
    ) async {
      final h = await _pumpApp(tester);
      await h.open();
      h.repository.complete([_tag(1, 'Работа')], assignedIds: {});
      await tester.pump();

      await close(tester);
      await tester.pumpAndSettle();

      expect(find.byType(Sheet), findsNothing);
      expect(find.byType(Dialog), findsNothing);
      expect(h.isClosed, isTrue);
      expect(h.repository.commands, isEmpty);
    });
  }

  testWidgets('при открытой клавиатуре поле поиска и первая строка видны в '
      'обоих размерах панели', (tester) async {
    final h = await _pumpApp(tester);
    await h.open();
    h.repository.complete([
      for (var i = 1; i <= 20; i++) _tag(i, 'Тег $i'),
    ], assignedIds: {});
    await tester.pump();
    await tester.showKeyboard(_search);
    const keyboard = 336.0;
    tester.view.viewInsets = const FakeViewPadding(bottom: keyboard);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpAndSettle();

    void expectVisible() {
      const aboveKeyboard = 844.0 - keyboard;
      final sheet = tester.getRect(find.byType(Sheet));
      final search = tester.getRect(_search);
      final row = tester.getRect(_row(1));
      expect(search.top, greaterThan(sheet.top));
      expect(row.top, greaterThan(search.bottom));
      expect(row.bottom, lessThanOrEqualTo(aboveKeyboard));
      expect(
        row.bottom,
        lessThanOrEqualTo(tester.getRect(find.text('Готово')).top),
      );
    }

    expectVisible();
    await tester.tap(find.bySemanticsLabel('Раскрыть панель тегов'));
    await tester.pumpAndSettle();
    expectVisible();
    expect(tester.takeException(), isNull);
  });

  for (final (locale, texts) in [
    (const Locale('ru'), (create: 'Создать тег «спорт»', title: 'Новый тег')),
    (const Locale('en'), (create: 'Create tag “спорт”', title: 'New tag')),
  ]) {
    testWidgets('${locale.languageCode}: Совпадений нет, создание доступно', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      final h = await _pumpApp(tester, locale: locale);
      await h.open();
      h.repository.complete([_tag(1, 'Дом')], assignedIds: {});
      await tester.pump();

      await tester.enterText(_search, 'спорт');
      await tester.pump();

      expect(find.byType(TagRow), findsNothing);
      expect(
        tester.getSemantics(find.bySemanticsLabel(texts.create)),
        isSemantics(label: texts.create, isButton: true, hasTapAction: true),
      );
      expect(_searchText(tester), 'спорт');

      await tester.tap(find.text(texts.create));
      await tester.pumpAndSettle();

      expect(find.byType(Sheet), findsExactly(2));
      expect(find.text(texts.title), findsOne);
      expect(_tagSheetNameText(tester), 'спорт');
      semantics.dispose();
    });
  }

  for (final (name, close) in <(String, Future<void> Function(WidgetTester))>[
    (
      'свайп вниз',
      (tester) => tester.drag(find.text('Новый тег'), const Offset(0, 300)),
    ),
    ('касание затемнения', (tester) => tester.tapAt(const Offset(195, 120))),
    ('«назад»', (tester) => tester.binding.handlePopRoute()),
  ]) {
    testWidgets('$name в листе «Новый тег» возвращает ту же панель с прежними '
        'каталогом, отметками и поиском', (tester) async {
      final h = await _pumpApp(tester);
      await h.open();
      h.repository.complete(
        [_tag(1, 'Работа'), _tag(2, 'Рассада')],
        assignedIds: {_id(2)},
      );
      await tester.pump();
      await tester.enterText(_search, 'ра');
      await tester.pump();
      await tester.tap(find.text('Создать тег «ра»'));
      await tester.pumpAndSettle();
      await tester.enterText(_tagSheetName, 'Рамки');

      await close(tester);
      await tester.pumpAndSettle();

      expect(find.byType(Sheet), findsOne);
      expect(find.text('Новый тег'), findsNothing);
      expect(h.isClosed, isFalse);
      expect(_searchText(tester), 'ра');
      expect(find.text('Создать тег «ра»'), findsOne);
      expect(_rowNames(tester), ['Работа', 'Рассада']);
      expect(_marks(tester), [TagRowMark.none, TagRowMark.checked]);
      expect(h.repository.commands, isEmpty);
      expect(h.repository.reads, hasLength(1));
    });
  }

  testWidgets('подтверждённое создание из листа закрывает лист, очищает поле '
      'поиска и ставит новый тег первым', (tester) async {
    final h = await _pumpApp(tester);
    await h.open();
    h.repository.complete([_tag(5, 'Дом')], assignedIds: {});
    await tester.pump();
    await tester.enterText(_search, 'парк');
    await tester.pump();
    await tester.tap(find.text('Создать тег «парк»'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Создать тег'));
    await tester.pump();
    final create = h.repository.commands.single as CreateTag;
    expect((create.name.value, create.color), ('парк', null));
    final created = ConfirmedGraphResult<TagCommandSuccess>(
      revision: const TagCatalogTestRevision(2),
      value: TagCreated(
        TagCreatedChange(
          revision: const TagCatalogTestRevision(2),
          after: _tag(1, 'парк'),
        ),
      ),
    );
    h.repository.command.complete(TagCommandSucceeded(created));
    h.changes.add(created);
    await tester.pumpAndSettle();

    expect(find.byType(Sheet), findsOne);
    expect(find.text('Новый тег'), findsNothing);
    expect(_searchText(tester), isEmpty);
    expect(_rowNames(tester), ['парк', 'Дом']);
    final assign = h.repository.commands.last as AssignTag;
    expect((assign.tagId, assign.intentionId), (_id(1), _intentionId));
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('Закрытие панели до подтверждения создания: подтверждение во '
      'время закрывающей анимации панели не отмечает тег', (tester) async {
    final h = await _pumpApp(tester);
    await h.open();
    h.repository.complete([_tag(5, 'Дом')], assignedIds: {});
    await tester.pump();
    await tester.enterText(_search, 'парк');
    await tester.pump();
    await tester.tap(find.text('Создать тег «парк»'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Создать тег'));
    await tester.pump();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Новый тег'), findsNothing);

    await tester.tap(find.text('Готово'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    // Маршрут панели уже закрыт, но её содержимое и модель ещё живут.
    expect(h.isClosed, isTrue);
    expect(find.text('Создать тег «парк»'), findsOne);
    final created = ConfirmedGraphResult<TagCommandSuccess>(
      revision: const TagCatalogTestRevision(2),
      value: TagCreated(
        TagCreatedChange(
          revision: const TagCatalogTestRevision(2),
          after: _tag(1, 'парк'),
        ),
      ),
    );
    h.repository.command.complete(TagCommandSucceeded(created));
    await tester.pump();

    expect(h.repository.commands.single, isA<CreateTag>());
    expect(find.text('Создать тег «парк»'), findsOne);
    expect(_searchText(tester), 'парк');
    await tester.pumpAndSettle();
    expect(find.byType(Sheet), findsNothing);
    expect(h.repository.commands.single, isA<CreateTag>());
  });
}

final _intentionId = (IntentionId.decode(
  '00000000-0000-4000-9000-000000000001',
) as IntentionIdDecodingSuccess).id;

final _search = find.byType(TextField).first;

/// Поле названия листа «Новый тег», открытого поверх панели.
final _tagSheetName = find.descendant(
  of: find.byType(Sheet).last,
  matching: find.byType(TextField),
);

String _searchText(WidgetTester tester) =>
    tester.widget<TextField>(_search).controller!.text;

String _tagSheetNameText(WidgetTester tester) =>
    tester.widget<TextField>(_tagSheetName).controller!.text;

final _listState = find.byWidgetPredicate((widget) => widget is ListState);

Finder _row(int number) =>
    find.byKey(ValueKey('tags-panel-row-${_id(number).toCanonicalString()}'));

List<String> _rowNames(WidgetTester tester) => [
  for (final row in tester.widgetList<TagRow>(find.byType(TagRow))) row.name,
];

List<TagRowMark> _marks(WidgetTester tester) => [
  for (final row in tester.widgetList<TagRow>(find.byType(TagRow))) row.mark,
];

/// Сообщение над списком уменьшает его видимую часть, поэтому строятся те же
/// строки с той же первой, но, возможно, не все прежние.
void _expectSameRows(WidgetTester tester, List<String> shown) {
  final rows = _rowNames(tester);
  expect(rows.length, greaterThan(1));
  expect(rows, shown.take(rows.length));
}

double _scrollOffset(WidgetTester tester) => tester
    .state<ScrollableState>(
      find.descendant(
        of: find.byType(CustomScrollView),
        matching: find.byType(Scrollable),
      ),
    )
    .position
    .pixels;

final class _Harness {
  _Harness(this._tester, this.repository, this.changes);

  final WidgetTester _tester;
  final TagCatalogTestRepository repository;
  final StreamController<ConfirmedGraphChangePackage> changes;

  /// Последнее открытие панели завершилось закрытием.
  var isClosed = false;

  /// Открывает панель с тестовой страницы.
  Future<void> open() async {
    isClosed = false;
    await _tester.tap(find.text('Открыть'));
    // Кольцо загрузки вращается без остановки, поэтому анимация открытия
    // завершается явным сдвигом времени.
    await _tester.pump();
    await _tester.pump(const Duration(seconds: 1));
  }
}

Future<_Harness> _pumpApp(
  WidgetTester tester, {
  Locale locale = const Locale('ru'),
}) async {
  tester.view
    ..devicePixelRatio = 1
    ..physicalSize = _screen
    ..padding = const FakeViewPadding(top: _statusBar)
    ..viewPadding = const FakeViewPadding(top: _statusBar);
  addTearDown(tester.view.reset);
  // Общая поверхность показывает сообщения только в активном приложении.
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  final repository = TagCatalogTestRepository();
  final changes = StreamController<ConfirmedGraphChangePackage>.broadcast();
  addTearDown(changes.close);
  final container = ProviderContainer(
    overrides: [
      personalGraphRepositoryProvider.overrideWithValue(repository),
      tagsPanelChangesProvider.overrideWithValue(changes.stream),
    ],
    retry: (retryCount, error) => null,
  );
  addTearDown(container.dispose);
  final harness = _Harness(tester, repository, changes);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: doableTheme(Brightness.light),
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) =>
            GraphOperationPresenter(child: child ?? const SizedBox.shrink()),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => showTagsPanel(
                  context,
                  TagsPanelAssignmentContext(_intentionId),
                ).whenComplete(() => harness.isClosed = true),
                child: const Text('Открыть'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  return harness;
}

TagId _id(int number) => (TagId.decode(
  '00000000-0000-4000-8000-${number.toString().padLeft(12, '0')}',
) as TagIdDecodingSuccess).id;

/// Номер задаёт и идентичность, и место тега в ручном порядке.
Tag _tag(int number, String name, {TagColor? color}) => Tag(
  id: _id(number),
  name: TagName.fromInput(name),
  color: color,
  position: tagPositionAt(number),
);
