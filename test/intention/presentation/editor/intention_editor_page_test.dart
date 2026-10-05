import 'dart:async';
import 'dart:math' as math;

import 'package:auto_route/auto_route.dart';
import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/src/app/navigation/app_destination.dart';
import 'package:doable/src/app/navigation/app_navigation_bar.dart';
import 'package:doable/src/app/navigation/app_shell_page.dart';
import 'package:doable/src/app/routing/app_router.dart';
import 'package:doable/src/app/routing/app_router.gr.dart';
import 'package:doable/src/graph/application/graph_command_coordinator.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:doable/src/graph/presentation/graph_operation_presenter.dart';
import 'package:doable/src/graph/presentation/operation_failure_presentation.dart';
import 'package:doable/src/intention/application/intention_command.dart';
import 'package:doable/src/intention/application/intention_catalog.dart'
    hide IntentionCatalogPage;
import 'package:doable/src/intention/application/intention_result.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/intention/domain/intention_text.dart';
import 'package:doable/src/intention/presentation/catalog/intention_catalog_page.dart';
import 'package:doable/src/intention/presentation/editor/intention_editor_page.dart';
import 'package:doable/src/intention/presentation/editor/intention_editor_state.dart';
import 'package:doable/src/intention/presentation/editor/intention_editor_view_model.dart';
import 'package:doable/src/tag/domain/tag.dart';
import 'package:doable/src/tag/domain/tag_id.dart';
import 'package:doable/src/tag/domain/tag_name.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
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

  testWidgets('открывает generated route формы из каталога без readiness', (
    tester,
  ) async {
    final repository = ControlledCatalogRepository();
    final router = await _openEditor(tester, repository);

    const route = IntentionEditorRoute();
    expect(route, isA<PageRouteInfo<void>>());
    expect(router.current.name, IntentionEditorRoute.name);
    expect(find.byType(IntentionEditorPage), findsOneWidget);
    expect(find.text('Create intention'), findsWidgets);
    expect(find.text('Title'), findsOneWidget);
    expect(find.text('Description (optional)'), findsOneWidget);
    expect(find.text('Ready for action'), findsNothing);
    expect(find.byType(Switch), findsNothing);
  });

  testWidgets('форма проходит accessibility guidelines при масштабе 200%', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    tester.binding.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(
      tester.binding.platformDispatcher.clearTextScaleFactorTestValue,
    );
    final repository = ControlledCatalogRepository();
    await _openEditor(tester, repository);
    await tester.ensureVisible(
      find.byKey(const ValueKey('intention-editor-submit')),
    );
    await tester.pumpAndSettle();

    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    await expectLater(tester, meetsGuideline(textContrastGuideline));
    semantics.dispose();
  });

  testWidgets(
    'блокирует повторную отправку, сохраняя доступный уход с подтверждением',
    (tester) async {
      final repository = ControlledCatalogRepository();
      final router = await _openEditor(tester, repository);

      await tester.enterText(
        find.byKey(const ValueKey('intention-editor-title')),
        '  Быть здоровым  ',
      );
      await tester.enterText(
        find.byKey(const ValueKey('intention-editor-description')),
        '  Сохранить буквально\n',
      );
      await tester.tap(find.byKey(const ValueKey('intention-editor-submit')));
      await tester.pump();

      expect(repository.commands, hasLength(1));
      expect(
        repository.commands.single,
        isA<CreateIntention>()
            .having((command) => command.title, 'title', '  Быть здоровым  ')
            .having(
              (command) => command.description,
              'description',
              '  Сохранить буквально\n',
            ),
      );
      expect(find.text('Creating…'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('intention-editor-submit')),
            )
            .onPressed,
        isNull,
      );

      await _tapClose(tester);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(_closeDiscard));
      await tester.pumpAndSettle();

      expectIntentionGraphRootPage(router);
      expect(repository.commands, hasLength(1));
      repository.completeCommand(
        0,
        const ResultFailure(IntentionUnexpectedFailure()),
      );
      await tester.pump();
    },
  );

  testWidgets(
    'не даёт менять текст выполняющейся отправки и повторяет отправку с показанным текстом',
    (tester) async {
      final repository = ControlledCatalogRepository();
      await _openEditor(tester, repository);
      TextField field(String key) =>
          tester.widget<TextField>(find.byKey(ValueKey(key)));

      await tester.enterText(
        find.byKey(const ValueKey('intention-editor-title')),
        'Намерение',
      );
      await tester.enterText(
        find.byKey(const ValueKey('intention-editor-description')),
        'Описание',
      );
      await tester.tap(find.byKey(const ValueKey('intention-editor-submit')));
      await tester.pump();

      expect(field('intention-editor-title').readOnly, isTrue);
      expect(field('intention-editor-description').readOnly, isTrue);

      repository.completeCommand(
        0,
        const ResultFailure(IntentionUnavailableFailure()),
      );
      await tester.pumpAndSettle();

      expect(field('intention-editor-title').readOnly, isFalse);
      expect(field('intention-editor-description').readOnly, isFalse);
      expect(field('intention-editor-title').controller?.text, 'Намерение');
      await tester.tap(find.widgetWithText(FilledButton, 'Try again'));
      await tester.pump();

      expect(repository.commands, hasLength(2));
      expect(
        repository.commands.last,
        isA<CreateIntention>()
            .having((command) => command.title, 'название', 'Намерение')
            .having((command) => command.description, 'описание', 'Описание'),
      );
      repository.completeCommand(
        1,
        const ResultFailure(IntentionUnexpectedFailure()),
      );
      await tester.pumpAndSettle();
    },
  );

  testWidgets('сохраняет поля и локализует field-specific validation', (
    tester,
  ) async {
    final repository = ControlledCatalogRepository();
    await _openEditor(tester, repository);

    await tester.enterText(
      find.byKey(const ValueKey('intention-editor-description')),
      'Описание остаётся',
    );
    await tester.tap(find.byKey(const ValueKey('intention-editor-submit')));
    repository.completeCommand(
      0,
      const ResultFailure(
        IntentionTextInputValidationFailure(
          IntentionTextValidationFailure(
            field: IntentionTextField.title,
            reason: IntentionTextValidationReason.empty,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Enter a title.'), findsOneWidget);
    expect(
      tester
          .widget<TextField>(
            find.byKey(const ValueKey('intention-editor-description')),
          )
          .controller
          ?.text,
      'Описание остаётся',
    );
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('intention-editor-submit')),
          )
          .onPressed,
      isNull,
    );

    await tester.enterText(
      find.byKey(const ValueKey('intention-editor-title')),
      'Исправленное намерение',
    );
    await tester.pump();

    expect(find.text('Enter a title.'), findsNothing);
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('intention-editor-submit')),
          )
          .onPressed,
      isNotNull,
    );
  });

  testWidgets(
    'правка другого поля сохраняет ошибку описания, а исправление описания снимает её без отправки',
    (tester) async {
      final repository = ControlledCatalogRepository();
      await _openEditor(tester, repository);
      FilledButton submit() => tester.widget<FilledButton>(
        find.byKey(const ValueKey('intention-editor-submit')),
      );

      await tester.enterText(
        find.byKey(const ValueKey('intention-editor-title')),
        'Намерение',
      );
      await tester.enterText(
        find.byKey(const ValueKey('intention-editor-description')),
        '  Слишком длинное\n',
      );
      await tester.tap(find.byKey(const ValueKey('intention-editor-submit')));
      repository.completeCommand(
        0,
        const ResultFailure(
          IntentionTextInputValidationFailure(
            IntentionTextValidationFailure(
              field: IntentionTextField.description,
              reason: IntentionTextValidationReason.tooLong,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Use no more than 4096 characters.'), findsOneWidget);
      expect(submit().onPressed, isNull);

      await tester.enterText(
        find.byKey(const ValueKey('intention-editor-title')),
        'Другое намерение',
      );
      await tester.pump();

      expect(find.text('Use no more than 4096 characters.'), findsOneWidget);
      expect(submit().onPressed, isNull);

      await tester.enterText(
        find.byKey(const ValueKey('intention-editor-description')),
        'Короткое',
      );
      await tester.pump();

      expect(find.text('Use no more than 4096 characters.'), findsNothing);
      expect(submit().onPressed, isNotNull);
      expect(repository.commands, hasLength(1));
    },
  );

  testWidgets(
    'правка текста не снимает конфликт и отказ отсутствующих тегов и не открывает повтор',
    (tester) async {
      final cases = <(IntentionFailure, String)>[
        (
          const IntentionConflictFailure(),
          'The intention couldn’t be created because of a conflict.',
        ),
        (
          IntentionCreationTagsMissingFailure([_tagId(1)]),
          'Check the entered data.',
        ),
      ];

      for (final (failure, message) in cases) {
        final repository = ControlledCatalogRepository();
        await _openEditor(tester, repository);
        await tester.enterText(
          find.byKey(const ValueKey('intention-editor-title')),
          'Намерение',
        );
        await tester.tap(find.byKey(const ValueKey('intention-editor-submit')));
        repository.completeCommand(0, ResultFailure(failure));
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byKey(const ValueKey('intention-editor-title')),
          'Исправленное намерение',
        );
        await tester.enterText(
          find.byKey(const ValueKey('intention-editor-description')),
          'Описание',
        );
        await tester.pump();

        expect(find.text(message), findsOneWidget);
        expect(find.widgetWithText(FilledButton, 'Try again'), findsNothing);
        expect(
          tester
              .widget<FilledButton>(
                find.byKey(const ValueKey('intention-editor-submit')),
              )
              .onPressed,
          isNull,
        );
        expect(repository.commands, hasLength(1));
        await tester.pumpWidget(const SizedBox.shrink());
      }
    },
  );

  testWidgets(
    'не подтверждает field failure по кадру видимого поля до появления сообщения',
    (tester) async {
      final repository = ControlledCatalogRepository();
      await _openEditor(tester, repository);
      await tester.tap(find.byKey(const ValueKey('intention-editor-submit')));
      repository.completeCommand(
        0,
        const ResultFailure(
          IntentionTextInputValidationFailure(
            IntentionTextValidationFailure(
              field: IntentionTextField.title,
              reason: IntentionTextValidationReason.empty,
            ),
          ),
        ),
      );
      await tester.idle();
      await tester.pump();

      final renderer = tester.widget<OperationFailurePresentation>(
        find.byType(OperationFailurePresentation),
      );
      final claim = renderer.claim!;
      final coordinator = ProviderScope.containerOf(
        tester.element(find.byType(IntentionEditorPage)),
      ).read(graphCommandCoordinatorProvider.notifier);
      expect(coordinator.claimInitiatorFailure(claim.token), same(claim));

      await tester.pumpAndSettle();

      expect(find.text('Enter a title.'), findsOneWidget);
      expect(coordinator.claimInitiatorFailure(claim.token), isNull);
    },
  );

  testWidgets('показывает безопасные failures и retry только для unavailable', (
    tester,
  ) async {
    final cases = <(IntentionFailure, String, bool)>[
      (
        const IntentionUnavailableFailure(),
        'The intention couldn’t be created. Try again.',
        true,
      ),
      (
        const IntentionConflictFailure(),
        'The intention couldn’t be created because of a conflict.',
        false,
      ),
      (
        const IntentionCorruptionFailure(),
        'Stored data is damaged. The intention wasn’t created.',
        false,
      ),
      (
        const IntentionUnexpectedFailure(),
        'The intention couldn’t be created because of an unexpected error.',
        false,
      ),
    ];

    for (final (failure, message, canRetry) in cases) {
      final repository = ControlledCatalogRepository();
      await _openEditor(tester, repository);
      await tester.enterText(
        find.byKey(const ValueKey('intention-editor-title')),
        'Намерение',
      );
      await tester.tap(find.byKey(const ValueKey('intention-editor-submit')));
      repository.completeCommand(0, ResultFailure(failure));
      await tester.pumpAndSettle();

      expect(find.text(message), findsOneWidget);
      expect(
        find.widgetWithText(FilledButton, 'Try again'),
        canRetry ? findsOneWidget : findsNothing,
      );
      expect(
        tester
            .widget<TextField>(
              find.byKey(const ValueKey('intention-editor-title')),
            )
            .controller
            ?.text,
        'Намерение',
      );
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets(
    'создаёт намерение с минимальными данными и возвращается после success',
    (tester) async {
      final repository = ControlledCatalogRepository();
      final router = await _openEditor(tester, repository);
      await tester.enterText(
        find.byKey(const ValueKey('intention-editor-title')),
        'Новое намерение',
      );
      await tester.tap(find.byKey(const ValueKey('intention-editor-submit')));
      await tester.pump();

      expect(
        repository.commands.single,
        isA<CreateIntention>()
            .having(
              (command) => command.title,
              'минимальное название',
              'Новое намерение',
            )
            .having(
              (command) => command.description,
              'отсутствующее необязательное описание',
              isNull,
            ),
      );
      expect(router.current.name, IntentionEditorRoute.name);
      repository.completeCommand(0, _savedResult(title: 'Новое намерение'));
      await tester.pump();
      await tester.pump();
      if (repository.queries.length > 1) {
        repository.complete(
          1,
          ResultSuccess(
            IntentionCatalogFirstPage(
              items: const [],
              totalCount: 0,
              nextCursor: null,
              revision: const TestCatalogRevision(1),
            ),
          ),
        );
      }
      await tester.pumpAndSettle();

      expectIntentionGraphRootPage(router);
      expect(find.textContaining('Intention created.'), findsOneWidget);
    },
  );

  testWidgets(
    'не повторяет в каталоге failure, представленный открытой формой',
    (tester) async {
      final repository = ControlledCatalogRepository();
      await _openEditor(tester, repository);
      await tester.enterText(
        find.byKey(const ValueKey('intention-editor-title')),
        'Намерение',
      );
      await tester.tap(find.byKey(const ValueKey('intention-editor-submit')));
      repository.completeCommand(
        0,
        const ResultFailure(IntentionUnavailableFailure()),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('The intention couldn’t be created. Try again.'),
        findsOneWidget,
      );
      await _tapClose(tester);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(_closeDiscard));
      await tester.pumpAndSettle();

      expect(
        find.text('The intention couldn’t be created. Try again.'),
        findsNothing,
      );
    },
  );

  testWidgets(
    'передаёт поздний failure ушедшей формы оболочке ровно один раз',
    (tester) async {
      final repository = ControlledCatalogRepository();
      await _openEditor(tester, repository);
      await tester.enterText(
        find.byKey(const ValueKey('intention-editor-title')),
        'Намерение',
      );
      await tester.tap(find.byKey(const ValueKey('intention-editor-submit')));
      await _tapClose(tester);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(_closeDiscard));
      await tester.pumpAndSettle();

      repository.completeCommand(
        0,
        const ResultFailure(IntentionUnexpectedFailure()),
      );
      await tester.pumpAndSettle();

      expect(
        find.text(
          'Create — “new intention”: The intention couldn’t be created because of an unexpected error.',
        ),
        findsOneWidget,
      );
      await tester.pump(const Duration(seconds: 1));
      expect(
        find.text(
          'Create — “new intention”: The intention couldn’t be created because of an unexpected error.',
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets('передаёт поздний success ушедшей формы оболочке', (
    tester,
  ) async {
    final repository = ControlledCatalogRepository();
    await _openEditor(tester, repository);
    await tester.enterText(
      find.byKey(const ValueKey('intention-editor-title')),
      'Позднее намерение',
    );
    await tester.tap(find.byKey(const ValueKey('intention-editor-submit')));
    await _tapClose(tester);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(_closeDiscard));
    await tester.pumpAndSettle();

    repository.completeCommand(0, _savedResult(title: 'Позднее намерение'));
    await tester.pump();
    await tester.pump();
    if (repository.queries.length > 1) {
      repository.complete(
        1,
        ResultSuccess(
          IntentionCatalogFirstPage(
            items: const [],
            totalCount: 0,
            nextCursor: null,
            revision: const TestCatalogRevision(1),
          ),
        ),
      );
    }
    await tester.pumpAndSettle();

    expect(
      find.text('Create — “Позднее намерение”: Intention created.'),
      findsOneWidget,
    );
  });

  testWidgets('успешный retry не оставляет сообщение прежнего failure', (
    tester,
  ) async {
    final repository = ControlledCatalogRepository();
    await _openEditor(tester, repository);
    await tester.enterText(
      find.byKey(const ValueKey('intention-editor-title')),
      'Намерение',
    );
    await tester.tap(find.byKey(const ValueKey('intention-editor-submit')));
    repository.completeCommand(
      0,
      const ResultFailure(IntentionUnavailableFailure()),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Try again'));
    repository.completeCommand(1, _savedResult(title: 'Намерение'));
    await tester.pump();
    await tester.pump();
    if (repository.queries.length > 1) {
      repository.complete(
        1,
        ResultSuccess(
          IntentionCatalogFirstPage(
            items: const [],
            totalCount: 0,
            nextCursor: null,
            revision: const TestCatalogRevision(1),
          ),
        ),
      );
    }
    await tester.pumpAndSettle();

    expect(find.textContaining('Intention created.'), findsOneWidget);
    expect(
      find.text('The intention couldn’t be created. Try again.'),
      findsNothing,
    );
  });

  testWidgets('локализует форму и validation на русском', (tester) async {
    final repository = ControlledCatalogRepository();
    await _openEditor(tester, repository, locale: const Locale('ru'));

    expect(find.text('Создать намерение'), findsWidgets);
    expect(find.text('Название'), findsOneWidget);
    expect(find.text('Описание (необязательно)'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('intention-editor-submit')));
    repository.completeCommand(
      0,
      const ResultFailure(
        IntentionTextInputValidationFailure(
          IntentionTextValidationFailure(
            field: IntentionTextField.title,
            reason: IntentionTextValidationReason.empty,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Введите название.'), findsOneWidget);
  });

  testWidgets(
    'success закрывает форму при занятой поверхности и предъявляется один раз после текущего сообщения',
    (tester) async {
      const busyMessage =
          'Delete — “Другое намерение”: The intention couldn’t be deleted. Try again.';
      final repository = ControlledCatalogRepository();
      final router = await _openEditor(tester, repository);
      final coordinator = ProviderScope.containerOf(
        tester.element(find.byType(IntentionEditorPage)),
      ).read(graphCommandCoordinatorProvider.notifier);
      final other = testIntention(index: 40, title: 'Другое намерение');
      final busy = coordinator.acceptExisting(
        DeleteIntention(other.id),
        presentationTitle: other.title,
      ) as IntentionCommandAccepted;
      coordinator.releaseInitiatorPresentation(busy.token);
      repository.completeCommand(
        0,
        const ResultFailure(IntentionUnavailableFailure()),
      );
      await tester.pumpAndSettle();
      expect(find.text(busyMessage), findsOneWidget);

      await tester.enterText(
        find.byKey(const ValueKey('intention-editor-title')),
        'Новое намерение',
      );
      await tester.tap(find.byKey(const ValueKey('intention-editor-submit')));
      repository.completeCommand(1, _savedResult(title: 'Новое намерение'));
      await tester.pump();
      await tester.pump();
      if (repository.queries.length > 1) {
        repository.complete(
          1,
          ResultSuccess(
            IntentionCatalogFirstPage(
              items: const [],
              totalCount: 0,
              nextCursor: null,
              revision: const TestCatalogRevision(1),
            ),
          ),
        );
      }
      await tester.pumpAndSettle();

      expectIntentionGraphRootPage(router);
      expect(find.text(busyMessage), findsOneWidget);
      expect(find.textContaining('Intention created.'), findsNothing);

      await _closeOperationMessage(tester);
      expect(find.text(busyMessage), findsNothing);
      expect(find.textContaining('Intention created.'), findsOneWidget);

      await _closeOperationMessage(tester);
      await tester.pumpAndSettle();
      expect(find.textContaining('Intention created.'), findsNothing);
    },
  );

  testWidgets(
    'ошибка формы без фокуса не предъявлена, а уход передаёт её оболочке один раз',
    (tester) async {
      const failure = 'The intention couldn’t be created. Try again.';
      final repository = ControlledCatalogRepository();
      final router = await _openEditor(tester, repository);
      await tester.enterText(
        find.byKey(const ValueKey('intention-editor-title')),
        'Намерение',
      );
      await tester.tap(find.byKey(const ValueKey('intention-editor-submit')));
      await tester.pump();

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      repository.completeCommand(
        0,
        const ResultFailure(IntentionUnavailableFailure()),
      );
      await tester.pumpAndSettle();
      expect(find.text(failure), findsOneWidget);

      await _tapClose(tester);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(_closeDiscard));
      await tester.pumpAndSettle();
      expectIntentionGraphRootPage(router);
      expect(find.textContaining(failure), findsNothing);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.textContaining(failure), findsOneWidget);

      await _closeOperationMessage(tester);
      await tester.pumpAndSettle();
      expect(find.textContaining(failure), findsNothing);
    },
  );

  group('закрытие формы создания', () {
    testWidgets(
      'неизменённая и возвращённая к исходным значениям форма закрывается «назад» и кнопкой закрытия без подтверждения',
      (tester) async {
        final repository = ControlledCatalogRepository();
        final router = await _openEditor(tester, repository);

        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();

        expect(find.byKey(_closeConfirmation), findsNothing);
        expectIntentionGraphRootPage(router);

        await tester.tap(
          find.byKey(const ValueKey('catalog-create-intention')),
        );
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const ValueKey('intention-editor-title')),
          'Намерение',
        );
        await tester.enterText(
          find.byKey(const ValueKey('intention-editor-title')),
          '',
        );
        await tester.pump();

        await _tapClose(tester);
        await tester.pumpAndSettle();

        expect(find.byKey(_closeConfirmation), findsNothing);
        expectIntentionGraphRootPage(router);
        expect(repository.commands, isEmpty);
      },
    );

    final changes =
        <
          String,
          Future<void> Function(WidgetTester tester, _EditorSessions sessions)
        >{
          'название из одних пробелов': (tester, _) => tester.enterText(
            find.byKey(const ValueKey('intention-editor-title')),
            '   ',
          ),
          'описание': (tester, _) => tester.enterText(
            find.byKey(const ValueKey('intention-editor-description')),
            '  Описание\n',
          ),
          'набор тегов': (tester, sessions) async =>
              sessions.notifier(tester).draftTagSet.add(_tag(1, 'Дом')),
          'избранное': (tester, sessions) async =>
              sessions.notifier(tester).markFavorite(),
          'готовность': (tester, sessions) async =>
              sessions.notifier(tester).confirmReadiness(),
        };
    for (final MapEntry(key: field, value: change) in changes.entries) {
      testWidgets(
        'изменённое поле «$field» требует подтверждения: продолжение сохраняет черновик, а сброс закрывает форму',
        (tester) async {
          final sessions = _EditorSessions();
          final repository = ControlledCatalogRepository();
          final router = await _openEditor(
            tester,
            repository,
            observers: [sessions],
          );
          await change(tester, sessions);
          await tester.pump();
          final draft = sessions.state(tester).draft;
          final title = _fieldText(tester, 'intention-editor-title');
          final description = _fieldText(
            tester,
            'intention-editor-description',
          );
          expect(draft.isChanged, isTrue);

          await _tapClose(tester);
          await tester.pumpAndSettle();

          expect(find.byKey(_closeConfirmation), findsOneWidget);
          expect(find.text('Discard the draft?'), findsOneWidget);
          expect(
            find.text(
              'The new intention’s entered data hasn’t been saved and will be lost.',
            ),
            findsOneWidget,
          );
          expect(router.current.name, IntentionEditorRoute.name);

          await tester.tap(find.byKey(_closeContinue));
          await tester.pumpAndSettle();

          expect(find.byKey(_closeConfirmation), findsNothing);
          expect(router.current.name, IntentionEditorRoute.name);
          expect(sessions.state(tester).draft, same(draft));
          expect(_fieldText(tester, 'intention-editor-title'), title);
          expect(
            _fieldText(tester, 'intention-editor-description'),
            description,
          );

          await _tapClose(tester);
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(_closeDiscard));
          await tester.pumpAndSettle();

          expect(find.byKey(_closeConfirmation), findsNothing);
          expectIntentionGraphRootPage(router);
          expect(repository.commands, isEmpty);

          await tester.tap(
            find.byKey(const ValueKey('catalog-create-intention')),
          );
          await tester.pumpAndSettle();

          expect(router.current.name, IntentionEditorRoute.name);
          expect(sessions.state(tester).draft.isChanged, isFalse);
          expect(_fieldText(tester, 'intention-editor-title'), isEmpty);
          expect(_fieldText(tester, 'intention-editor-description'), isEmpty);
        },
      );
    }

    testWidgets(
      'системное «назад», программный уход и закрытие диалога без выбора сохраняют черновик и не создают второе подтверждение',
      (tester) async {
        final sessions = _EditorSessions();
        final repository = ControlledCatalogRepository();
        final router = await _openEditor(
          tester,
          repository,
          observers: [sessions],
        );
        await tester.enterText(
          find.byKey(const ValueKey('intention-editor-title')),
          '  Намерение  ',
        );
        await tester.pump();

        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(find.byKey(_closeConfirmation), findsOneWidget);
        // «Назад» обращается к сессии панели, а не к оболочке под ней.
        expect(_selectedDestination(tester), AppDestination.intentionGraph);

        // Нажатие на затемнение вне диалога закрывает только его.
        await tester.tapAt(const Offset(8, 8));
        await tester.pumpAndSettle();
        expect(find.byKey(_closeConfirmation), findsNothing);
        expect(router.current.name, IntentionEditorRoute.name);
        expect(_fieldText(tester, 'intention-editor-title'), '  Намерение  ');

        unawaited(router.maybePop());
        unawaited(router.maybePop());
        await tester.pumpAndSettle();
        expect(find.byKey(_closeConfirmation), findsOneWidget);

        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(find.byKey(_closeConfirmation), findsNothing);
        expect(router.current.name, IntentionEditorRoute.name);
        expect(_selectedDestination(tester), AppDestination.intentionGraph);
        expect(_fieldText(tester, 'intention-editor-title'), '  Намерение  ');
        expect(sessions.state(tester).draft.title, '  Намерение  ');
        expect(repository.commands, isEmpty);
      },
    );

    testWidgets(
      'во время принятой отправки объясняет продолжение сохранения, а уход не отменяет и не повторяет её',
      (tester) async {
        final repository = ControlledCatalogRepository();
        final router = await _openEditor(tester, repository);
        await tester.enterText(
          find.byKey(const ValueKey('intention-editor-title')),
          'Позднее намерение',
        );
        await tester.tap(find.byKey(const ValueKey('intention-editor-submit')));
        await tester.pump();

        await _tapClose(tester);
        await tester.pumpAndSettle();

        expect(find.text('Close the form?'), findsOneWidget);
        expect(
          find.text(
            'Saving is already in progress and will continue after the form '
            'closes. If saving fails, the entered data won’t be restored.',
          ),
          findsOneWidget,
        );
        await tester.tap(find.byKey(_closeContinue));
        await tester.pumpAndSettle();
        expect(router.current.name, IntentionEditorRoute.name);
        expect(find.text('Creating…'), findsOneWidget);

        await _tapClose(tester);
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(_closeDiscard));
        await tester.pumpAndSettle();
        expectIntentionGraphRootPage(router);
        expect(repository.commands, hasLength(1));

        repository.completeCommand(0, _savedResult(title: 'Позднее намерение'));
        await tester.pump();
        await tester.pump();
        _completeCatalogRefresh(repository);
        await tester.pumpAndSettle();

        expect(
          find.text('Create — “Позднее намерение”: Intention created.'),
          findsOneWidget,
        );
        expect(repository.commands, hasLength(1));
      },
    );

    testWidgets(
      'успех при открытом подтверждении закрывает свою форму и диалог, а его поздний ответ не закрывает новое открытие',
      (tester) async {
        final repository = ControlledCatalogRepository();
        final router = await _openEditor(tester, repository);
        await tester.enterText(
          find.byKey(const ValueKey('intention-editor-title')),
          'Новое намерение',
        );
        await tester.tap(find.byKey(const ValueKey('intention-editor-submit')));
        await tester.pump();
        await _tapClose(tester);
        await tester.pumpAndSettle();
        expect(find.byKey(_closeConfirmation), findsOneWidget);

        repository.completeCommand(0, _savedResult(title: 'Новое намерение'));
        await tester.pump();
        await tester.pump();
        _completeCatalogRefresh(repository);
        await tester.pumpAndSettle();

        expect(find.byKey(_closeConfirmation), findsNothing);
        expectIntentionGraphRootPage(router);
        expect(
          find.text('Create — “Новое намерение”: Intention created.'),
          findsOneWidget,
        );

        await tester.tap(
          find.byKey(const ValueKey('catalog-create-intention')),
        );
        await tester.pumpAndSettle();
        await tester.pump(const Duration(seconds: 1));

        expect(router.current.name, IntentionEditorRoute.name);
        expect(find.byKey(_closeConfirmation), findsNothing);
        expect(_fieldText(tester, 'intention-editor-title'), isEmpty);
      },
    );

    testWidgets(
      'отказ при открытом подтверждении снимает устаревший диалог и сохраняет форму с черновиком',
      (tester) async {
        final repository = ControlledCatalogRepository();
        final router = await _openEditor(tester, repository);
        await tester.enterText(
          find.byKey(const ValueKey('intention-editor-title')),
          'Намерение',
        );
        await tester.tap(find.byKey(const ValueKey('intention-editor-submit')));
        await tester.pump();
        await _tapClose(tester);
        await tester.pumpAndSettle();
        expect(find.text('Close the form?'), findsOneWidget);

        repository.completeCommand(
          0,
          const ResultFailure(IntentionUnavailableFailure()),
        );
        await tester.pumpAndSettle();

        expect(find.byKey(_closeConfirmation), findsNothing);
        expect(router.current.name, IntentionEditorRoute.name);
        expect(
          find.text('The intention couldn’t be created. Try again.'),
          findsOneWidget,
        );
        expect(_fieldText(tester, 'intention-editor-title'), 'Намерение');

        // Новый запрос объясняет текущее состояние: отправки больше нет.
        await _tapClose(tester);
        await tester.pumpAndSettle();
        expect(find.text('Discard the draft?'), findsOneWidget);
        await tester.tap(find.byKey(_closeContinue));
        await tester.pumpAndSettle();
        expect(router.current.name, IntentionEditorRoute.name);
        expect(find.widgetWithText(FilledButton, 'Try again'), findsOneWidget);
      },
    );

    testWidgets(
      'запоздалый ответ подтверждения после смены состояния отправки не закрывает форму',
      (tester) async {
        final repository = ControlledCatalogRepository();
        final router = await _openEditor(tester, repository);
        await tester.enterText(
          find.byKey(const ValueKey('intention-editor-title')),
          'Намерение',
        );
        await tester.tap(find.byKey(const ValueKey('intention-editor-submit')));
        await tester.pump();
        await _tapClose(tester);
        await tester.pumpAndSettle();

        // Человек уже нажимает «Закрыть», когда отправка завершается
        // отказом: подтверждение больше не описывает состояние формы.
        final gesture = await tester.startGesture(
          tester.getCenter(find.byKey(_closeDiscard)),
        );
        repository.completeCommand(
          0,
          const ResultFailure(IntentionUnavailableFailure()),
        );
        await tester.pump();
        await gesture.up();
        await tester.pumpAndSettle();

        expect(find.byKey(_closeConfirmation), findsNothing);
        expect(router.current.name, IntentionEditorRoute.name);
        expect(_fieldText(tester, 'intention-editor-title'), 'Намерение');
        expect(
          find.text('The intention couldn’t be created. Try again.'),
          findsOneWidget,
        );
        expect(repository.commands, hasLength(1));
      },
    );

    testWidgets(
      'локализует подтверждение закрытия на русском и сохраняет доступность его действий',
      (tester) async {
        final semantics = tester.ensureSemantics();
        final repository = ControlledCatalogRepository();
        await _openEditor(tester, repository, locale: const Locale('ru'));
        await tester.enterText(
          find.byKey(const ValueKey('intention-editor-title')),
          'Намерение',
        );

        await _tapClose(tester);
        await tester.pumpAndSettle();

        expect(find.text('Сбросить черновик?'), findsOneWidget);
        expect(
          find.text(
            'Введённые данные нового намерения не сохранены и будут потеряны.',
          ),
          findsOneWidget,
        );
        expect(find.text('Продолжить ввод'), findsOneWidget);
        expect(find.text('Сбросить'), findsOneWidget);
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        await expectLater(tester, meetsGuideline(textContrastGuideline));

        await tester.tap(find.byKey(_closeContinue));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('intention-editor-submit')));
        await tester.pump();
        await _tapClose(tester);
        await tester.pumpAndSettle();

        expect(find.text('Закрыть форму?'), findsOneWidget);
        expect(
          find.text(
            'Сохранение уже выполняется и продолжится после закрытия формы. '
            'Если сохранить не удастся, введённые данные не восстановятся.',
          ),
          findsOneWidget,
        );
        expect(find.text('Остаться'), findsOneWidget);
        expect(find.text('Закрыть'), findsOneWidget);

        await tester.tap(find.byKey(_closeContinue));
        await tester.pumpAndSettle();
        repository.completeCommand(
          0,
          const ResultFailure(IntentionUnexpectedFailure()),
        );
        await tester.pumpAndSettle();
        semantics.dispose();
      },
    );
  });

  group('компактная модальная панель создания', () {
    testWidgets(
      'кнопка «+» открывает над сохранённым каталогом компактную панель с фокусом в пустом названии',
      (tester) async {
        _usePhone(tester, _phoneInsets);
        final repository = ControlledCatalogRepository();
        final router = await _openEditor(tester, repository);

        // Маршрут создания прозрачен: каталог остаётся на экране под панелью.
        expect(router.current.name, IntentionEditorRoute.name);
        expect(
          ModalRoute.of(tester.element(find.byType(IntentionEditorPage)))!
              .opaque,
          isFalse,
        );
        expect(find.byType(IntentionCatalogPage), findsOneWidget);

        final sheet = tester.getRect(find.byKey(_sheet));
        expect(sheet.bottom, _phone.height);
        expect(sheet.left, 0);
        expect(sheet.right, _phone.width);
        // Над компактной панелью видны шапка и параметры каталога.
        expect(tester.getRect(_catalogBar).top, 0);
        expect(
          sheet.top,
          greaterThanOrEqualTo(tester.getRect(_catalogFilter).bottom),
        );

        // Фокус — в пустом названии; пустое описание начинается одной
        // строкой, без резерва пустой многострочной области.
        expect(_editable(tester, _title).focusNode.hasFocus, isTrue);
        expect(_fieldText(tester, 'intention-editor-title'), isEmpty);
        expect(_fieldText(tester, 'intention-editor-description'), isEmpty);
        expect(
          tester.getSize(find.byKey(_description)).height,
          tester.getSize(find.byKey(_title)).height,
        );

        // Отправка — внутри панели над нижним безопасным отступом.
        final submit = tester.getRect(find.byKey(_submit));
        expect(sheet.contains(submit.topLeft), isTrue);
        expect(
          submit.bottom,
          lessThanOrEqualTo(_phone.height - _phoneInsets.safeBottom),
        );
        expect(find.byKey(_submit).hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'рост описания увеличивает панель только до предела под шапкой каталога, затем поля прокручиваются, а отправка остаётся закреплённой',
      (tester) async {
        _usePhone(tester, _phoneInsets);
        final repository = ControlledCatalogRepository();
        await _openEditor(tester, repository);
        final compact = tester.getRect(find.byKey(_sheet));

        await tester.enterText(
          find.byKey(_description),
          'Первая строка\nВторая строка',
        );
        await tester.pumpAndSettle();
        final twoLines = tester.getRect(find.byKey(_sheet));
        expect(twoLines.bottom, compact.bottom);
        expect(twoLines.height, greaterThan(compact.height));

        await tester.enterText(find.byKey(_description), _lines(80));
        await tester.pumpAndSettle();
        final bounded = tester.getRect(find.byKey(_sheet));
        expect(bounded.bottom, compact.bottom);
        expect(bounded.top, lessThan(twoLines.top));
        expect(
          bounded.top,
          greaterThanOrEqualTo(tester.getRect(_catalogBar).bottom),
        );
        // Описание выше панели: оно прокручивается внутри её полей.
        expect(
          tester.getSize(find.byKey(_description)).height,
          greaterThan(bounded.height),
        );
        final submit = find.byKey(_submit);
        expect(submit.hitTestable(), findsOneWidget);
        expect(tester.getRect(submit).top, greaterThan(bounded.top));
        expect(
          tester.getRect(submit).bottom,
          lessThanOrEqualTo(bounded.bottom - _phoneInsets.safeBottom),
        );

        await tester.enterText(find.byKey(_description), _lines(160));
        await tester.pumpAndSettle();
        expect(tester.getRect(find.byKey(_sheet)), bounded);
        expect(submit.hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'клавиатура поднимает компактную панель и ограничивает её высоту, оставляя шапку каталога над ней и отправку доступной',
      (tester) async {
        _usePhone(tester, _phoneInsets);
        final repository = ControlledCatalogRepository();
        await _openEditor(tester, repository);
        final withoutKeyboard = tester.getRect(find.byKey(_sheet));

        _usePhone(tester, _keyboardInsets);
        await tester.pumpAndSettle();
        final withKeyboard = tester.getRect(find.byKey(_sheet));
        expect(withKeyboard.bottom, _phone.height - _keyboardInsets.keyboard);
        // Клавиатура закрыла нижний безопасный отступ, а высота по-прежнему
        // задаётся содержимым.
        expect(
          withKeyboard.height,
          withoutKeyboard.height - _phoneInsets.safeBottom,
        );
        final submit = find.byKey(_submit);
        expect(submit.hitTestable(), findsOneWidget);
        expect(
          tester.getRect(submit).bottom,
          lessThanOrEqualTo(withKeyboard.bottom),
        );

        await tester.enterText(find.byKey(_description), _lines(40));
        await tester.pumpAndSettle();
        final bounded = tester.getRect(find.byKey(_sheet));
        expect(bounded.bottom, withKeyboard.bottom);
        expect(bounded.top, lessThan(withKeyboard.top));
        expect(
          bounded.top,
          greaterThanOrEqualTo(tester.getRect(_catalogBar).bottom),
        );
        expect(submit.hitTestable(), findsOneWidget);
        expect(
          tester.getRect(submit).bottom,
          lessThanOrEqualTo(bounded.bottom),
        );
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'каталог и основная навигация под панелью исключены из нажатий, фокуса и семантики, а выбранный пункт сохраняется',
      (tester) async {
        final semantics = tester.ensureSemantics();
        final repository = ControlledCatalogRepository();
        await _openEditor(tester, repository);

        final destinations = find.byType(NavigationDestination);
        expect(_catalogFilter, findsOneWidget);
        expect(_catalogFilter.hitTestable(), findsNothing);
        expect(
          find.byKey(const ValueKey('catalog-create-intention')).hitTestable(),
          findsNothing,
        );
        expect(destinations, findsNWidgets(3));
        expect(destinations.hitTestable(), findsNothing);
        expect(_selectedDestination(tester), AppDestination.intentionGraph);
        expect(
          find.semantics.byPredicate(
            (node) => node.role == SemanticsRole.tab,
            describeMatch: (_) => 'пункты панели навигации',
          ),
          findsNothing,
        );
        expect(find.semantics.byLabel('Filter by title'), findsNothing);
        expect(find.semantics.byLabel('Title'), findsOneWidget);

        // Клавиатурный обход не переводит фокус в каталог или панель.
        for (var step = 0; step < 10; step++) {
          await tester.sendKeyEvent(LogicalKeyboardKey.tab);
          await tester.pump();
          expect(
            FocusManager.instance.primaryFocus?.context
                ?.findAncestorWidgetOfExactType<AppShellPage>(),
            isNull,
            reason: 'шаг обхода $step',
          );
        }
        expect(_selectedDestination(tester), AppDestination.intentionGraph);
        semantics.dispose();
      },
    );

    testWidgets(
      'нажатие вне неизменённой панели сразу закрывает её, а вне изменённой — запрашивает подтверждение без смены пункта',
      (tester) async {
        final sessions = _EditorSessions();
        final repository = ControlledCatalogRepository();
        final router = await _openEditor(
          tester,
          repository,
          observers: [sessions],
        );
        final firstSession = sessions.latest;

        await tester.tapAt(_outsideSheet);
        await tester.pumpAndSettle();
        expect(find.byKey(_closeConfirmation), findsNothing);
        expectIntentionGraphRootPage(router);

        await tester.tap(
          find.byKey(const ValueKey('catalog-create-intention')),
        );
        await tester.pumpAndSettle();
        // Новое открытие — новая сессия с начальным черновиком.
        expect(sessions.latest, isNot(firstSession));
        expect(sessions.state(tester).draft.isChanged, isFalse);
        await tester.enterText(find.byKey(_title), 'Намерение');
        await tester.pump();

        await tester.tapAt(_outsideSheet);
        await tester.pumpAndSettle();
        expect(find.byKey(_closeConfirmation), findsOneWidget);
        expect(router.current.name, IntentionEditorRoute.name);
        expect(_selectedDestination(tester), AppDestination.intentionGraph);

        await tester.tap(find.byKey(_closeContinue));
        await tester.pumpAndSettle();
        expect(router.current.name, IntentionEditorRoute.name);
        expect(_fieldText(tester, 'intention-editor-title'), 'Намерение');

        await tester.tapAt(_outsideSheet);
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(_closeDiscard));
        await tester.pumpAndSettle();
        expectIntentionGraphRootPage(router);
        expect(_selectedDestination(tester), AppDestination.intentionGraph);
        expect(repository.commands, isEmpty);
      },
    );

    testWidgets(
      'панель называет себя заголовком и даёт локализованное закрытие кнопкой и фоном без жеста',
      (tester) async {
        final semantics = tester.ensureSemantics();
        for (final (locale, heading, close) in [
          (const Locale('en'), 'Create intention', 'Close the form'),
          (const Locale('ru'), 'Создать намерение', 'Закрыть форму'),
        ]) {
          final repository = ControlledCatalogRepository();
          final router = await _openEditor(tester, repository, locale: locale);

          expect(
            tester.getSemantics(find.byKey(_heading)),
            isSemantics(label: heading, isHeader: true, namesRoute: true),
          );
          expect(
            tester.getSemantics(find.byKey(_closeButton)),
            isSemantics(tooltip: close, isButton: true, hasTapAction: true),
          );
          final barrier = find.semantics.byLabel(close);
          expect(barrier, findsOneWidget);

          // Экранный диктор закрывает неизменённую панель действием фона.
          tester.semantics.dismiss(barrier);
          await tester.pumpAndSettle();
          expectIntentionGraphRootPage(router);
          await tester.pumpWidget(const SizedBox.shrink());
        }
        semantics.dispose();
      },
    );
  });
}

const _sheet = ValueKey('intention-creation-sheet');
const _heading = ValueKey('intention-editor-heading');
const _closeButton = ValueKey('intention-editor-close');
const _title = ValueKey('intention-editor-title');
const _description = ValueKey('intention-editor-description');
const _submit = ValueKey('intention-editor-submit');

final _catalogBar = find.descendant(
  of: find.byType(IntentionCatalogPage),
  matching: find.byType(AppBar),
);
final _catalogFilter = find.byKey(const ValueKey('catalog-filter-field'));

/// Точка над панелью, где под модальным фоном лежит шапка каталога.
const _outsideSheet = Offset(400, 8);

/// Экран телефона в портретной ориентации.
const _phone = Size(400, 800);

/// Системные отступы экрана и высота экранной клавиатуры.
typedef _Insets = ({double safeTop, double safeBottom, double keyboard});

const _Insets _phoneInsets = (safeTop: 47, safeBottom: 34, keyboard: 0);
const _Insets _keyboardInsets = (safeTop: 47, safeBottom: 34, keyboard: 300);

/// Ставит экран телефона с отступами [insets]: открытая клавиатура закрывает
/// нижний безопасный отступ, как на устройстве.
void _usePhone(WidgetTester tester, _Insets insets) {
  tester.view.physicalSize = _phone;
  tester.view.devicePixelRatio = 1;
  tester.view.padding = FakeViewPadding(
    top: insets.safeTop,
    bottom: math.max(0, insets.safeBottom - insets.keyboard),
  );
  tester.view.viewPadding = FakeViewPadding(
    top: insets.safeTop,
    bottom: insets.safeBottom,
  );
  tester.view.viewInsets = FakeViewPadding(bottom: insets.keyboard);
  addTearDown(tester.view.reset);
}

String _lines(int count) =>
    [for (var line = 1; line <= count; line++) 'Строка $line'].join('\n');

EditableText _editable(WidgetTester tester, Key field) =>
    tester.widget<EditableText>(
      find.descendant(
        of: find.byKey(field),
        matching: find.byType(EditableText),
      ),
    );

AppDestination _selectedDestination(WidgetTester tester) => tester
    .widget<AppNavigationBar>(
      find.byType(AppNavigationBar, skipOffstage: false),
    )
    .selected;

Future<void> _tapClose(WidgetTester tester) =>
    tester.tap(find.byKey(_closeButton));

const _closeConfirmation = ValueKey('intention-editor-close-confirmation');
const _closeContinue = ValueKey('intention-editor-close-continue');
const _closeDiscard = ValueKey('intention-editor-close-discard');

/// Последняя построенная сессия формы создания. Набор тегов и отметки ещё
/// не имеют элементов формы, поэтому проверки закрытия меняют их через
/// сессию; новое открытие формы получает новую сессию.
final class _EditorSessions extends ProviderObserver {
  IntentionEditorViewModelProvider? _latest;

  IntentionEditorViewModelProvider? get latest => _latest;

  @override
  void didAddProvider(ProviderObserverContext context, Object? value) {
    if (context.provider case final IntentionEditorViewModelProvider provider) {
      _latest = provider;
    }
  }

  IntentionEditorViewModel notifier(WidgetTester tester) =>
      _container(tester).read(_latest!.notifier);

  IntentionEditorState state(WidgetTester tester) =>
      _container(tester).read(_latest!);

  ProviderContainer _container(WidgetTester tester) =>
      ProviderScope.containerOf(
        tester.element(find.byType(IntentionEditorPage)),
      );
}

String? _fieldText(WidgetTester tester, String key) =>
    tester.widget<TextField>(find.byKey(ValueKey(key))).controller?.text;

/// Отвечает на обновление каталога после подтверждённого создания.
void _completeCatalogRefresh(ControlledCatalogRepository repository) {
  if (repository.queries.length > 1) {
    repository.complete(
      1,
      ResultSuccess(
        IntentionCatalogFirstPage(
          items: const [],
          totalCount: 0,
          nextCursor: null,
          revision: const TestCatalogRevision(1),
        ),
      ),
    );
  }
}

Tag _tag(int number, String name) =>
    Tag(id: _tagId(number), name: TagName.fromInput(name));

Future<void> _closeOperationMessage(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 5));
  await tester.pumpAndSettle();
}

Future<AppRouter> _openEditor(
  WidgetTester tester,
  ControlledCatalogRepository repository, {
  Locale locale = const Locale('en'),
  List<ProviderObserver> observers = const [],
}) async {
  final router = AppRouter();
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        personalGraphRepositoryProvider.overrideWithValue(repository),
      ],
      observers: observers,
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
  await tester.tap(find.byKey(const ValueKey('catalog-create-intention')));
  await tester.pumpAndSettle();
  return router;
}

Result<IntentionCommandSuccess> _savedResult({required String title}) {
  final intention = testIntention(title: title);
  return ResultSuccess(
    IntentionSaved(
      intention,
      catalogMutation: IntentionCatalogCreated(
        revision: const TestCatalogRevision(1),
        entry: TestCatalogEntrySnapshot(
          IntentionSummary(
            id: intention.id,
            title: intention.title,
            hasDescription: intention.description != null,
            readiness: intention.readiness,
            archiveState: intention.archiveState,
            activeRelationCount: 0,
            createdAt: intention.createdAt,
            updatedAt: intention.updatedAt,
            favoriteMark: FavoriteMark.notFavorite,
          ),
        ),
      ),
    ),
  );
}

TagId _tagId(int number) => switch (TagId.decode(
  '018f47c2-6b7d-7abc-8def-${number.toString().padLeft(12, '0')}',
)) {
  TagIdDecodingSuccess(:final id) => id,
  InvalidTagIdDecoding() => throw StateError('Некорректный UUID тега.'),
};
