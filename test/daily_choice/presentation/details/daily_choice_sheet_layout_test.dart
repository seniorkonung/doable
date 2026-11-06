import 'dart:async';
import 'dart:math' as math;

import 'package:doable/src/daily_choice/application/daily_choice_details.dart';
import 'package:doable/src/daily_choice/domain/choice_path_step_id.dart';
import 'package:doable/src/daily_choice/domain/daily_choice.dart';
import 'package:doable/src/daily_choice/domain/daily_choice_description.dart';
import 'package:doable/src/daily_choice/domain/daily_choice_id.dart';
import 'package:doable/src/daily_choice/domain/daily_choice_priority.dart';
import 'package:doable/src/daily_choice/domain/daily_choice_schedule.dart';
import 'package:doable/src/daily_choice/presentation/details/daily_choice_sheet.dart';
import 'package:doable/src/design_system/components/choice_head.dart';
import 'package:doable/src/design_system/components/choice_path.dart' as ui;
import 'package:doable/src/design_system/components/detail_row.dart';
import 'package:doable/src/design_system/components/half_pinned_sliver.dart';
import 'package:doable/src/design_system/components/sheet.dart';
import 'package:doable/src/design_system/components/tabs.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/application/personal_graph_repository.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation_id.dart';
import 'package:doable/src/shared/domain/calendar_date.dart';
import 'package:doable/src/shared/presentation/local_day/local_date_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/controlled_local_date.dart';
import '../../../support/ordinary_page_test_app.dart';
import '../../../support/tag_read_contract_test_fallback.dart';

void main() {
  for (final (name, expands) in const [
    ('компактном', false),
    ('полном', true),
  ]) {
    testWidgets('при предельных названиях, крупном шрифте и на низком экране '
        'весь текст обеих вкладок достижим без обрезки в $name размере', (
      tester,
    ) async {
      await _useExtremeScreen(tester);
      final semantics = tester.ensureSemantics();
      await _openSheet(tester, _extremeDetails());
      if (expands) {
        await tester.tap(_expand);
        await tester.pumpAndSettle();
      }

      await _expectWholeTextReachable(tester, [
        _maxTitle('основа'),
        _maxTitle('действие'),
        'Архив',
        'Обзор',
        'Путь',
        '2',
        _maxDescription,
        'Дата',
        '8 окт. 2025',
        'Время',
        'Весь день',
        'Приоритет',
        'P1',
        'P2',
        'P3',
        'P4',
      ]);
      await _expectTabsReachable(tester);

      // Вкладки стоят под высокой шапкой, а верх списка принадлежит ручке.
      await Scrollable.ensureVisible(
        tester.element(find.text('Путь', skipOffstage: false)),
        alignment: 0.5,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Путь'));
      await tester.pumpAndSettle();
      await _expectWholeTextReachable(tester, [
        _maxTitle('основа'),
        _maxTitle('середина'),
        _maxTitle('действие'),
        'Нужно',
        'Можно',
        'В пути есть архивированные намерения или связи.',
      ]);
      semantics.dispose();
    });
  }

  testWidgets('палец вверх по высокой шапке раскрывает панель, затем шапка и '
      'вкладки уходят вместе с телом, а ручка стоит на месте', (tester) async {
    await _useExtremeScreen(tester);
    final semantics = tester.ensureSemantics();
    await _openSheet(tester, _extremeDetails());
    final compact = tester.getRect(_sheet);
    final handleOffset = tester.getTopLeft(_expand).dy - compact.top;
    expect(_headerHeight(tester), greaterThan(_list(tester).height / 2));

    final gesture = await tester.startGesture(
      Offset(compact.center.dx, tester.getTopLeft(_head).dy + 60),
    );
    for (var move = 0; move < 40; move++) {
      await gesture.moveBy(const Offset(0, -20));
      await tester.pump();
      final scrolled = _body(tester).pixels;
      if (scrolled > 0) expect(tester.getTopLeft(_sheet).dy, _statusBar);
      expect(
        tester.getTopLeft(_head).dy,
        closeTo(_list(tester).top - scrolled, 0.01),
      );
      expect(tester.getTopLeft(_tabs).dy, tester.getBottomLeft(_head).dy);
    }
    expect(_body(tester).pixels, greaterThan(0));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(tester.getTopLeft(_sheet).dy, _statusBar);
    expect(_headerHeight(tester), greaterThan(_list(tester).height / 2));
    expect(tester.getTopLeft(_collapse).dy - _statusBar, handleOffset);
    expect(_collapse.hitTestable(), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('шапка не выше порога остаётся на месте при прокрутке тела', (
    tester,
  ) async {
    _useScreen(tester, const Size(390, 844));
    final semantics = tester.ensureSemantics();
    await _openSheet(tester, _details(description: _longDescription));
    await tester.tap(_expand);
    await tester.pumpAndSettle();
    final head = tester.getTopLeft(_head);
    expect(_headerHeight(tester), lessThan(_list(tester).height / 2));

    await tester.dragFrom(_list(tester).center, const Offset(0, -300));
    await tester.pumpAndSettle();

    expect(_body(tester).pixels, greaterThan(0));
    expect(tester.getTopLeft(_head), head);
    expect(tester.getTopLeft(_tabs).dy, tester.getBottomLeft(_head).dy);
    semantics.dispose();
  });

  testWidgets('раскрытие панели через порог закрепляет шапку и не меняет '
      'выбранную вкладку', (tester) async {
    _useScreen(tester, const Size(390, 1000));
    final semantics = tester.ensureSemantics();
    await _openSheet(
      tester,
      _details(
        actionTitle: _maxTitle('действие'),
        middleTitle: _maxTitle('середина'),
      ),
    );
    await tester.tap(find.text('Путь'));
    await tester.pumpAndSettle();
    expect(_headerHeight(tester), greaterThan(_list(tester).height / 2));
    final compactTop = tester.getTopLeft(_head).dy;
    _body(tester).jumpTo(40);
    await tester.pump();
    expect(tester.getTopLeft(_head).dy, compactTop - 40);
    _body(tester).jumpTo(0);
    await tester.pump();

    await tester.tap(_expand);
    await tester.pumpAndSettle();

    expect(_headerHeight(tester), lessThan(_list(tester).height / 2));
    final fullTop = tester.getTopLeft(_head).dy;
    _body(tester).jumpTo(40);
    await tester.pump();
    expect(tester.getTopLeft(_head).dy, fullTop);
    expect(find.byType(ui.ChoicePath), findsOneWidget);
    expect(find.byType(DetailRow), findsNothing);
    semantics.dispose();
  });

  testWidgets('поле описания с кареткой видно над клавиатурой под высокой '
      'шапкой, а шапка уходит вместе с полем и достижима целиком', (
    tester,
  ) async {
    await _useExtremeScreen(tester);
    final semantics = tester.ensureSemantics();
    await _openSheet(
      tester,
      _details(
        sourceTitle: _maxTitle('основа'),
        middleTitle: _maxTitle('середина'),
        actionTitle: _maxTitle('действие'),
        archived: true,
      ),
    );
    await _openDescription(tester, 'Пояснение');
    _openKeyboard(tester);
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(EditableText), _enteredDescription);
    await tester.pumpAndSettle();

    expect(_headerHeight(tester), greaterThan(_list(tester).height / 2));
    _expectCaretVisible(tester);
    _expectFieldKept(tester);
    for (final pixels in [0.0, 120.0]) {
      _body(tester).jumpTo(pixels);
      await tester.pump();
      expect(
        tester.getTopLeft(_head).dy,
        closeTo(_list(tester).top - pixels, 0.01),
      );
    }
    await _expectWholeTextReachable(tester, [
      _maxTitle('основа'),
      _maxTitle('действие'),
      'Архив',
    ]);
    _expectFieldKept(tester);
    semantics.dispose();
  });

  testWidgets('открытие и закрытие клавиатуры переводят шапку через порог '
      'закрепления в обе стороны, а текст и фокус поля остаются', (
    tester,
  ) async {
    _useScreen(tester, const Size(390, 844));
    final semantics = tester.ensureSemantics();
    await _openSheet(
      tester,
      _details(
        sourceTitle: _maxTitle('основа'),
        actionTitle: _maxTitle('действие'),
      ),
    );
    await _openDescription(tester, 'Пояснение');
    await tester.enterText(find.byType(EditableText), _enteredDescription);
    await tester.pumpAndSettle();
    expect(_headerHeight(tester), lessThan(_list(tester).height / 2));
    expect(_pinnedExtent(tester), _headerHeight(tester));

    _openKeyboard(tester);
    await tester.pumpAndSettle();

    expect(_headerHeight(tester), greaterThan(_list(tester).height / 2));
    expect(_pinnedExtent(tester), 0);
    _expectCaretVisible(tester);
    _expectFieldKept(tester);

    tester.view.resetViewInsets();
    await tester.pumpAndSettle();

    expect(_headerHeight(tester), lessThan(_list(tester).height / 2));
    expect(_pinnedExtent(tester), _headerHeight(tester));
    _expectCaretVisible(tester);
    _expectFieldKept(tester);
    semantics.dispose();
  });

  testWidgets('шапка не выше порога закреплена над полем и не закрывает '
      'каретку в начале прокрученного текста', (tester) async {
    _useScreen(tester, const Size(360, 720));
    final semantics = tester.ensureSemantics();
    await _openSheet(tester, _details());
    await tester.tap(find.text('Пояснение'));
    await tester.pumpAndSettle();
    _openKeyboard(tester);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(EditableText), _manyLines);
    await tester.pumpAndSettle();
    final head = tester.getTopLeft(_head);
    expect(_headerHeight(tester), lessThan(_list(tester).height / 2));
    expect(_body(tester).pixels, greaterThan(0));

    tester.testTextInput.updateEditingValue(
      TextEditingValue(
        text: _manyLines,
        selection: TextSelection.collapsed(offset: 0),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.getTopLeft(_head), head);
    _expectCaretVisible(tester);
    semantics.dispose();
  });
}

const _keyboard = 300.0;

const _enteredDescription = 'Новое описание';

final _manyLines = List.generate(20, (line) => 'строка $line').join('\n');

const _statusBar = 24.0;

/// Название наибольшей допустимой длины: 255 графем.
String _maxTitle(String word) =>
    '${'$word ${'слово ' * 43}'.substring(0, 254)}я';

final _maxDescription = List.filled(120, 'строка описания').join(' ');

final _longDescription = List.filled(300, 'слово').join(' ');

final _sheet = find.byType(Sheet);

// Прокрученная шапка уходит за край списка, поэтому ищется и за ним.
final _head = find.byType(ChoiceHead, skipOffstage: false);
final _tabs = find.byWidgetPredicate(
  (widget) => widget is Tabs,
  skipOffstage: false,
);
final _expand = find.bySemanticsLabel('Раскрыть панель дневного выбора');
final _collapse = find.bySemanticsLabel('Свернуть панель дневного выбора');

final _listFinder = find.descendant(
  of: _sheet,
  matching: find.byType(CustomScrollView),
);

Rect _list(WidgetTester tester) => tester.getRect(_listFinder);

ScrollPosition _body(WidgetTester tester) => tester
    .state<ScrollableState>(
      find.descendant(of: _sheet, matching: find.byType(Scrollable)).first,
    )
    .position;

/// Шапка вместе с вкладками, а при изменении описания вкладок нет.
double _headerHeight(WidgetTester tester) =>
    _headerBottom(tester) - tester.getTopLeft(_head).dy;

double _headerBottom(WidgetTester tester) =>
    tester.getBottomLeft(_tabs.evaluate().isEmpty ? _head : _tabs).dy;

/// Высота, которую закреплённая шапка закрывает над телом; 0, пока шапка
/// прокручивается вместе с ним.
double _pinnedExtent(WidgetTester tester) => tester
    .renderObject<RenderHalfPinnedSliver>(find.byType(HalfPinnedSliver))
    .geometry!
    .maxScrollObstructionExtent;

/// Под высокой шапкой описание сначала нужно прокрутить в видимую часть.
Future<void> _openDescription(WidgetTester tester, String description) async {
  final text = find.text(description, skipOffstage: false);
  await tester.ensureVisible(text);
  await tester.pumpAndSettle();
  await tester.tap(text);
  await tester.pumpAndSettle();
}

void _openKeyboard(WidgetTester tester) =>
    tester.view.viewInsets = const FakeViewPadding(bottom: _keyboard);

/// Каретка видна в списке над клавиатурой и не стоит под шапкой.
void _expectCaretVisible(WidgetTester tester) {
  final editable = tester
      .state<EditableTextState>(find.byType(EditableText))
      .renderEditable;
  final caret = MatrixUtils.transformRect(
    editable.getTransformTo(null),
    editable.getLocalRectForCaret(editable.selection!.extent),
  );
  final list = _list(tester);
  final keyboardTop =
      tester.view.physicalSize.height / tester.view.devicePixelRatio -
      tester.view.viewInsets.bottom / tester.view.devicePixelRatio;
  expect(list.bottom, lessThanOrEqualTo(keyboardTop));
  expect(
    caret.top,
    greaterThanOrEqualTo(math.max(list.top, _headerBottom(tester))),
  );
  expect(caret.bottom, lessThanOrEqualTo(list.bottom));
}

void _expectFieldKept(WidgetTester tester) {
  final field = tester.widget<EditableText>(
    find.byType(EditableText, skipOffstage: false),
  );
  expect(field.controller.text, _enteredDescription);
  expect(field.focusNode.hasFocus, isTrue);
}

/// Экран ниже границы поддержки 360×720, но выше компактного предела, поэтому
/// у панели остаются оба размера. Шрифт — наибольший системный на Android.
Future<void> _useExtremeScreen(WidgetTester tester) async {
  _useScreen(tester, const Size(360, 640));
  tester.view
    ..padding = const FakeViewPadding(top: _statusBar, bottom: 48)
    ..viewPadding = const FakeViewPadding(top: _statusBar, bottom: 48);
  tester.platformDispatcher.textScaleFactorTestValue = 2;
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  // Переносы и ширина пилюль зависят от настоящего шрифта.
  await (FontLoader('Inter')..addFont(
        rootBundle.load('lib/src/design_system/fonts/InterVariable.ttf'),
      ))
      .load();
}

void _useScreen(WidgetTester tester, Size size) {
  tester.view
    ..physicalSize = size
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

List<RenderParagraph> _paragraphs(WidgetTester tester, Finder of) => [
  for (final element
      in find
          .descendant(
            of: find.descendant(
              of: of,
              matching: find.byType(Text, skipOffstage: false),
              skipOffstage: false,
            ),
            matching: find.byType(RichText, skipOffstage: false),
            skipOffstage: false,
          )
          .evaluate())
    element.renderObject! as RenderParagraph,
];

Rect _rectOf(RenderParagraph paragraph) => MatrixUtils.transformRect(
  paragraph.getTransformTo(null),
  Offset.zero & paragraph.size,
);

/// Прокручивает тело шагами, не больше видимой части, и проверяет, что каждый
/// текст открылся по всей высоте. Текст в шапке виден в области списка, а
/// текст тела — только под шапкой с вкладками: закреплённая шапка его закрывает.
Future<void> _expectWholeTextReachable(
  WidgetTester tester,
  List<String> texts,
) async {
  final body = _body(tester);
  body.jumpTo(0);
  await tester.pump();
  final paragraphs = _paragraphs(tester, _listFinder);
  expect(
    paragraphs.map((paragraph) => paragraph.text.toPlainText()),
    containsAll(texts),
  );
  final inHeader = {
    ..._paragraphs(tester, _head),
    ..._paragraphs(tester, _tabs),
  };
  final inTabs = _paragraphs(tester, _tabs).toSet();
  final reached = {for (final paragraph in paragraphs) paragraph: 0.0};
  final step = _list(tester).height / 2;
  for (var pixels = 0.0; ; pixels += step) {
    body.jumpTo(math.min(pixels, body.maxScrollExtent));
    await tester.pump();
    final list = _list(tester);
    final headerBottom = _headerBottom(tester);
    for (final paragraph in paragraphs) {
      final rect = _rectOf(paragraph);
      if (!inTabs.contains(paragraph)) {
        final text = paragraph.text.toPlainText();
        expect(rect.left, greaterThanOrEqualTo(list.left), reason: text);
        expect(rect.right, lessThanOrEqualTo(list.right), reason: text);
      }
      final top = math.max(
        rect.top,
        inHeader.contains(paragraph)
            ? list.top
            : math.max(list.top, headerBottom),
      );
      final bottom = math.min(rect.bottom, list.bottom);
      if (bottom > top && top - rect.top <= reached[paragraph]!) {
        reached[paragraph] = math.max(reached[paragraph]!, bottom - rect.top);
      }
    }
    if (body.pixels >= body.maxScrollExtent) break;
  }
  for (final paragraph in paragraphs) {
    final text = paragraph.text.toPlainText();
    final width = paragraph.size.width;
    expect(
      reached[paragraph],
      closeTo(paragraph.size.height, 0.01),
      reason: text,
    );
    expect(paragraph.didExceedMaxLines, isFalse, reason: text);
    expect(
      paragraph.size.height,
      greaterThanOrEqualTo(paragraph.getMaxIntrinsicHeight(width)),
      reason: text,
    );
    expect(
      width,
      greaterThanOrEqualTo(paragraph.getMinIntrinsicWidth(double.infinity)),
      reason: text,
    );
  }
  body.jumpTo(0);
  await tester.pump();
}

/// Полоса вкладок прокручивается сама, поэтому каждая подпись видна целиком
/// хотя бы у одного края полосы.
Future<void> _expectTabsReachable(WidgetTester tester) async {
  final strip = tester
      .state<ScrollableState>(
        find.descendant(of: _tabs, matching: find.byType(Scrollable)),
      )
      .position;
  final bar = tester.getRect(_tabs);
  final paragraphs = _paragraphs(tester, _tabs);
  final seen = <RenderParagraph>{};
  for (final pixels in [strip.minScrollExtent, strip.maxScrollExtent]) {
    strip.jumpTo(pixels);
    await tester.pump();
    for (final paragraph in paragraphs) {
      final rect = _rectOf(paragraph);
      if (rect.intersect(bar) == rect) seen.add(paragraph);
    }
  }
  expect(seen, paragraphs.toSet());
}

/// Открывает панель над страницей и выдаёт ей [details].
Future<void> _openSheet(WidgetTester tester, DailyChoiceDetails details) async {
  final repository = _Repository(details);
  addTearDown(repository.dispose);
  final localDate = ControlledLocalDate(CalendarDate.fromParts(2026, 10, 8));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        personalGraphRepositoryProvider.overrideWith((ref) => repository),
        localDateSourceProvider.overrideWithValue(localDate.read),
      ],
      child: OrdinaryPageTestApp(
        locale: const Locale('ru'),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () =>
                  unawaited(showDailyChoiceSheet(context, _choice)),
              child: const Text('Открыть'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.tap(find.text('Открыть'));
  await tester.pump();
  repository.emit();
  await tester.pumpAndSettle();
}

/// Выбор, в котором каждый текст панели занимает наибольшее место: предельные
/// названия, архивные отметки и дата с годом.
DailyChoiceDetails _extremeDetails() => _details(
  sourceTitle: _maxTitle('основа'),
  middleTitle: _maxTitle('середина'),
  actionTitle: _maxTitle('действие'),
  description: _maxDescription,
  date: CalendarDate.fromParts(2025, 10, 8),
  archived: true,
);

String _uuid(int n) =>
    '018f0b5d-6b2e-7c80-8000-${n.toRadixString(16).padLeft(12, '0')}';
final _choice =
    (DailyChoiceId.decode(_uuid(1)) as DailyChoiceIdDecodingSuccess).id;
IntentionId _intentionId(int n) =>
    (IntentionId.decode(_uuid(n)) as IntentionIdDecodingSuccess).id;
LongTermRelationId _relationId(int n) => (LongTermRelationId.decode(
  _uuid(n),
) as LongTermRelationIdDecodingSuccess).id;
ChoicePathStepId _stepId(int n) =>
    (ChoicePathStepId.decode(_uuid(n)) as ChoicePathStepIdDecodingSuccess).id;

Intention _intention(int n, String title, {required bool archived}) =>
    Intention(
      id: _intentionId(n),
      title: title,
      description: null,
      readiness: IntentionReadiness.ready,
      archiveState: archived
          ? IntentionArchiveState.archived
          : IntentionArchiveState.active,
      createdAt: IntentionTimestamp(DateTime.utc(2026)),
      updatedAt: IntentionTimestamp(DateTime.utc(2026)),
    );

DailyChoiceDetails _details({
  String sourceTitle = 'Основа',
  String middleTitle = 'Середина',
  String actionTitle = 'Действие',
  String description = 'Пояснение',
  CalendarDate? date,
  bool archived = false,
}) {
  final source = _intention(1, sourceTitle, archived: archived);
  final middle = _intention(2, middleTitle, archived: archived);
  final selected = _intention(3, actionTitle, archived: archived);
  final choice = DailyChoice(
    id: _choice,
    sourceIntentionId: source.id,
    selectedIntentionId: selected.id,
    date: date ?? CalendarDate.fromParts(2026, 10, 8),
    schedule: const DailyChoiceAllDay(),
    priority: DailyChoicePriority.p2,
    description: DailyChoiceDescription.fromInput(description),
    isCompleted: false,
  );
  DailyChoicePathStepDetails step(int n, Intention from, Intention to) =>
      DailyChoicePathStepDetails(
        step: ChoicePathStep(
          id: _stepId(n),
          dailyChoiceId: choice.id,
          relationId: _relationId(n),
          previousStepId: n == 1 ? null : _stepId(n - 1),
        ),
        relation: LongTermRelation(
          id: _relationId(n),
          sourceIntentionId: from.id,
          relatedIntentionId: to.id,
          type: n == 1 ? LongTermRelationType.need : LongTermRelationType.can,
          priority: RelationPriority.p2,
          scope: archived ? RelationScope.archived : RelationScope.active,
          creationSequence: RelationCreationSequence(n),
          createdAt: RelationTimestamp(DateTime.utc(2026)),
          updatedAt: RelationTimestamp(DateTime.utc(2026)),
        ),
        description: null,
        source: from,
        related: to,
      );
  return DailyChoiceDetails(
    choice: choice,
    source: source,
    selected: selected,
    path: [step(1, source, middle), step(2, middle, selected)],
  );
}

final class _Revision implements GraphRevision {
  const _Revision();

  @override
  GraphRevisionOrder compareTo(GraphRevision other) => GraphRevisionOrder.same;
}

final class _Repository
    with TagReadContractTestFallback
    implements PersonalGraphRepository {
  _Repository(this._details);

  final DailyChoiceDetails _details;
  final _controller = StreamController<DailyChoiceReadResult>.broadcast(
    sync: true,
  );

  @override
  Stream<DailyChoiceReadResult> watchDailyChoice(DailyChoiceId id) =>
      _controller.stream;

  void emit() => _controller.add(
    DailyChoiceReadSuccess(
      GraphSnapshot(value: _details, revision: const _Revision()),
    ),
  );

  Future<void> dispose() => _controller.close();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
