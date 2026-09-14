import 'package:auto_route/auto_route.dart';
import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/src/app/routing/app_router.dart';
import 'package:doable/src/app/routing/app_router.gr.dart';
import 'package:doable/src/graph/application/graph_command_coordinator.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:doable/src/graph/presentation/graph_operation_presenter.dart';
import 'package:doable/src/intention/application/intention_command.dart';
import 'package:doable/src/intention/application/intention_catalog.dart';
import 'package:doable/src/intention/application/intention_result.dart';
import 'package:doable/src/intention/domain/intention_text.dart';
import 'package:doable/src/intention/presentation/editor/intention_editor_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

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

  testWidgets('блокирует повторную отправку, сохраняя доступный Back', (
    tester,
  ) async {
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

    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(router.current.name, IntentionCatalogRoute.name);
    expect(repository.commands, hasLength(1));
    repository.completeCommand(
      0,
      const ResultFailure(IntentionUnexpectedFailure()),
    );
    await tester.pump();
  });

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

      expect(router.current.name, IntentionCatalogRoute.name);
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
      await tester.pageBack();
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
      await tester.pageBack();
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
    await tester.pageBack();
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

      expect(router.current.name, IntentionCatalogRoute.name);
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

      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(router.current.name, IntentionCatalogRoute.name);
      expect(find.textContaining(failure), findsNothing);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.textContaining(failure), findsOneWidget);

      await _closeOperationMessage(tester);
      await tester.pumpAndSettle();
      expect(find.textContaining(failure), findsNothing);
    },
  );
}

Future<void> _closeOperationMessage(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 5));
  await tester.pumpAndSettle();
}

Future<AppRouter> _openEditor(
  WidgetTester tester,
  ControlledCatalogRepository repository, {
  Locale locale = const Locale('en'),
}) async {
  final router = AppRouter();
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        personalGraphRepositoryProvider.overrideWithValue(repository),
      ],
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
            createdAt: intention.createdAt,
            updatedAt: intention.updatedAt,
          ),
        ),
      ),
    ),
  );
}
