import 'dart:math' as math;

import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/src/app/routing/app_router.dart';
import 'package:doable/src/app/routing/app_router.gr.dart';
import 'package:doable/src/graph/application/graph_command_coordinator.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:doable/src/graph/presentation/graph_operation_presenter.dart';
import 'package:doable/src/graph/presentation/operation_failure_presentation.dart';
import 'package:doable/src/intention/application/intention_catalog.dart'
    hide IntentionCatalogPage;
import 'package:doable/src/intention/application/intention_command.dart';
import 'package:doable/src/intention/application/intention_result.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/intention/domain/intention_text.dart';
import 'package:doable/src/intention/presentation/catalog/intention_catalog_page.dart';
import 'package:doable/src/intention/presentation/editor/intention_creation_sheet.dart';
import 'package:doable/src/intention/presentation/editor/intention_editor_page.dart';
import 'package:doable/src/intention/presentation/editor/intention_editor_state.dart';
import 'package:doable/src/intention/presentation/editor/intention_editor_view_model.dart';
import 'package:doable/src/intention/presentation/operation/operation_state.dart';
import 'package:doable/src/tag/application/tag_read_result.dart';
import 'package:doable/src/tag/domain/tag.dart';
import 'package:doable/src/tag/domain/tag_id.dart';
import 'package:doable/src/tag/domain/tag_name.dart';
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

  group('геометрия и прокрутка компактной панели', () {
    testWidgets('панель не предоставляет кнопку изменения размера', (
      tester,
    ) async {
      _usePhone(tester, _portrait);
      final sessions = _EditorSessions();
      final repository = ControlledCatalogRepository();
      await _openEditor(tester, repository, sessions);

      expect(
        find.byKey(const ValueKey('intention-creation-sheet-resize')),
        findsNothing,
      );
      expect(find.byIcon(Icons.open_in_full), findsNothing);
      expect(find.byIcon(Icons.close_fullscreen), findsNothing);
      expect(find.byKey(_closeButton).hitTestable(), findsOneWidget);
      _expectSubmitAvailable(tester, _portrait);
    });

    for (final isFling in [false, true]) {
      testWidgets(
        '${isFling ? 'быстрый' : 'медленный'} свайп вверх по ручке сохраняет геометрию, черновик и сессию без отправки и закрытия',
        (tester) async {
          _usePhone(tester, _portrait);
          final sessions = _EditorSessions();
          final repository = ControlledCatalogRepository();
          final router = await _openEditor(tester, repository, sessions);
          await tester.enterText(find.byKey(_title), 'Намерение');
          await tester.enterText(find.byKey(_description), 'Описание');
          await tester.pumpAndSettle();
          final session = sessions.single;
          final draft = sessions.state(tester).draft;
          final compact = _sheetRect(tester);
          final stack = router.stack.length;
          final titleController = _controller(tester, _title);
          final descriptionController = _controller(tester, _description);

          if (isFling) {
            await tester.fling(find.byKey(_handle), const Offset(0, -60), 1500);
          } else {
            await tester.drag(find.byKey(_handle), const Offset(0, -120));
          }
          await tester.pumpAndSettle();

          expect(_sheetRect(tester), compact);
          expect(sessions.state(tester).draft, same(draft));
          _expectSameSession(tester, sessions, session);
          expect(_controller(tester, _title), same(titleController));
          expect(
            _controller(tester, _description),
            same(descriptionController),
          );
          expect(_hasFocus(tester, _description), isTrue);
          expect(router.current.name, IntentionEditorRoute.name);
          expect(router.stack.length, stack);
          expect(find.byKey(_closeConfirmation), findsNothing);
          expect(find.byKey(_closeButton).hitTestable(), findsOneWidget);
          _expectSubmitAvailable(tester, _portrait);
          expect(repository.commands, isEmpty);
          expect(tester.takeException(), isNull);
        },
      );
    }

    testWidgets(
      'рост и сокращение описания сохраняют сессию, контроллеры, ввод, фокус и маршрут',
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

        await tester.enterText(find.byKey(_description), _lines(6));
        await tester.pumpAndSettle();

        expect(_sheetRect(tester).height, greaterThan(compact.height));
        _expectCompact(tester, _sheetRect(tester), _portrait);
        _expectSubmitAvailable(tester, _portrait);
        expect(find.byKey(_closeConfirmation), findsNothing);
        _expectSameSession(tester, sessions, session);
        expect(router.stack.length, stack);
        expect(router.current.name, IntentionEditorRoute.name);
        expect(_controller(tester, _title), same(titleController));
        expect(_controller(tester, _description), same(descriptionController));
        expect(titleController.text, 'Намерение');
        expect(descriptionController.text, _lines(6));
        expect(_hasFocus(tester, _description), isTrue);
        expect(sessions.state(tester).draft.title, 'Намерение');
        expect(sessions.state(tester).draft.description, _lines(6));

        await tester.enterText(find.byKey(_description), 'Описание');
        await tester.pumpAndSettle();

        expect(_sheetRect(tester), compact);
        expect(find.byKey(_closeConfirmation), findsNothing);
        _expectSameSession(tester, sessions, session);
        expect(router.stack.length, stack);
        expect(_controller(tester, _description), same(descriptionController));
        expect(descriptionController.text, 'Описание');
        expect(_hasFocus(tester, _description), isTrue);
        expect(repository.commands, isEmpty);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'свайп вниз по ручке запрашивает закрытие изменённого черновика, а продолжение сохраняет панель и сессию',
      (tester) async {
        _usePhone(tester, _portrait);
        final sessions = _EditorSessions();
        final repository = ControlledCatalogRepository();
        final router = await _openEditor(tester, repository, sessions);
        await tester.enterText(find.byKey(_title), 'Намерение');
        await tester.pumpAndSettle();
        final session = sessions.single;
        final compact = _sheetRect(tester);

        // Короткое движение ручки не запрашивает закрытие.
        await tester.drag(find.byKey(_handle), const Offset(0, 8));
        await tester.pumpAndSettle();
        expect(_sheetRect(tester), compact);
        expect(find.byKey(_closeConfirmation), findsNothing);

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

    testWidgets('свайп вниз из неизменённой панели сразу закрывает её', (
      tester,
    ) async {
      _usePhone(tester, _portrait);
      final sessions = _EditorSessions();
      final repository = ControlledCatalogRepository();
      final router = await _openEditor(tester, repository, sessions);

      await tester.drag(find.byKey(_handle), const Offset(0, 240));
      await tester.pumpAndSettle();
      expect(find.byKey(_closeConfirmation), findsNothing);
      expectIntentionGraphRootPage(router);
      expect(repository.commands, isEmpty);
    });

    testWidgets(
      'прокрутка полей не закрывает панель и не меняет её геометрию или черновик',
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
        final draft = sessions.state(tester).draft;
        final session = sessions.single;

        // Свайп вниз по полям у их начала — прокрутка, а не закрытие.
        await tester.fling(find.byKey(_fields), const Offset(0, 300), 3000);
        await tester.pumpAndSettle();
        expect(_fieldsPosition(tester).pixels, 0);
        await tester.fling(find.byKey(_fields), const Offset(0, -300), 3000);
        await tester.pumpAndSettle();
        expect(_fieldsPosition(tester).pixels, greaterThan(0));
        expect(_sheetRect(tester), compact);
        expect(find.byKey(_closeConfirmation), findsNothing);
        expect(router.current.name, IntentionEditorRoute.name);
        expect(sessions.state(tester).draft, same(draft));
        _expectSameSession(tester, sessions, session);
        _expectSubmitAvailable(tester, _portrait);
        expect(repository.commands, isEmpty);
      },
    );

    testWidgets(
      'длинное описание доступно прокруткой внутри компактной панели с доступным сохранением',
      (tester) async {
        _usePhone(tester, _portrait);
        final sessions = _EditorSessions();
        final repository = ControlledCatalogRepository();
        await _openEditor(tester, repository, sessions);

        await tester.enterText(find.byKey(_description), _lines(120));
        await tester.pumpAndSettle();
        final compact = _sheetRect(tester);
        _expectCompact(tester, compact, _portrait);
        expect(
          tester.getSize(find.byKey(_description)).height,
          greaterThan(compact.height),
        );
        _expectSubmitAvailable(tester, _portrait);

        _fieldsPosition(tester).jumpTo(400);
        await tester.pumpAndSettle();
        expect(_sheetRect(tester), compact);
        expect(_fieldsPosition(tester).pixels, 400);
        expect(_controller(tester, _description).text, _lines(120));
        _expectSubmitAvailable(tester, _portrait);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'много содержимого в полях прокручивается внутри компактной панели, а отправка остаётся закреплённой',
      (tester) async {
        _usePhone(tester, _portrait);
        await tester.pumpWidget(
          MaterialApp(
            home: IntentionCreationSheet(
              closeLabel: 'Close the form',
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
        expect(find.byKey(_submit).hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  });

  group('клавиатура и системные отступы', () {
    for (final device in [_portrait, _landscape]) {
      testWidgets(
        'клавиатура на ${device.name} пересчитывает геометрию компактной панели, а её скрытие сохраняет панель и черновик',
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
          _expectSubmitAvailable(tester, device, keyboard: true);

          // Скрытие и повторное появление клавиатуры меняют геометрию.
          _usePhone(tester, device);
          await tester.pumpAndSettle();
          _expectCompact(tester, _sheetRect(tester), device);
          _expectSubmitAvailable(tester, device);
          _usePhone(tester, device, keyboard: true);
          await tester.pumpAndSettle();
          _expectCompact(tester, _sheetRect(tester), device, keyboard: true);
          _expectSubmitAvailable(tester, device, keyboard: true);
          _usePhone(tester, device);
          await tester.pumpAndSettle();
          _expectCompact(tester, _sheetRect(tester), device);
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
        // закреплённая часть может не поместиться над клавиатурой:
        // кнопка остаётся нажимаемой, а остаток части
        // доступен её прокруткой.
        final isSubmitFullyVisible = textScale <= _androidMaxTextScale;
        testWidgets(
          'на ${device.name} с клавиатурой и масштабом текста ${(textScale * 100).round()}% отправка и закрытие доступны в компактной панели без переполнений',
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
            _expectSubmitAvailable(
              tester,
              device,
              keyboard: true,
              fullyVisible: isSubmitFullyVisible,
            );
            expect(find.byKey(_closeButton).hitTestable(), findsOneWidget);
            expect(tester.takeException(), isNull);

            if (!isSubmitFullyVisible) {
              // Сверх максимума Android полям над клавиатурой может не
              // остаться места; скрытие клавиатуры возвращает его, не меняя
              // черновик.
              _usePhone(tester, device);
              await tester.pumpAndSettle();
              _expectCompact(tester, _sheetRect(tester), device);
              _expectSubmitAvailable(tester, device);
            }
            // Поля доступны прокруткой при достаточной высоте над клавиатурой
            // либо после её скрытия при масштабе сверх максимума Android.
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

    for (final (device, minFieldsHeight) in [
      // Высоты над клавиатурой хватает только на часть области полей.
      (_landscape, 1.0),
      (_wideLandscape, kMinInteractiveDimension),
    ]) {
      testWidgets(
        'компактная панель над клавиатурой на ${device.name} уменьшает видимый участок страницы не ниже минимума ради видимой области полей, а название доступно касанию и экранному диктору',
        (tester) async {
          final semantics = tester.ensureSemantics();
          _usePhone(tester, device, keyboard: true);
          final sessions = _EditorSessions();
          final repository = ControlledCatalogRepository();
          await _openEditor(tester, repository, sessions);
          await tester.enterText(find.byKey(_description), _lines(12));
          await tester.pumpAndSettle();

          _expectCompact(tester, _sheetRect(tester), device, keyboard: true);
          _expectSubmitAvailable(tester, device, keyboard: true);
          expect(
            tester.getRect(find.byKey(_fields)).height,
            greaterThanOrEqualTo(minFieldsHeight),
          );
          await _scrollToCenter(tester, _title);
          expect(find.byKey(_title).hitTestable(), findsOneWidget);
          expect([
            for (final node
                in tester.semantics.simulatedAccessibilityTraversal())
              node.label,
          ], containsAll(['Title', 'Description (optional)']));
          expect(tester.takeException(), isNull);
          semantics.dispose();
        },
      );
    }
  });

  group('сохранение сессии', () {
    testWidgets(
      'продолжение после запроса закрытия сохраняет геометрию, контроллеры, фокус и положение содержимого',
      (tester) async {
        _usePhone(tester, _portrait);
        final sessions = _EditorSessions();
        final repository = ControlledCatalogRepository();
        final router = await _openEditor(tester, repository, sessions);
        await tester.enterText(find.byKey(_description), _lines(120));
        await tester.pumpAndSettle();
        final compact = _sheetRect(tester);
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
        expect(_sheetRect(tester), compact);
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
      'каждое новое открытие имеет самостоятельную сессию и пустой черновик',
      (tester) async {
        _usePhone(tester, _portrait);
        final sessions = _EditorSessions();
        final repository = ControlledCatalogRepository();
        final router = await _openEditor(tester, repository, sessions);
        final compact = _sheetRect(tester);

        final first = sessions.single;
        // Неизменённая панель закрывается сразу.
        await tester.tap(find.byKey(_closeButton));
        await tester.pumpAndSettle();
        expectIntentionGraphRootPage(router);

        await tester.tap(find.byKey(_catalogCreate));
        await tester.pumpAndSettle();
        expect(sessions.added, hasLength(2));
        expect(sessions.latest, isNot(same(first)));
        expect(sessions.disposed, contains(same(first)));
        final second = sessions.latest;
        expect(_sheetRect(tester), compact);

        // Изменённая панель закрывается подтверждённым сбросом.
        await tester.enterText(find.byKey(_title), 'Намерение');
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(_closeButton));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(_closeDiscard));
        await tester.pumpAndSettle();
        expectIntentionGraphRootPage(router);

        await tester.tap(find.byKey(_catalogCreate));
        await tester.pumpAndSettle();
        expect(sessions.added, hasLength(3));
        expect(sessions.latest, isNot(same(second)));
        expect(sessions.disposed, contains(same(second)));
        expect(_controller(tester, _title).text, isEmpty);
        expect(_controller(tester, _description).text, isEmpty);
        expect(sessions.state(tester).draft.isChanged, isFalse);
        expect(_sheetRect(tester), compact);
        expect(repository.commands, isEmpty);
      },
    );
  });

  group('ошибки сохранения', () {
    for (final (name, field, reason, fieldKey, message) in _fieldFailures) {
      testWidgets(
        'в компактной панели ошибка $name доводит своё поле и собственный текст до видимости в прокрученных полях над клавиатурой, право ошибки подтверждается только по кадру с видимым сообщением, а исправление поля разрешает новую отправку',
        (tester) async {
          _usePhone(tester, _portrait, keyboard: true);
          final sessions = _EditorSessions();
          final repository = ControlledCatalogRepository();
          await _openEditor(tester, repository, sessions);
          await tester.enterText(find.byKey(_title), ' Намерение ');
          await tester.enterText(find.byKey(_description), _lines(40));
          await tester.pumpAndSettle();
          await _scrollAwayFrom(tester, fieldKey);
          final draft = sessions.state(tester).draft;

          await tester.tap(find.byKey(_submit));
          await tester.pump();
          repository.completeCommand(0, _textFailure(field, reason));
          await tester.idle();
          await tester.pump();

          final claim = _failureClaim(tester);
          for (var frame = 0; _isClaimPending(tester, claim); frame++) {
            expect(frame, lessThan(60), reason: 'сообщение становится видимым');
            await tester.pump(const Duration(milliseconds: 16));
          }
          _expectInsideFields(tester, find.text(message));
          await tester.pumpAndSettle();

          _expectInsideFields(tester, find.text(message));
          _expectFieldEndVisible(tester, fieldKey);
          expect(find.byType(SnackBar), findsNothing);
          expect(sessions.state(tester).draft, same(draft));
          expect(_controller(tester, _title).text, ' Намерение ');
          expect(_controller(tester, _description).text, _lines(40));
          expect(_submitButton(tester).onPressed, isNull);
          expect(repository.commands, hasLength(1));
          expect(tester.takeException(), isNull);

          // Исправление видимого поля снимает его ошибку и само не
          // отправляет команду.
          await tester.enterText(find.byKey(fieldKey), 'Исправлено');
          await tester.pumpAndSettle();

          expect(find.text(message), findsNothing);
          expect(_submitButton(tester).onPressed, isNotNull);
          expect(repository.commands, hasLength(1));
          expect(tester.takeException(), isNull);
        },
      );

      testWidgets(
        'в компактной панели ошибка $name остаётся видимой, когда скрытая на время отправки клавиатура возвращается',
        (tester) async {
          _usePhone(tester, _portrait, keyboard: true);
          final sessions = _EditorSessions();
          final repository = ControlledCatalogRepository();
          await _openEditor(tester, repository, sessions);
          await tester.enterText(find.byKey(_title), 'Намерение');
          await tester.enterText(find.byKey(_description), _lines(40));
          await tester.pumpAndSettle();
          await _scrollAwayFrom(tester, fieldKey);

          await tester.tap(find.byKey(_submit));
          await tester.pump();
          // Поля только для чтения во время отправки закрывают соединение
          // ввода, и платформа скрывает клавиатуру.
          _usePhone(tester, _portrait);
          await tester.pumpAndSettle();
          repository.completeCommand(0, _textFailure(field, reason));
          await tester.pumpAndSettle();
          _expectInsideFields(tester, find.text(message));

          // Поле снова принимает ввод, и клавиатура возвращается к нему.
          _usePhone(tester, _portrait, keyboard: true);
          await tester.pumpAndSettle();

          _expectInsideFields(tester, find.text(message));
          _expectFieldEndVisible(tester, fieldKey);
          expect(_hasFocus(tester, _description), isTrue);
          expect(repository.commands, hasLength(1));
          expect(tester.takeException(), isNull);
        },
      );
    }

    for (final (interruption, interrupt)
        in <(String, Future<void> Function(WidgetTester))>[
          (
            'прокрутка полей человеком',
            (tester) =>
                tester.fling(find.byKey(_fields), const Offset(0, -400), 3000),
          ),
          (
            'правка черновика',
            (tester) => tester.enterText(
              find.byKey(_description),
              '${_lines(40)}\nЕщё строка',
            ),
          ),
        ]) {
      testWidgets(
        '$interruption прекращает доведение ошибки до видимости при смене размеров полей',
        (tester) async {
          _usePhone(tester, _portrait, keyboard: true);
          final sessions = _EditorSessions();
          final repository = ControlledCatalogRepository();
          await _openEditor(tester, repository, sessions);
          await tester.enterText(find.byKey(_description), _lines(40));
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(_submit));
          await tester.pump();
          repository.completeCommand(
            0,
            _textFailure(
              IntentionTextField.title,
              IntentionTextValidationReason.empty,
            ),
          );
          await tester.pumpAndSettle();
          _expectInsideFields(tester, find.text('Enter a title.'));

          await interrupt(tester);
          await tester.pumpAndSettle();
          _expectAboveFields(tester, find.text('Enter a title.'));

          _usePhone(tester, _portrait);
          await tester.pumpAndSettle();
          _usePhone(tester, _portrait, keyboard: true);
          await tester.pumpAndSettle();

          _expectAboveFields(tester, find.text('Enter a title.'));
          expect(find.text('Enter a title.'), findsOneWidget);
          expect(repository.commands, hasLength(1));
        },
      );
    }

    for (final (failure, message, recovery) in _pinnedFailures) {
      testWidgets(
        'в компактной панели отказ «$message» с исправлением и повтором закреплён рядом с сохранением над клавиатурой при масштабе текста 200%, не сдвигая прокрученные поля',
        (tester) async {
          _usePhone(tester, _portrait, keyboard: true);
          tester.platformDispatcher.textScaleFactorTestValue =
              _androidMaxTextScale;
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
          final tags = [_tag(1, 'Дом'), _tag(2, 'Работа')];
          final sessions = _EditorSessions();
          final repository = ControlledCatalogRepository()
            ..tagObservations = _observedTags(tags);
          await _openEditor(tester, repository, sessions);
          sessions.notifier(tester)
            ..draftTagSet.add(tags[0])
            ..draftTagSet.add(tags[1])
            ..markFavorite()
            ..confirmReadiness();
          await tester.enterText(find.byKey(_title), 'Намерение');
          await tester.enterText(find.byKey(_description), _lines(12));
          await tester.pumpAndSettle();
          final draft = sessions.state(tester).draft;
          final pixels = _fieldsPosition(tester).pixels;
          expect(pixels, greaterThan(0));

          await tester.tap(find.byKey(_submit));
          await tester.pump();
          repository.completeCommand(0, ResultFailure(failure));
          await tester.pumpAndSettle();

          _expectPinned(tester, recovery);
          expect(_fieldsPosition(tester).pixels, pixels);
          expect(_isClaimPending(tester, _failureClaim(tester)), isFalse);
          expect(find.byType(SnackBar), findsNothing);
          expect(sessions.state(tester).draft, same(draft));
          expect(repository.commands, hasLength(1));
          expect(tester.takeException(), isNull);

          switch (recovery) {
            case _Recovery.removeMissingTags:
              expect(_submitButton(tester).onPressed, isNull);
              await tester.tap(find.byKey(_removeMissing));
              await tester.pumpAndSettle();

              // Исправление меняет только набор и само не отправляет.
              expect(sessions.state(tester).draft.tagIds, [_tagId(2)]);
              expect(find.byKey(_failure), findsNothing);
              expect(_submitButton(tester).onPressed, isNotNull);
              expect(repository.commands, hasLength(1));
            case _Recovery.retry:
              final first = _failureClaim(tester);
              await tester.tap(find.byKey(_submit));
              await tester.pump();

              expect(repository.commands, hasLength(2));
              expect(
                repository.commands.last,
                isA<CreateIntention>()
                    .having((command) => command.title, 'название', 'Намерение')
                    .having(
                      (command) => command.description,
                      'описание',
                      _lines(12),
                    )
                    .having((command) => command.tagIds, 'теги', [
                      _tagId(1),
                      _tagId(2),
                    ])
                    .having(
                      (command) => command.favoriteMark,
                      'избранное',
                      FavoriteMark.favorite,
                    )
                    .having(
                      (command) => command.readiness,
                      'готовность',
                      IntentionReadiness.ready,
                    ),
              );
              expect(find.byKey(_failure), findsNothing);
              repository.completeCommand(1, ResultFailure(failure));
              await tester.pumpAndSettle();

              // Повтор принят той же сессией как новая операция.
              final second = _failureClaim(tester);
              expect(second.token, isNot(same(first.token)));
              expect(_isClaimPending(tester, second), isFalse);
              expect(sessions.added, hasLength(1));
              expect(find.byType(SnackBar), findsNothing);
            case _Recovery.none:
              expect(_submitButton(tester).onPressed, isNull);
              // Правки, не устраняющие причину, отказ не снимают.
              await tester.ensureVisible(find.byKey(_favorite));
              await tester.pumpAndSettle();
              await tester.tap(find.byKey(_favorite));
              await tester.enterText(find.byKey(_title), 'Другое намерение');
              await tester.pumpAndSettle();

              expect(find.byKey(_failure), findsOneWidget);
              expect(_submitButton(tester).onPressed, isNull);
              expect(repository.commands, hasLength(1));
          }
          expect(tester.takeException(), isNull);
        },
      );
    }

    testWidgets(
      'любой отказ сохраняет все пять полей черновика в той же компактной панели',
      (tester) async {
        _usePhone(tester, _portrait);
        final failures = [
          for (final (name, field, reason, _, _) in _fieldFailures)
            (name, _textFailure(field, reason)),
          for (final (failure, message, _) in _pinnedFailures)
            (message, ResultFailure<IntentionCommandSuccess>(failure)),
        ];
        for (final (name, failure) in failures) {
          final tags = [_tag(1, 'Дом')];
          final sessions = _EditorSessions();
          final repository = ControlledCatalogRepository()
            ..tagObservations = _observedTags(tags);
          await _openEditor(tester, repository, sessions);
          sessions.notifier(tester)
            ..draftTagSet.add(tags.single)
            ..markFavorite()
            ..confirmReadiness();
          await tester.enterText(find.byKey(_title), '  Намерение');
          await tester.enterText(find.byKey(_description), 'Описание\n');
          await tester.pumpAndSettle();
          final session = sessions.single;
          final draft = sessions.state(tester).draft;

          await tester.tap(find.byKey(_submit));
          await tester.pump();
          repository.completeCommand(0, failure);
          await tester.pumpAndSettle();

          final state = sessions.state(tester);
          expect(
            state.operation,
            isA<OperationFailed<Intention>>(),
            reason: name,
          );
          expect(state.draft, same(draft), reason: name);
          expect(state.draft.tagIds, [_tagId(1)], reason: name);
          expect(state.draft.favoriteMark, FavoriteMark.favorite, reason: name);
          expect(state.draft.readiness, IntentionReadiness.ready, reason: name);
          expect(_controller(tester, _title).text, '  Намерение', reason: name);
          expect(
            _controller(tester, _description).text,
            'Описание\n',
            reason: name,
          );
          expect(find.byKey(_tagChip(1)), findsOneWidget, reason: name);
          _expectSameSession(tester, sessions, session);
          _expectCompact(tester, _sheetRect(tester), _portrait);
          _expectSubmitAvailable(tester, _portrait);
          expect(repository.commands, hasLength(1), reason: name);
          await tester.pumpWidget(const SizedBox.shrink());
        }
      },
    );
  });

  group('полный заполненный сценарий на тесном экране', () {
    for (final device in [_narrowPortrait, _narrowLandscape]) {
      for (final textScale in [_androidMaxTextScale, _beyondMaxTextScale]) {
        // До максимума Android «Сохранить» видно целиком, а сообщение отказа
        // читается без клавиатуры; сверх него кнопки остаются нажимаемыми, а
        // остаток закреплённой части прокручивается.
        final isWithinPlatformTextScale = textScale <= _androidMaxTextScale;
        testWidgets(
          'на ${device.name} с безопасными отступами, клавиатурой и масштабом текста ${(textScale * 100).round()}% все пять полей, закрытие, объяснения, сохранение и исправление отказов доступны без переполнений',
          (tester) async {
            final semantics = tester.ensureSemantics();
            _usePhone(tester, device, keyboard: true);
            tester.platformDispatcher.textScaleFactorTestValue = textScale;
            addTearDown(
              tester.platformDispatcher.clearTextScaleFactorTestValue,
            );
            final tags = [
              _tag(1, 'Дом'),
              _tag(2, 'Очень длинное название тега, которое переносится'),
            ];
            final sessions = _EditorSessions();
            final repository = ControlledCatalogRepository()
              ..tagObservations = _observedTags(tags);
            await _openEditor(tester, repository, sessions);
            const title = 'Длинное название намерения, которое переносится';
            await tester.enterText(find.byKey(_title), title);
            await tester.enterText(find.byKey(_description), _lines(8));
            sessions.notifier(tester)
              ..draftTagSet.add(tags[0])
              ..draftTagSet.add(tags[1]);
            await tester.pumpAndSettle();

            Future<void> expectUsable({required bool keyboard}) async {
              await _expectPanelUsable(
                tester,
                device,
                tagIds: sessions.state(tester).draft.tagIds,
                keyboard: keyboard,
                fullyVisibleSubmit: isWithinPlatformTextScale,
              );
            }

            await expectUsable(keyboard: true);

            // Отметки включаются действиями панели; объяснение готовности
            // забирает фокус у поля, и платформа скрывает клавиатуру.
            await _tapInFields(tester, device, _favorite);
            await _tapInFields(tester, device, _readiness);
            _usePhone(tester, device);
            await tester.pumpAndSettle();
            await _expectDialogUsable(tester, [
              _readinessCancel,
              _readinessConfirm,
            ]);
            await _tapDialogAction(tester, _readinessConfirm);
            _usePhone(tester, device, keyboard: true);
            await tester.pumpAndSettle();
            expect(
              sessions.state(tester).draft.favoriteMark,
              FavoriteMark.favorite,
            );
            expect(
              sessions.state(tester).draft.readiness,
              IntentionReadiness.ready,
            );
            await expectUsable(keyboard: true);

            // Скрытие клавиатуры возвращает полям место в компактной панели.
            _usePhone(tester, device);
            await tester.pumpAndSettle();
            await expectUsable(keyboard: false);

            // Подтверждение закрытия появляется, пока платформа скрывает
            // клавиатуру; продолжение сохраняет черновик и возвращает её.
            _usePhone(tester, device, keyboard: true);
            await tester.pumpAndSettle();
            await tester.tap(find.byKey(_closeButton));
            await tester.pumpAndSettle();
            _usePhone(tester, device);
            await tester.pumpAndSettle();
            await _expectDialogUsable(tester, [_closeContinue, _closeDiscard]);
            await _tapDialogAction(tester, _closeContinue);
            expect(sessions.state(tester).draft.title, title);
            _usePhone(tester, device, keyboard: true);
            await tester.pumpAndSettle();

            // Отказ из-за удалённого тега: поля только для чтения на время
            // отправки скрывают клавиатуру, а после отказа она возвращается.
            await tester.tap(find.byKey(_submit));
            await tester.pump();
            _usePhone(tester, device);
            repository.completeCommand(
              0,
              ResultFailure(IntentionCreationTagsMissingFailure([_tagId(1)])),
            );
            await tester.pumpAndSettle();
            _usePhone(tester, device, keyboard: true);
            await tester.pumpAndSettle();
            await _expectFailureRecoverable(
              tester,
              device,
              _removeMissing,
              'A selected tag was deleted from the catalog. Remove it from '
              'the draft to save the intention.',
              isMessageVisible: isWithinPlatformTextScale,
            );
            await tester.tapAt(
              _expectTappable(tester, find.byKey(_removeMissing)),
            );
            await tester.pumpAndSettle();
            expect(sessions.state(tester).draft.tagIds, [_tagId(2)]);
            if (isWithinPlatformTextScale) {
              // Панель сама показала отказ: общая поверхность его не
              // повторяет.
              expect(find.byType(SnackBar), findsNothing);
            } else {
              // Сообщение не поместилось в панель ни в одном кадре, поэтому
              // после исправления его предъявляет общая поверхность.
              await _waitForOperationMessages(tester);
            }
            await expectUsable(keyboard: true);

            // Устранимый отказ: повтор доступен в компактной панели.
            await tester.tap(find.byKey(_submit));
            await tester.pump();
            repository.completeCommand(
              1,
              const ResultFailure(IntentionUnavailableFailure()),
            );
            await tester.pumpAndSettle();
            await _expectFailureRecoverable(
              tester,
              device,
              _submit,
              'The intention couldn’t be created. Try again.',
              isMessageVisible: isWithinPlatformTextScale,
            );
            await tester.tap(find.byKey(_submit));
            await tester.pump();

            expect(repository.commands, hasLength(3));
            expect(
              repository.commands.last,
              isA<CreateIntention>()
                  .having((command) => command.title, 'название', title)
                  .having(
                    (command) => command.description,
                    'описание',
                    _lines(8),
                  )
                  .having((command) => command.tagIds, 'теги', [_tagId(2)])
                  .having(
                    (command) => command.favoriteMark,
                    'избранное',
                    FavoriteMark.favorite,
                  )
                  .having(
                    (command) => command.readiness,
                    'готовность',
                    IntentionReadiness.ready,
                  ),
            );
            expect(sessions.added, hasLength(1));
            expect(tester.takeException(), isNull);
            semantics.dispose();
          },
        );
      }
    }
  });
}

/// Геометрия, действия и поля компактной панели доступны на [device].
/// Если клавиатура и масштаб сверх максимума Android занимают всю область
/// полей, их доступность проверяется после скрытия клавиатуры.
Future<void> _expectPanelUsable(
  WidgetTester tester,
  _Device device, {
  required Iterable<TagId> tagIds,
  required bool keyboard,
  required bool fullyVisibleSubmit,
}) async {
  final reason = 'компактная панель, клавиатура: $keyboard';
  expect(tester.takeException(), isNull, reason: reason);
  _expectCompact(tester, _sheetRect(tester), device, keyboard: keyboard);
  _expectSubmitAvailable(
    tester,
    device,
    keyboard: keyboard,
    fullyVisible: fullyVisibleSubmit || !keyboard,
  );
  for (final action in [_closeButton, _submit]) {
    expect(find.byKey(action).hitTestable(), findsOneWidget, reason: reason);
    _expectInsideSafeArea(tester, device, action, keyboard: keyboard);
  }
  final fields = tester.getRect(find.byKey(_fields));
  if (fields.height == 0) {
    expect(keyboard, isTrue, reason: 'полям не осталось места: $reason');
    _usePhone(tester, device);
    await tester.pumpAndSettle();
    await _expectPanelUsable(
      tester,
      device,
      tagIds: tagIds,
      keyboard: false,
      fullyVisibleSubmit: true,
    );
    _usePhone(tester, device, keyboard: true);
    await tester.pumpAndSettle();
    return;
  }
  for (final control in [
    _title,
    _description,
    for (final id in tagIds)
      ValueKey('intention-editor-tag-remove-${id.toCanonicalString()}'),
    _chooseTags,
    _favorite,
    _readiness,
  ]) {
    await _scrollToCenter(tester, control);
    expect(
      find.byKey(control).hitTestable(),
      findsOneWidget,
      reason: '$control: $reason',
    );
    _expectInsideSafeArea(tester, device, control, keyboard: keyboard);
  }
  expect(tester.takeException(), isNull, reason: reason);
}

/// Прокручивает поля так, что середина [key] оказывается в середине их
/// видимой области.
Future<void> _scrollToCenter(WidgetTester tester, Key key) async {
  await Scrollable.ensureVisible(
    tester.element(find.byKey(key)),
    alignment: 0.5,
  );
  await tester.pumpAndSettle();
}

/// Нажимает действие полей, доведя его до видимости; при отсутствии места
/// полям сначала скрывает клавиатуру.
Future<void> _tapInFields(WidgetTester tester, _Device device, Key key) async {
  if (tester.getRect(find.byKey(_fields)).height == 0) {
    _usePhone(tester, device);
    await tester.pumpAndSettle();
  }
  await _scrollToCenter(tester, key);
  await tester.tap(find.byKey(key));
  await tester.pumpAndSettle();
}

/// Цель [key] не уходит под системные отступы: по горизонтали она целиком
/// между боковыми отступами, а середина её видимой части — в безопасной
/// области над клавиатурой. Видимая часть цели в полях ограничена их
/// видимой областью.
void _expectInsideSafeArea(
  WidgetTester tester,
  _Device device,
  Key key, {
  required bool keyboard,
}) {
  final fields = tester.getRect(find.byKey(_fields));
  var rect = tester.getRect(find.byKey(key));
  if (rect.overlaps(fields)) {
    rect = rect.intersect(fields);
  }
  final safe = Rect.fromLTRB(
    device.padding.left,
    device.padding.top,
    device.size.width - device.padding.right,
    device.size.height - (keyboard ? device.keyboard : device.padding.bottom),
  );
  expect(safe.contains(rect.center), isTrue, reason: '$key: $rect вне $safe');
  expect(rect.left, greaterThanOrEqualTo(safe.left), reason: '$key');
  expect(rect.right, lessThanOrEqualTo(safe.right), reason: '$key');
}

/// Действия диалога над панелью доводятся до видимости и нажимаются, а
/// диалог не переполняется.
Future<void> _expectDialogUsable(WidgetTester tester, List<Key> actions) async {
  expect(tester.takeException(), isNull);
  expect(find.byType(AlertDialog), findsOneWidget);
  for (final action in actions) {
    await tester.ensureVisible(find.byKey(action));
    await tester.pumpAndSettle();
    _expectTappable(tester, find.byKey(action));
  }
  expect(tester.takeException(), isNull);
}

Future<void> _tapDialogAction(WidgetTester tester, Key action) async {
  await tester.ensureVisible(find.byKey(action));
  await tester.pumpAndSettle();
  await tester.tapAt(_expectTappable(tester, find.byKey(action)));
  await tester.pumpAndSettle();
  expect(find.byType(AlertDialog), findsNothing);
}

/// Видимую часть [finder] можно нажать: касание середины этой части
/// попадает в цель. Возвращает точку касания.
///
/// Видимая часть — пересечение цели с экраном над клавиатурой и с областью
/// ближайшей прокрутки, внутри которой она лежит.
Offset _expectTappable(WidgetTester tester, Finder finder) {
  var visible = tester
      .getRect(finder)
      .intersect(
        Rect.fromLTRB(
          0,
          0,
          tester.view.physicalSize.width / tester.view.devicePixelRatio,
          _visibleBottom(tester),
        ),
      );
  final viewport = find.ancestor(of: finder, matching: find.byType(Scrollable));
  if (viewport.evaluate().isNotEmpty) {
    visible = visible.intersect(tester.getRect(viewport.first));
  }
  expect(visible.isEmpty, isFalse, reason: '$finder не видна');
  final target = tester.renderObject(finder);
  expect(
    tester
        .hitTestOnBinding(visible.center)
        .path
        .any((entry) => identical(entry.target, target)),
    isTrue,
    reason: 'касание видимой части $finder попадает в цель',
  );
  return visible.center;
}

/// В компактной панели исправление или повтор нажимается над клавиатурой,
/// а экранный диктор получает сообщение. При [isMessageVisible] начало
/// сообщения видно после скрытия клавиатуры. Сверх максимума системного
/// шрифта Android действия могут занять всю высоту закреплённой части.
Future<void> _expectFailureRecoverable(
  WidgetTester tester,
  _Device device,
  Key recovery,
  String message, {
  required bool isMessageVisible,
}) async {
  final failure = find.byKey(_failure);
  expect(tester.takeException(), isNull);
  // Закреплённый отказ с увеличенным текстом уменьшает видимый контекст.
  _expectCompact(
    tester,
    _sheetRect(tester),
    device,
    keyboard: true,
    minVisibleContext: _minVisibleContextExtent,
  );
  _expectTappable(tester, find.byKey(recovery));
  expect(find.byKey(_closeButton).hitTestable(), findsOneWidget);
  expect(
    tester.getSemantics(failure),
    isSemantics(label: message, isLiveRegion: true),
  );
  _usePhone(tester, device);
  await tester.pumpAndSettle();
  if (isMessageVisible) {
    final status = tester.getRect(find.byKey(_status));
    final text = tester.getRect(failure);
    expect(text.top, greaterThanOrEqualTo(status.top));
    expect(text.top, lessThan(status.bottom));
  }
  _expectTappable(tester, find.byKey(recovery));
  _usePhone(tester, device, keyboard: true);
  await tester.pumpAndSettle();
}

/// Дожидается, пока общая поверхность закроет свои сообщения.
Future<void> _waitForOperationMessages(WidgetTester tester) async {
  for (var attempt = 0; attempt < 5; attempt++) {
    if (find.byType(SnackBar).evaluate().isEmpty) {
      return;
    }
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  }
  expect(find.byType(SnackBar), findsNothing);
}

/// Способ восстановления после общего отказа, который предлагает панель.
enum _Recovery { removeMissingTags, retry, none }

/// Ошибки полей: название поля в описании проверки, поле и причина отказа,
/// ключ поля и текст ошибки.
const _fieldFailures =
    <(String, IntentionTextField, IntentionTextValidationReason, Key, String)>[
      (
        'названия',
        IntentionTextField.title,
        IntentionTextValidationReason.empty,
        _title,
        'Enter a title.',
      ),
      (
        'описания',
        IntentionTextField.description,
        IntentionTextValidationReason.tooLong,
        _description,
        'Use no more than 4096 characters.',
      ),
    ];

/// Общие отказы сохранения: причина, сообщение и предлагаемое восстановление.
final _pinnedFailures = <(IntentionFailure, String, _Recovery)>[
  (
    IntentionCreationTagsMissingFailure([_tagId(1)]),
    'A selected tag was deleted from the catalog. Remove it from the draft '
        'to save the intention.',
    _Recovery.removeMissingTags,
  ),
  (
    const IntentionUnavailableFailure(),
    'The intention couldn’t be created. Try again.',
    _Recovery.retry,
  ),
  (
    const IntentionConflictFailure(),
    'The intention couldn’t be created because of a conflict.',
    _Recovery.none,
  ),
  (
    const IntentionCorruptionFailure(),
    'Stored data is damaged. The intention wasn’t created.',
    _Recovery.none,
  ),
  (
    const IntentionUnexpectedFailure(),
    'The intention couldn’t be created because of an unexpected error.',
    _Recovery.none,
  ),
];

ResultFailure<IntentionCommandSuccess> _textFailure(
  IntentionTextField field,
  IntentionTextValidationReason reason,
) => ResultFailure(
  IntentionTextInputValidationFailure(
    IntentionTextValidationFailure(field: field, reason: reason),
  ),
);

/// Прокручивает поля так, что место будущей ошибки поля [field] оказывается
/// вне видимой области: к концу полей для названия и к их началу для
/// описания, которое длиннее области полей.
Future<void> _scrollAwayFrom(WidgetTester tester, Key field) async {
  final position = _fieldsPosition(tester);
  position.jumpTo(field == _title ? position.maxScrollExtent : 0);
  await tester.pumpAndSettle();
  final viewport = tester.getRect(find.byKey(_fields));
  final rect = tester.getRect(find.byKey(field));
  expect(
    rect.bottom <= viewport.top || rect.bottom > viewport.bottom,
    isTrue,
    reason: 'конец поля вне видимой области полей',
  );
}

/// Нижняя граница экрана над клавиатурой.
double _visibleBottom(WidgetTester tester) =>
    tester.view.physicalSize.height / tester.view.devicePixelRatio -
    tester.view.viewInsets.bottom / tester.view.devicePixelRatio;

/// [finder] целиком виден в области полей над клавиатурой.
void _expectInsideFields(WidgetTester tester, Finder finder) {
  final viewport = tester.getRect(find.byKey(_fields));
  final rect = tester.getRect(finder);
  expect(rect.top, greaterThanOrEqualTo(viewport.top));
  expect(rect.bottom, lessThanOrEqualTo(viewport.bottom));
  expect(viewport.bottom, lessThanOrEqualTo(_visibleBottom(tester)));
}

/// [finder] прокручен выше видимой области полей.
void _expectAboveFields(WidgetTester tester, Finder finder) => expect(
  tester.getRect(finder).bottom,
  lessThanOrEqualTo(tester.getRect(find.byKey(_fields)).top),
);

/// Поле [field] видно вместе со своим концом, где находится текст ошибки;
/// поле, которое помещается в области полей, видно целиком.
void _expectFieldEndVisible(WidgetTester tester, Key field) {
  final viewport = tester.getRect(find.byKey(_fields));
  final rect = tester.getRect(find.byKey(field));
  expect(rect.bottom, lessThanOrEqualTo(viewport.bottom));
  expect(rect.bottom, greaterThan(viewport.top));
  if (rect.height <= viewport.height) {
    expect(rect.top, greaterThanOrEqualTo(viewport.top));
  }
}

/// Общий отказ закреплён между полями и действиями: поля остаются видимыми,
/// начало сообщения видно над клавиатурой, а предложенные действия
/// нажимаются.
void _expectPinned(WidgetTester tester, _Recovery recovery) {
  final fields = tester.getRect(find.byKey(_fields));
  final status = tester.getRect(find.byKey(_status));
  final message = tester.getRect(find.byKey(_failure));
  final actions = [
    _submit,
    if (recovery == _Recovery.removeMissingTags) _removeMissing,
  ];
  expect(fields.height, greaterThan(0));
  expect(status.top, greaterThanOrEqualTo(fields.bottom));
  expect(message.top, greaterThanOrEqualTo(status.top));
  expect(message.top, lessThan(status.bottom));
  for (final action in actions) {
    final rect = tester.getRect(find.byKey(action));
    expect(rect.top, greaterThanOrEqualTo(status.bottom));
    expect(rect.bottom, lessThanOrEqualTo(_visibleBottom(tester)));
    expect(find.byKey(action).hitTestable(), findsOneWidget);
  }
  expect(
    find.widgetWithText(FilledButton, 'Try again'),
    recovery == _Recovery.retry ? findsOneWidget : findsNothing,
  );
  expect(
    find.byKey(_removeMissing),
    recovery == _Recovery.removeMissingTags ? findsOneWidget : findsNothing,
  );
}

GraphInitiatorPresentationClaim _failureClaim(WidgetTester tester) => tester
    .widget<OperationFailurePresentation>(
      find.byType(OperationFailurePresentation),
    )
    .claim!;

/// Право ошибки ещё у формы: не подтверждено и не передано общей
/// поверхности.
bool _isClaimPending(
  WidgetTester tester,
  GraphInitiatorPresentationClaim claim,
) => identical(
  ProviderScope.containerOf(tester.element(find.byType(IntentionEditorPage)))
      .read(graphCommandCoordinatorProvider.notifier)
      .claimInitiatorFailure(claim.token),
  claim,
);

FilledButton _submitButton(WidgetTester tester) =>
    tester.widget<FilledButton>(find.byKey(_submit));

Tag _tag(int number, String name) =>
    Tag(id: _tagId(number), name: TagName.fromInput(name));

TagId _tagId(int number) => switch (TagId.decode(
  '018f47c2-6b7d-7abc-8def-${number.toString().padLeft(12, '0')}',
)) {
  TagIdDecodingSuccess(:final id) => id,
  InvalidTagIdDecoding() => throw StateError('Некорректный UUID тега.'),
};

ValueKey<String> _tagChip(int number) =>
    ValueKey('intention-editor-tag-${_tagId(number).toCanonicalString()}');

/// Наблюдение подтверждает тег из [tags] и не завершается, пока наблюдатель
/// не освободит подписку.
Stream<TagReadResult> Function(TagId) _observedTags(List<Tag> tags) =>
    (id) => Stream.multi(
      (controller) => controller.add(
        TagReadSuccess(
          GraphSnapshot(
            value: tags.where((tag) => tag.id == id).firstOrNull,
            revision: const TestCatalogRevision(0),
          ),
        ),
      ),
    );

const _sheet = ValueKey('intention-creation-sheet');
const _handle = ValueKey('intention-creation-sheet-handle');
const _fields = ValueKey('intention-creation-sheet-fields');
const _closeButton = ValueKey('intention-editor-close');
const _title = ValueKey('intention-editor-title');
const _description = ValueKey('intention-editor-description');
const _submit = ValueKey('intention-editor-submit');
const _status = ValueKey('intention-creation-sheet-status');
const _failure = ValueKey('intention-editor-failure');
const _removeMissing = ValueKey('intention-editor-remove-missing-tags');
const _favorite = ValueKey('intention-editor-favorite');
const _readiness = ValueKey('intention-editor-readiness');
const _chooseTags = ValueKey('intention-editor-choose-tags');
const _readinessCancel = ValueKey('intention-editor-readiness-cancel');
const _readinessConfirm = ValueKey('intention-editor-readiness-confirm');
const _catalogCreate = ValueKey('catalog-create-intention');
const _closeConfirmation = ValueKey('intention-editor-close-confirmation');
const _closeContinue = ValueKey('intention-editor-close-continue');
const _closeDiscard = ValueKey('intention-editor-close-discard');

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

/// Распространённый телефон в альбомной ориентации: над клавиатурой
/// остаётся высота для закреплённых частей, наименьшей области полей и
/// части видимого участка страницы.
const _Device _wideLandscape = (
  name: 'распространённом телефоне в альбомной ориентации',
  size: Size(915, 412),
  padding: EdgeInsets.only(top: 24, right: 48),
  keyboard: 190,
  visibleContextWithKeyboard: _minVisibleContextExtent,
);

/// Узкий и низкий телефон: меньше обычного портретного экрана по обеим
/// сторонам, с отступами строки состояния и жестовой навигации.
const _Device _narrowPortrait = (
  name: 'узком и низком телефоне в портретной ориентации',
  size: Size(320, 568),
  padding: EdgeInsets.only(top: 24, bottom: 24),
  keyboard: 260,
  visibleContextWithKeyboard: _visibleContextExtent,
);

/// Тот же телефон в альбомной ориентации: панель навигации сбоку, а над
/// клавиатурой остаётся так мало высоты, что видимый участок страницы
/// уступает место закреплённым частям панели.
const _Device _narrowLandscape = (
  name: 'узком и низком телефоне в альбомной ориентации',
  size: Size(568, 320),
  padding: EdgeInsets.only(top: 24, right: 48),
  keyboard: 160,
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
Rect _availableArea(_Device device, {bool keyboard = false}) {
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
  double? minVisibleContext,
}) {
  final area = _availableArea(device, keyboard: keyboard);
  expect(sheet.bottom, area.bottom);
  expect(sheet.left, area.left);
  expect(sheet.right, area.right);
  expect(
    sheet.top,
    greaterThanOrEqualTo(
      area.top +
          (minVisibleContext ??
              (keyboard
                  ? device.visibleContextWithKeyboard
                  : _visibleContextExtent)),
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
      lessThanOrEqualTo(_availableArea(device, keyboard: keyboard).bottom),
    );
  }
}

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

  IntentionEditorViewModel notifier(WidgetTester tester) =>
      ProviderScope.containerOf(
        tester.element(find.byType(IntentionEditorPage)),
      ).read(latest.notifier);
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
