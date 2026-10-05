import 'dart:math' as math;

import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/src/app/routing/app_router.dart';
import 'package:doable/src/app/routing/app_router.gr.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:doable/src/graph/presentation/graph_operation_presenter.dart';
import 'package:doable/src/intention/application/intention_catalog.dart'
    hide IntentionCatalogPage;
import 'package:doable/src/intention/application/intention_result.dart';
import 'package:doable/src/intention/presentation/catalog/intention_catalog_page.dart';
import 'package:doable/src/intention/presentation/editor/intention_creation_sheet.dart';
import 'package:doable/src/intention/presentation/editor/intention_editor_page.dart';
import 'package:doable/src/intention/presentation/editor/intention_editor_state.dart';
import 'package:doable/src/intention/presentation/editor/intention_editor_view_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/app_root_pages.dart';
import '../catalog/catalog_test_support.dart';

void main() {
  setUp(() {
    WidgetsBinding.instance.handleAppLifecycleStateChanged(
      AppLifecycleState.resumed,
    );
  });

  group('разворачивание и сворачивание панели', () {
    testWidgets(
      'кнопка разворачивает ту же панель на всю доступную высоту и сворачивает её до прежней компактной, сохраняя сессию, ввод, фокус и маршрут',
      (tester) async {
        _usePhone(tester, _portrait);
        final sessions = _EditorSessions();
        final repository = ControlledCatalogRepository();
        final router = await _openEditor(tester, repository, sessions);
        await tester.enterText(find.byKey(_title), 'Намерение');
        await tester.enterText(find.byKey(_description), 'Описание');
        await tester.pumpAndSettle();
        final session = sessions.single;
        final stack = router.stack.length;
        final titleController = _controller(tester, _title);
        final descriptionController = _controller(tester, _description);
        final compact = _sheetRect(tester);
        _expectCompact(tester, compact, _portrait);

        await tester.tap(find.byKey(_resize));
        await tester.pumpAndSettle();

        final expanded = _sheetRect(tester);
        expect(expanded, _expandedArea(_portrait));
        expect(sessions.state(tester).sheetMode, _expandedMode);
        expect(find.byKey(_closeConfirmation), findsNothing);
        expect(find.byKey(_submit).hitTestable(), findsOneWidget);
        _expectSameSession(tester, sessions, session);
        expect(router.stack.length, stack);
        expect(router.current.name, IntentionEditorRoute.name);
        expect(_controller(tester, _title), same(titleController));
        expect(_controller(tester, _description), same(descriptionController));
        expect(titleController.text, 'Намерение');
        expect(descriptionController.text, 'Описание');
        expect(_hasFocus(tester, _description), isTrue);
        expect(sessions.state(tester).draft.title, 'Намерение');

        await tester.tap(find.byKey(_resize));
        await tester.pumpAndSettle();

        expect(_sheetRect(tester), compact);
        expect(sessions.state(tester).sheetMode, _compactMode);
        expect(find.byKey(_closeConfirmation), findsNothing);
        _expectSameSession(tester, sessions, session);
        expect(router.stack.length, stack);
        expect(_controller(tester, _description), same(descriptionController));
        expect(_hasFocus(tester, _description), isTrue);
        expect(repository.commands, isEmpty);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'свайп вверх по ручке разворачивает панель, свайп вниз из развёрнутой только сворачивает её, а следующий свайп вниз запрашивает закрытие изменённого черновика',
      (tester) async {
        _usePhone(tester, _portrait);
        final sessions = _EditorSessions();
        final repository = ControlledCatalogRepository();
        final router = await _openEditor(tester, repository, sessions);
        await tester.enterText(find.byKey(_title), 'Намерение');
        await tester.pumpAndSettle();
        final session = sessions.single;
        final compact = _sheetRect(tester);

        // Короткое движение ручки не меняет режим.
        await tester.drag(find.byKey(_handle), const Offset(0, -8));
        await tester.pumpAndSettle();
        expect(_sheetRect(tester), compact);

        await tester.drag(find.byKey(_handle), const Offset(0, -240));
        await tester.pumpAndSettle();
        expect(_sheetRect(tester), _expandedArea(_portrait));
        expect(sessions.state(tester).sheetMode, _expandedMode);

        // Даже быстрый свайп вниз из развёрнутой панели только сворачивает.
        await tester.fling(find.byKey(_handle), const Offset(0, 400), 3000);
        await tester.pumpAndSettle();
        expect(_sheetRect(tester), compact);
        expect(sessions.state(tester).sheetMode, _compactMode);
        expect(find.byKey(_closeConfirmation), findsNothing);
        expect(router.current.name, IntentionEditorRoute.name);

        await tester.drag(find.byKey(_handle), const Offset(0, 240));
        await tester.pumpAndSettle();
        expect(find.byKey(_closeConfirmation), findsOneWidget);

        await tester.tap(find.byKey(_closeContinue));
        await tester.pumpAndSettle();
        expect(router.current.name, IntentionEditorRoute.name);
        expect(_sheetRect(tester), compact);
        expect(_controller(tester, _title).text, 'Намерение');
        _expectSameSession(tester, sessions, session);
        expect(repository.commands, isEmpty);
      },
    );

    testWidgets(
      'свайп вниз из компактной неизменённой панели сразу закрывает её, а из развёрнутой — только сворачивает',
      (tester) async {
        _usePhone(tester, _portrait);
        final sessions = _EditorSessions();
        final repository = ControlledCatalogRepository();
        final router = await _openEditor(tester, repository, sessions);

        await tester.tap(find.byKey(_resize));
        await tester.pumpAndSettle();
        await tester.drag(find.byKey(_handle), const Offset(0, 240));
        await tester.pumpAndSettle();
        expect(router.current.name, IntentionEditorRoute.name);
        expect(sessions.state(tester).sheetMode, _compactMode);

        await tester.drag(find.byKey(_handle), const Offset(0, 240));
        await tester.pumpAndSettle();
        expect(find.byKey(_closeConfirmation), findsNothing);
        expectIntentionGraphRootPage(router);
        expect(repository.commands, isEmpty);
      },
    );

    testWidgets(
      'прокрутка полей в обоих режимах не закрывает, не разворачивает и не сворачивает панель',
      (tester) async {
        _usePhone(tester, _portrait);
        final sessions = _EditorSessions();
        final repository = ControlledCatalogRepository();
        final router = await _openEditor(tester, repository, sessions);
        await tester.enterText(find.byKey(_description), _lines(60));
        await tester.pumpAndSettle();
        _fieldsPosition(tester).jumpTo(0);
        await tester.pumpAndSettle();
        final compact = _sheetRect(tester);

        // Свайп вниз по полям у их начала — прокрутка, а не закрытие.
        await tester.fling(find.byKey(_fields), const Offset(0, 300), 3000);
        await tester.pumpAndSettle();
        await tester.fling(find.byKey(_fields), const Offset(0, -300), 3000);
        await tester.pumpAndSettle();
        expect(_fieldsPosition(tester).pixels, greaterThan(0));
        expect(_sheetRect(tester), compact);
        expect(sessions.state(tester).sheetMode, _compactMode);
        expect(find.byKey(_closeConfirmation), findsNothing);
        expect(router.current.name, IntentionEditorRoute.name);

        await tester.tap(find.byKey(_resize));
        await tester.pumpAndSettle();
        await tester.fling(find.byKey(_fields), const Offset(0, 600), 3000);
        await tester.pumpAndSettle();
        expect(_fieldsPosition(tester).pixels, 0);
        expect(_sheetRect(tester), _expandedArea(_portrait));
        expect(sessions.state(tester).sheetMode, _expandedMode);
        expect(find.byKey(_closeConfirmation), findsNothing);
        expect(router.current.name, IntentionEditorRoute.name);
        expect(repository.commands, isEmpty);
      },
    );

    testWidgets(
      'длинное описание прокручивается внутри компактной панели без разворачивания, а смена режима сохраняет положение содержимого',
      (tester) async {
        _usePhone(tester, _portrait);
        final sessions = _EditorSessions();
        final repository = ControlledCatalogRepository();
        await _openEditor(tester, repository, sessions);

        await tester.enterText(find.byKey(_description), _lines(120));
        await tester.pumpAndSettle();
        final compact = _sheetRect(tester);
        _expectCompact(tester, compact, _portrait);
        expect(sessions.state(tester).sheetMode, _compactMode);
        expect(
          tester.getSize(find.byKey(_description)).height,
          greaterThan(compact.height),
        );
        expect(find.byKey(_submit).hitTestable(), findsOneWidget);

        _fieldsPosition(tester).jumpTo(400);
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(_resize));
        await tester.pumpAndSettle();
        expect(_sheetRect(tester), _expandedArea(_portrait));
        expect(_fieldsPosition(tester).pixels, 400);

        await tester.tap(find.byKey(_resize));
        await tester.pumpAndSettle();
        expect(_sheetRect(tester), compact);
        expect(_fieldsPosition(tester).pixels, 400);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'много содержимого в полях прокручивается внутри компактной панели, а отправка остаётся закреплённой',
      (tester) async {
        _usePhone(tester, _portrait);
        var mode = IntentionCreationSheetMode.compact;
        await tester.pumpWidget(
          MaterialApp(
            home: StatefulBuilder(
              builder: (context, setState) => IntentionCreationSheet(
                mode: mode,
                onExpand: () =>
                    setState(() => mode = IntentionCreationSheetMode.expanded),
                onCollapse: () =>
                    setState(() => mode = IntentionCreationSheetMode.compact),
                closeLabel: 'Close the form',
                expandLabel: 'Expand the form',
                collapseLabel: 'Collapse the form',
                onCloseRequested: () {},
                header: const Text('Create intention'),
                fields: Wrap(
                  spacing: 8,
                  children: [
                    for (var tag = 1; tag <= 80; tag++)
                      Chip(label: Text('Тег $tag')),
                  ],
                ),
                footer: FilledButton(
                  key: _submit,
                  onPressed: () {},
                  child: const Text('Save'),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final compact = _sheetRect(tester);
        _expectCompact(tester, compact, _portrait);
        expect(find.text('Тег 80').hitTestable(), findsNothing);
        await tester.scrollUntilVisible(
          find.text('Тег 80'),
          200,
          scrollable: _fieldsScrollable,
        );
        expect(find.text('Тег 80').hitTestable(), findsOneWidget);
        expect(_sheetRect(tester), compact);
        expect(mode, IntentionCreationSheetMode.compact);

        await tester.tap(find.byKey(_resize));
        await tester.pumpAndSettle();
        expect(_sheetRect(tester), _expandedArea(_portrait));
        expect(find.byKey(_submit).hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  });

  group('клавиатура и системные отступы', () {
    for (final device in [_portrait, _landscape]) {
      testWidgets(
        'клавиатура на ${device.name} пересчитывает геометрию обоих режимов без их смены, а её скрытие сохраняет панель и черновик',
        (tester) async {
          _usePhone(tester, device);
          final sessions = _EditorSessions();
          final repository = ControlledCatalogRepository();
          final router = await _openEditor(tester, repository, sessions);
          await tester.enterText(find.byKey(_title), 'Намерение');
          await tester.pumpAndSettle();
          final session = sessions.single;

          _usePhone(tester, device, keyboard: true);
          await tester.pumpAndSettle();
          _expectCompact(tester, _sheetRect(tester), device, keyboard: true);
          expect(sessions.state(tester).sheetMode, _compactMode);
          _expectSubmitAvailable(tester, device, keyboard: true);

          await tester.tap(find.byKey(_resize));
          await tester.pumpAndSettle();
          expect(_sheetRect(tester), _expandedArea(device, keyboard: true));
          _expectSubmitAvailable(tester, device, keyboard: true);

          // Скрытие клавиатуры по правилам платформы меняет только геометрию.
          _usePhone(tester, device);
          await tester.pumpAndSettle();
          expect(_sheetRect(tester), _expandedArea(device));
          expect(sessions.state(tester).sheetMode, _expandedMode);
          _expectSubmitAvailable(tester, device);

          _usePhone(tester, device, keyboard: true);
          await tester.pumpAndSettle();
          expect(_sheetRect(tester), _expandedArea(device, keyboard: true));
          expect(sessions.state(tester).sheetMode, _expandedMode);

          await tester.tap(find.byKey(_resize));
          await tester.pumpAndSettle();
          _expectCompact(tester, _sheetRect(tester), device, keyboard: true);

          _usePhone(tester, device);
          await tester.pumpAndSettle();
          _expectCompact(tester, _sheetRect(tester), device);
          expect(sessions.state(tester).sheetMode, _compactMode);
          expect(router.current.name, IntentionEditorRoute.name);
          expect(find.byKey(_closeConfirmation), findsNothing);
          expect(_controller(tester, _title).text, 'Намерение');
          expect(sessions.state(tester).draft.title, 'Намерение');
          _expectSameSession(tester, sessions, session);
          expect(repository.commands, isEmpty);
          expect(tester.takeException(), isNull);
        },
      );
    }

    for (final device in [_portrait, _landscape]) {
      for (final textScale in [_androidMaxTextScale, _beyondMaxTextScale]) {
        // На максимуме Android «Сохранить» видно целиком. Сверх него
        // закреплённая часть может не поместиться над клавиатурой даже в
        // развёрнутом виде: кнопка остаётся нажимаемой, а остаток части
        // доступен её прокруткой.
        final isSubmitFullyVisible = textScale <= _androidMaxTextScale;
        testWidgets(
          'на ${device.name} с клавиатурой и масштабом текста ${(textScale * 100).round()}% отправка и размер доступны в обоих режимах без переполнений',
          (tester) async {
            _usePhone(tester, device, keyboard: true);
            tester.platformDispatcher.textScaleFactorTestValue = textScale;
            addTearDown(
              tester.platformDispatcher.clearTextScaleFactorTestValue,
            );
            final sessions = _EditorSessions();
            final repository = ControlledCatalogRepository();
            await _openEditor(tester, repository, sessions);
            await tester.enterText(find.byKey(_description), _lines(12));
            await tester.pumpAndSettle();

            _expectCompact(tester, _sheetRect(tester), device, keyboard: true);
            expect(sessions.state(tester).sheetMode, _compactMode);
            _expectSubmitAvailable(
              tester,
              device,
              keyboard: true,
              fullyVisible: isSubmitFullyVisible,
            );
            expect(find.byKey(_resize).hitTestable(), findsOneWidget);
            expect(find.byKey(_closeButton).hitTestable(), findsOneWidget);
            expect(tester.takeException(), isNull);

            await tester.tap(find.byKey(_resize));
            await tester.pumpAndSettle();
            expect(_sheetRect(tester), _expandedArea(device, keyboard: true));
            _expectSubmitAvailable(
              tester,
              device,
              keyboard: true,
              fullyVisible: isSubmitFullyVisible,
            );
            expect(find.byKey(_resize).hitTestable(), findsOneWidget);

            if (!isSubmitFullyVisible) {
              // Сверх максимума Android полям над клавиатурой может не
              // остаться места; скрытие клавиатуры возвращает его, не меняя
              // режим.
              _usePhone(tester, device);
              await tester.pumpAndSettle();
              expect(_sheetRect(tester), _expandedArea(device));
              _expectSubmitAvailable(tester, device);
            }
            // Поля доступны прокруткой и в самом тесном развёрнутом виде.
            final viewport = tester.getRect(find.byKey(_fields));
            expect(viewport.height, greaterThan(0));
            await tester.ensureVisible(find.byKey(_title));
            await tester.pumpAndSettle();
            final title = tester.getRect(find.byKey(_title));
            expect(title.top, lessThan(viewport.bottom));
            expect(title.bottom, greaterThan(viewport.top));
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  });

  group('сохранение сессии', () {
    testWidgets(
      'продолжение после запроса закрытия сохраняет режим, контроллеры, фокус и положение содержимого',
      (tester) async {
        _usePhone(tester, _portrait);
        final sessions = _EditorSessions();
        final repository = ControlledCatalogRepository();
        final router = await _openEditor(tester, repository, sessions);
        await tester.enterText(find.byKey(_description), _lines(120));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(_resize));
        await tester.pumpAndSettle();
        // Поля прокручены к каретке в конце введённого описания.
        final controller = _controller(tester, _description);
        final position = _fieldsPosition(tester).pixels;
        expect(position, greaterThan(0));
        final session = sessions.single;

        await tester.tap(find.byKey(_closeButton));
        await tester.pumpAndSettle();
        expect(find.byKey(_closeConfirmation), findsOneWidget);
        await tester.tap(find.byKey(_closeContinue));
        await tester.pumpAndSettle();

        expect(router.current.name, IntentionEditorRoute.name);
        expect(_sheetRect(tester), _expandedArea(_portrait));
        expect(sessions.state(tester).sheetMode, _expandedMode);
        expect(_fieldsPosition(tester).pixels, position);
        expect(controller.selection.baseOffset, _lines(120).length);
        expect(_controller(tester, _description), same(controller));
        expect(controller.text, _lines(120));
        expect(_hasFocus(tester, _description), isTrue);
        _expectSameSession(tester, sessions, session);
        expect(repository.commands, isEmpty);
      },
    );

    testWidgets(
      'каждое новое открытие создания начинается в компактном режиме',
      (tester) async {
        _usePhone(tester, _portrait);
        final sessions = _EditorSessions();
        final repository = ControlledCatalogRepository();
        final router = await _openEditor(tester, repository, sessions);
        final compact = _sheetRect(tester);

        // Неизменённая развёрнутая панель закрывается сразу.
        await tester.tap(find.byKey(_resize));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(_closeButton));
        await tester.pumpAndSettle();
        expectIntentionGraphRootPage(router);

        await tester.tap(find.byKey(_catalogCreate));
        await tester.pumpAndSettle();
        expect(sessions.added, hasLength(2));
        expect(sessions.state(tester).sheetMode, _compactMode);
        expect(_sheetRect(tester), compact);

        // Изменённая развёрнутая панель закрывается подтверждённым сбросом.
        await tester.enterText(find.byKey(_title), 'Намерение');
        await tester.tap(find.byKey(_resize));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(_closeButton));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(_closeDiscard));
        await tester.pumpAndSettle();
        expectIntentionGraphRootPage(router);

        await tester.tap(find.byKey(_catalogCreate));
        await tester.pumpAndSettle();
        expect(sessions.added, hasLength(3));
        expect(sessions.state(tester).sheetMode, _compactMode);
        expect(sessions.state(tester).draft.isChanged, isFalse);
        expect(_sheetRect(tester), compact);
        expect(repository.commands, isEmpty);
      },
    );

    testWidgets(
      'изменение размера доступно экранному диктору без жеста и локализовано',
      (tester) async {
        final semantics = tester.ensureSemantics();
        _usePhone(tester, _portrait);
        for (final (locale, expand, collapse) in [
          (const Locale('en'), 'Expand the form', 'Collapse the form'),
          (const Locale('ru'), 'Развернуть форму', 'Свернуть форму'),
        ]) {
          final sessions = _EditorSessions();
          final repository = ControlledCatalogRepository();
          await _openEditor(tester, repository, sessions, locale: locale);
          await tester.enterText(find.byKey(_title), 'Намерение');
          await tester.pumpAndSettle();

          expect(
            tester.getSemantics(find.byKey(_resize)),
            isSemantics(tooltip: expand, isButton: true, hasTapAction: true),
          );
          tester.semantics.tap(_byTooltip(expand));
          await tester.pumpAndSettle();
          expect(_sheetRect(tester), _expandedArea(_portrait));
          expect(
            tester.getSemantics(find.byKey(_resize)),
            isSemantics(tooltip: collapse, isButton: true, hasTapAction: true),
          );

          tester.semantics.tap(_byTooltip(collapse));
          await tester.pumpAndSettle();
          expect(sessions.state(tester).sheetMode, _compactMode);
          expect(find.byKey(_closeConfirmation), findsNothing);
          expect(_controller(tester, _title).text, 'Намерение');
          await tester.pumpWidget(const SizedBox.shrink());
        }
        semantics.dispose();
      },
    );
  });
}

const _sheet = ValueKey('intention-creation-sheet');
const _handle = ValueKey('intention-creation-sheet-handle');
const _resize = ValueKey('intention-creation-sheet-resize');
const _fields = ValueKey('intention-creation-sheet-fields');
const _closeButton = ValueKey('intention-editor-close');
const _title = ValueKey('intention-editor-title');
const _description = ValueKey('intention-editor-description');
const _submit = ValueKey('intention-editor-submit');
const _catalogCreate = ValueKey('catalog-create-intention');
const _closeConfirmation = ValueKey('intention-editor-close-confirmation');
const _closeContinue = ValueKey('intention-editor-close-continue');
const _closeDiscard = ValueKey('intention-editor-close-discard');

const _compactMode = IntentionCreationSheetMode.compact;
const _expandedMode = IntentionCreationSheetMode.expanded;

/// Участок страницы под строкой состояния, видимый над компактной панелью.
const _visibleContextExtent = 72.0;

/// Наименьший видимый участок страницы над компактной панелью, когда
/// закреплённые части не помещаются в обычное компактное ограничение.
const _minVisibleContextExtent = 24.0;

/// Наибольшая ширина панели на широком экране.
const _maxSheetWidth = 640.0;

/// Наибольший масштаб системного шрифта Android — платформы приложения.
const _androidMaxTextScale = 2.0;

/// Масштаб сверх максимума Android: геометрия не должна опираться на это
/// ограничение платформы.
const _beyondMaxTextScale = 3.0;

/// Телефон: логический размер экрана, системные отступы, высота экранной
/// клавиатуры и наименьший ожидаемый видимый участок страницы над
/// компактной панелью при открытой клавиатуре.
typedef _Device = ({
  String name,
  Size size,
  EdgeInsets padding,
  double keyboard,
  double visibleContextWithKeyboard,
});

const _Device _portrait = (
  name: 'телефоне в портретной ориентации',
  size: Size(360, 740),
  padding: EdgeInsets.only(top: 24, bottom: 24),
  keyboard: 280,
  visibleContextWithKeyboard: _visibleContextExtent,
);

/// Над клавиатурой остаётся так мало высоты, что видимый участок страницы
/// уступает место закреплённым частям панели.
const _Device _landscape = (
  name: 'телефоне в альбомной ориентации',
  size: Size(740, 360),
  padding: EdgeInsets.only(top: 24, right: 48),
  keyboard: 180,
  visibleContextWithKeyboard: _minVisibleContextExtent,
);

/// Ставит экран [device]; открытая клавиатура закрывает нижний безопасный
/// отступ, как на устройстве.
void _usePhone(WidgetTester tester, _Device device, {bool keyboard = false}) {
  final keyboardHeight = keyboard ? device.keyboard : 0.0;
  tester.view.physicalSize = device.size;
  tester.view.devicePixelRatio = 1;
  tester.view.padding = FakeViewPadding(
    left: device.padding.left,
    top: device.padding.top,
    right: device.padding.right,
    bottom: math.max(0, device.padding.bottom - keyboardHeight),
  );
  tester.view.viewPadding = FakeViewPadding(
    left: device.padding.left,
    top: device.padding.top,
    right: device.padding.right,
    bottom: device.padding.bottom,
  );
  tester.view.viewInsets = FakeViewPadding(bottom: keyboardHeight);
  addTearDown(tester.view.reset);
}

/// Вся доступная панели область экрана: под строкой состояния, над
/// клавиатурой и по центру в пределах наибольшей ширины панели.
Rect _expandedArea(_Device device, {bool keyboard = false}) {
  final width = math.min(device.size.width, _maxSheetWidth);
  final left = (device.size.width - width) / 2;
  return Rect.fromLTRB(
    left,
    device.padding.top,
    left + width,
    device.size.height - (keyboard ? device.keyboard : 0),
  );
}

/// Компактная панель стоит над клавиатурой и оставляет видимым участок
/// страницы под строкой состояния.
void _expectCompact(
  WidgetTester tester,
  Rect sheet,
  _Device device, {
  bool keyboard = false,
}) {
  final area = _expandedArea(device, keyboard: keyboard);
  expect(sheet.bottom, area.bottom);
  expect(sheet.left, area.left);
  expect(sheet.right, area.right);
  expect(
    sheet.top,
    greaterThanOrEqualTo(
      area.top +
          (keyboard
              ? device.visibleContextWithKeyboard
              : _visibleContextExtent),
    ),
    reason: 'над компактной панелью виден участок страницы',
  );
}

/// «Сохранить» нажимается внутри панели над клавиатурой; при [fullyVisible]
/// кнопка видна целиком.
void _expectSubmitAvailable(
  WidgetTester tester,
  _Device device, {
  bool keyboard = false,
  bool fullyVisible = true,
}) {
  final submit = find.byKey(_submit);
  expect(submit.hitTestable(), findsOneWidget);
  final rect = tester.getRect(submit);
  final sheet = _sheetRect(tester);
  expect(rect.top, greaterThanOrEqualTo(sheet.top));
  expect(rect.center.dy, lessThan(sheet.bottom));
  if (fullyVisible) {
    expect(rect.bottom, lessThanOrEqualTo(sheet.bottom));
    expect(
      rect.bottom,
      lessThanOrEqualTo(_expandedArea(device, keyboard: keyboard).bottom),
    );
  }
}

SemanticsFinder _byTooltip(String tooltip) => find.semantics.byPredicate(
  (node) => node.tooltip == tooltip,
  describeMatch: (_) => 'узел с подсказкой «$tooltip»',
);

Rect _sheetRect(WidgetTester tester) => tester.getRect(find.byKey(_sheet));

Finder get _fieldsScrollable => find
    .descendant(of: find.byKey(_fields), matching: find.byType(Scrollable))
    .first;

ScrollPosition _fieldsPosition(WidgetTester tester) =>
    tester.state<ScrollableState>(_fieldsScrollable).position;

TextEditingController _controller(WidgetTester tester, Key field) =>
    tester.widget<TextField>(find.byKey(field)).controller!;

bool _hasFocus(WidgetTester tester, Key field) => tester
    .widget<EditableText>(
      find.descendant(
        of: find.byKey(field),
        matching: find.byType(EditableText),
      ),
    )
    .focusNode
    .hasFocus;

String _lines(int count) =>
    [for (var line = 1; line <= count; line++) 'Строка $line'].join('\n');

/// Та же сессия: новая не построена, прежняя не освобождена.
void _expectSameSession(
  WidgetTester tester,
  _EditorSessions sessions,
  IntentionEditorViewModelProvider session,
) {
  expect(sessions.added, [same(session)]);
  expect(sessions.disposed, isEmpty);
  expect(sessions.latest, same(session));
}

/// Сессии формы создания, построенные и освобождённые за время теста.
final class _EditorSessions extends ProviderObserver {
  final added = <IntentionEditorViewModelProvider>[];
  final disposed = <IntentionEditorViewModelProvider>[];

  IntentionEditorViewModelProvider get latest => added.last;

  IntentionEditorViewModelProvider get single => added.single;

  @override
  void didAddProvider(ProviderObserverContext context, Object? value) {
    if (context.provider case final IntentionEditorViewModelProvider provider) {
      added.add(provider);
    }
  }

  @override
  void didDisposeProvider(ProviderObserverContext context) {
    if (context.provider case final IntentionEditorViewModelProvider provider) {
      disposed.add(provider);
    }
  }

  IntentionEditorState state(WidgetTester tester) => ProviderScope.containerOf(
    tester.element(find.byType(IntentionEditorPage)),
  ).read(latest);
}

Future<AppRouter> _openEditor(
  WidgetTester tester,
  ControlledCatalogRepository repository,
  _EditorSessions sessions, {
  Locale locale = const Locale('en'),
}) async {
  final router = AppRouter();
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        personalGraphRepositoryProvider.overrideWithValue(repository),
      ],
      observers: [sessions],
      retry: (retryCount, error) => null,
      child: MaterialApp.router(
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router.config(),
        builder: (context, child) =>
            GraphOperationPresenter(child: child ?? const SizedBox.shrink()),
      ),
    ),
  );
  await tester.pump();
  await openIntentionGraph(tester);
  repository.complete(
    0,
    ResultSuccess(
      IntentionCatalogFirstPage(
        items: const [],
        totalCount: 0,
        nextCursor: null,
        revision: const TestCatalogRevision(0),
      ),
    ),
  );
  await tester.pumpAndSettle();
  expect(find.byType(IntentionCatalogPage), findsOneWidget);
  await tester.tap(find.byKey(_catalogCreate));
  await tester.pumpAndSettle();
  return router;
}
