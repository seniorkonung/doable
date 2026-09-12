import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/src/app/routing/app_router.dart';
import 'package:doable/src/app/routing/app_router.gr.dart';
import 'package:doable/src/intention/application/intention_command.dart';
import 'package:doable/src/intention/application/intention_repository.dart';
import 'package:doable/src/intention/application/intention_result.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/intention/domain/intention_text.dart';
import 'package:doable/src/intention/presentation/details/intention_details_page.dart';
import 'package:doable/src/intention/presentation/operation/intention_command_coordinator.dart';
import 'package:doable/src/intention/presentation/operation/intention_repository_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'details_test_support.dart';

void main() {
  test('маршрут подробного просмотра хранит предметный идентификатор', () {
    final id = testDetailsIntentionId(1);

    final route = IntentionDetailsRoute(intentionId: id);

    expect(route, isA<PageRouteInfo<IntentionDetailsRouteArgs>>());
    expect(route.args!.intentionId, same(id));
  });

  testWidgets('показывает загрузку и пользовательский текст без перевода', (
    tester,
  ) async {
    final repository = ControlledDetailsRepository();
    final intention = testDetailsIntention(
      title: 'Сохранить русский заголовок',
      description: '  Описание\nбез преобразования  ',
      readiness: IntentionReadiness.ready,
    );
    await _pumpDetailsPage(tester, repository, intention.id);
    await waitForDetailRequests(repository, 1);

    expect(find.text('Loading intention…'), findsOneWidget);
    repository.detailRequests.single.add(ResultSuccess(intention));
    await tester.pump();

    expect(find.text('Сохранить русский заголовок'), findsOneWidget);
    expect(find.text('  Описание\nбез преобразования  '), findsOneWidget);
    expect(find.text('Ready for action'), findsOneWidget);
    expect(find.text('Active'), findsOneWidget);
  });

  testWidgets('показывает архивное состояние и отсутствие описания', (
    tester,
  ) async {
    final repository = ControlledDetailsRepository();
    final intention = testDetailsIntention(
      index: 2,
      title: 'Архивное намерение',
      description: null,
      archiveState: IntentionArchiveState.archived,
    );
    await _pumpDetailsPage(tester, repository, intention.id);
    await waitForDetailRequests(repository, 1);

    repository.detailRequests.single.add(ResultSuccess(intention));
    await tester.pump();

    expect(find.text('Archived'), findsOneWidget);
    expect(find.text('No description'), findsOneWidget);
    expect(find.text('Not ready for action'), findsOneWidget);
  });

  testWidgets('отличает подтверждённое отсутствие от загрузки', (tester) async {
    final repository = ControlledDetailsRepository();
    final id = testDetailsIntentionId(3);
    await _pumpDetailsPage(tester, repository, id);
    await waitForDetailRequests(repository, 1);
    repository.detailRequests.single.add(const ResultSuccess(null));
    await tester.pump();

    expect(find.text('Intention not found.'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Try again'), findsNothing);
  });

  testWidgets('показывает терминальные отказы без обычного повтора', (
    tester,
  ) async {
    final scenarios = <(IntentionFailure, String)>[
      (
        const IntentionCorruptionFailure(),
        'Stored intention data is damaged and can’t be shown.',
      ),
      (
        const IntentionUnexpectedFailure(),
        'The intention couldn’t be loaded because of an unexpected error.',
      ),
    ];

    for (var index = 0; index < scenarios.length; index += 1) {
      final repository = ControlledDetailsRepository();
      final id = testDetailsIntentionId(index + 60);
      await _pumpDetailsPage(tester, repository, id);
      await waitForDetailRequests(repository, 1);
      final (failure, message) = scenarios[index];

      repository.detailRequests.single.add(ResultFailure(failure));
      await tester.pump();

      expect(find.text(message), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Try again'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    }
  });

  testWidgets('повторяет только устранимое чтение подробных данных', (
    tester,
  ) async {
    final repository = ControlledDetailsRepository();
    final intention = testDetailsIntention(index: 4);
    await _pumpDetailsPage(tester, repository, intention.id);
    await waitForDetailRequests(repository, 1);
    repository.detailRequests.single.add(
      const ResultFailure(IntentionUnavailableFailure()),
    );
    await tester.pump();

    expect(
      find.text('The intention couldn’t be loaded. Try again.'),
      findsOneWidget,
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Try again'));
    await tester.pump();
    await waitForDetailRequests(repository, 2);
    expect(find.text('Loading intention…'), findsOneWidget);

    repository.detailRequests[1].add(ResultSuccess(intention));
    await tester.pump();
    expect(find.text(intention.title), findsOneWidget);
  });

  testWidgets('показывает сохраняющийся gate намерения отдельно от чтения', (
    tester,
  ) async {
    final repository = ControlledDetailsRepository();
    final intention = testDetailsIntention(index: 5);
    final container = _detailsContainer(repository);
    addTearDown(container.dispose);
    final coordinator = container.read(
      intentionCommandCoordinatorProvider.notifier,
    );
    final start = coordinator.accept(DeleteIntention(intention.id));
    expect(start, isA<IntentionCommandAccepted>());

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: _localizedApp(IntentionDetailsPage(intentionId: intention.id)),
      ),
    );
    await waitForDetailRequests(repository, 1);

    expect(find.text('Saving changes…'), findsOneWidget);
    expect(find.text('Loading intention…'), findsOneWidget);

    repository.detailRequests.single.add(ResultSuccess(intention));
    await tester.pump();
    expect(
      tester
          .widget<OutlinedButton>(
            find.byKey(const ValueKey('intention-details-edit')),
          )
          .onPressed,
      isNull,
    );

    repository.completeCommand(
      0,
      const ResultFailure(IntentionUnavailableFailure()),
    );
    await (start as IntentionCommandAccepted).future;
    await tester.pump();
  });

  testWidgets(
    'изменяет поля без optimistic state и блокирует mutating controls на время записи',
    (tester) async {
      final repository = ControlledDetailsRepository();
      final intention = testDetailsIntention(
        index: 50,
        title: 'Прежнее название',
        description: 'Прежнее описание',
      );
      await _pumpDetailsPage(tester, repository, intention.id);
      await waitForDetailRequests(repository, 1);
      repository.detailRequests[0].add(ResultSuccess(intention));
      await tester.pump();

      await tester.tap(find.widgetWithText(OutlinedButton, 'Edit'));
      await tester.pump();
      expect(
        tester
            .widget<TextField>(
              find.byKey(const ValueKey('intention-details-edit-title')),
            )
            .controller
            ?.text,
        'Прежнее название',
      );
      await tester.enterText(
        find.byKey(const ValueKey('intention-details-edit-title')),
        '  Новое название  ',
      );
      await tester.enterText(
        find.byKey(const ValueKey('intention-details-edit-description')),
        '  Новое описание\n',
      );
      await tester.tap(
        find.byKey(const ValueKey('intention-details-edit-submit')),
      );
      await tester.pump();

      expect(repository.commands, hasLength(1));
      expect(
        repository.commands.single,
        isA<UpdateIntention>()
            .having(
              (command) => command.title,
              'исходное название',
              '  Новое название  ',
            )
            .having(
              (command) => command.description,
              'исходное описание',
              '  Новое описание\n',
            ),
      );
      expect(find.text('Прежнее название'), findsOneWidget);
      expect(find.text('Saving changes…'), findsNWidgets(2));
      expect(
        tester
            .widget<TextField>(
              find.byKey(const ValueKey('intention-details-edit-title')),
            )
            .enabled,
        isFalse,
      );
      expect(
        tester
            .widget<ButtonStyleButton>(
              find.byKey(const ValueKey('intention-details-edit-submit')),
            )
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<ButtonStyleButton>(
              find.byKey(const ValueKey('intention-details-edit-cancel')),
            )
            .onPressed,
        isNull,
      );

      repository.completeCommand(
        0,
        const ResultFailure(IntentionUnexpectedFailure()),
      );
      await tester.pumpAndSettle();
    },
  );

  testWidgets('прикрепляет ошибки текста к полю и сохраняет исправимый ввод', (
    tester,
  ) async {
    final scenarios =
        <(IntentionTextField, IntentionTextValidationReason, String)>[
          (
            IntentionTextField.title,
            IntentionTextValidationReason.empty,
            'Enter a title.',
          ),
          (
            IntentionTextField.title,
            IntentionTextValidationReason.tooLong,
            'Use no more than 255 characters.',
          ),
          (
            IntentionTextField.title,
            IntentionTextValidationReason.invalidUnicodeRepertoire,
            'Enter valid Unicode text without NUL.',
          ),
          (
            IntentionTextField.description,
            IntentionTextValidationReason.tooLong,
            'Use no more than 4096 characters.',
          ),
          (
            IntentionTextField.description,
            IntentionTextValidationReason.invalidUnicodeRepertoire,
            'Enter valid Unicode text without NUL.',
          ),
        ];

    for (var index = 0; index < scenarios.length; index += 1) {
      final repository = ControlledDetailsRepository();
      final intention = testDetailsIntention(index: 60 + index);
      await _pumpDetailsPage(tester, repository, intention.id);
      await waitForDetailRequests(repository, 1);
      repository.detailRequests[0].add(ResultSuccess(intention));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(OutlinedButton, 'Edit'));
      await tester.pump();

      final (field, reason, message) = scenarios[index];
      final key = switch (field) {
        IntentionTextField.title => const ValueKey(
          'intention-details-edit-title',
        ),
        IntentionTextField.description => const ValueKey(
          'intention-details-edit-description',
        ),
        IntentionTextField.titleFilter => throw StateError(
          'Фильтр каталога не относится к форме подробного представления.',
        ),
      };
      final entered = 'Исправляемый ввод $index';
      await tester.enterText(find.byKey(key), entered);
      await tester.tap(
        find.byKey(const ValueKey('intention-details-edit-submit')),
      );
      repository.completeCommand(
        0,
        ResultFailure(
          IntentionTextInputValidationFailure(
            IntentionTextValidationFailure(field: field, reason: reason),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(message), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byKey(key)).controller?.text,
        entered,
      );
      expect(tester.widget<TextField>(find.byKey(key)).enabled, isTrue);
      expect(
        tester
            .widget<ButtonStyleButton>(
              find.byKey(const ValueKey('intention-details-edit-submit')),
            )
            .onPressed,
        isNull,
      );
      await tester.enterText(find.byKey(key), '$entered исправлен');
      await tester.pump();
      expect(find.text(message), findsNothing);
      expect(
        tester
            .widget<ButtonStyleButton>(
              find.byKey(const ValueKey('intention-details-edit-submit')),
            )
            .onPressed,
        isNotNull,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    }
  });

  testWidgets('показывает confirmed success только после completion', (
    tester,
  ) async {
    final repository = ControlledDetailsRepository();
    final before = testDetailsIntention(index: 70, title: 'До изменения');
    final saved = testDetailsIntention(index: 70, title: 'После изменения');
    await _pumpDetailsPage(tester, repository, before.id);
    await waitForDetailRequests(repository, 1);
    repository.detailRequests[0].add(ResultSuccess(before));
    await tester.pump();
    await tester.tap(find.widgetWithText(OutlinedButton, 'Edit'));
    await tester.pump();
    await tester.enterText(
      find.byKey(const ValueKey('intention-details-edit-title')),
      saved.title,
    );
    await tester.tap(
      find.byKey(const ValueKey('intention-details-edit-submit')),
    );
    await tester.pump();

    expect(find.text('До изменения'), findsOneWidget);
    expect(find.text('После изменения'), findsOneWidget);
    repository.completeCommand(
      0,
      testDetailsSavedResult(saved, before: before),
    );
    await tester.pump();
    await waitForDetailRequests(repository, 2);
    await tester.pump();

    expect(find.text('Changes saved.'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('intention-details-edit-title')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('intention-details-title')),
      findsOneWidget,
    );
    expect(find.text('После изменения'), findsOneWidget);
  });

  testWidgets(
    'оставляет уход доступным и передаёт поздний update outcome каталогу',
    (tester) async {
      final repository = ControlledDetailsRepository();
      final intention = testDetailsIntention(
        index: 71,
        title: 'Изменяемое намерение',
      );
      repository.catalogResult = ResultSuccess(
        IntentionCatalogFirstPage(
          items: [testDetailsSummary(intention)],
          totalCount: 1,
          nextCursor: null,
          revision: const _DetailsTestRevision(),
        ),
      );
      final router = AppRouter();
      final container = _detailsContainer(repository);
      addTearDown(router.dispose);
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(
            locale: const Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            routerConfig: router.config(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text(intention.title));
      await tester.pump();
      await waitForDetailRequests(repository, 1);
      repository.detailRequests[0].add(ResultSuccess(intention));
      await tester.pump();
      await tester.tap(find.widgetWithText(OutlinedButton, 'Edit'));
      await tester.pump();
      await tester.enterText(
        find.byKey(const ValueKey('intention-details-edit-title')),
        'Позднее изменение',
      );
      await tester.ensureVisible(
        find.byKey(const ValueKey('intention-details-edit-submit')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('intention-details-edit-submit')),
      );
      await tester.pump();
      expect(find.text('Saving changes…'), findsNWidgets(2));

      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(router.current.name, IntentionCatalogRoute.name);

      repository.completeCommand(
        0,
        const ResultFailure(IntentionUnavailableFailure()),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('The changes couldn’t be saved. Try again.'),
        findsOneWidget,
      );
    },
  );

  testWidgets('строка каталога открывает generated details route', (
    tester,
  ) async {
    final repository = ControlledDetailsRepository();
    final intention = testDetailsIntention(
      index: 6,
      title: 'Открываемое намерение',
      archiveState: IntentionArchiveState.archived,
    );
    repository.catalogResult = ResultSuccess(
      IntentionCatalogFirstPage(
        items: [testDetailsSummary(intention)],
        totalCount: 1,
        nextCursor: null,
        revision: const _DetailsTestRevision(),
      ),
    );
    final router = AppRouter();
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [intentionRepositoryProvider.overrideWithValue(repository)],
        retry: (retryCount, error) => null,
        child: MaterialApp.router(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: router.config(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('catalog-scope-control')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Archived').last);
    await tester.pumpAndSettle();
    expect(repository.catalogQueries.last.scope, IntentionScope.archived);

    await tester.tap(find.text('Открываемое намерение'));
    await tester.pump();
    await waitForDetailRequests(repository, 1);
    await tester.pump(const Duration(milliseconds: 500));

    expect(router.current.name, IntentionDetailsRoute.name);
    expect(find.byType(IntentionDetailsPage), findsOneWidget);
    expect(repository.detailIds.single, intention.id);
  });

  testWidgets('IntentionDeleted завершает открытый details route', (
    tester,
  ) async {
    final repository = ControlledDetailsRepository();
    repository.catalogResult = ResultSuccess(
      IntentionCatalogFirstPage(
        items: const [],
        totalCount: 0,
        nextCursor: null,
        revision: const _DetailsTestRevision(),
      ),
    );
    final intention = testDetailsIntention(index: 70);
    final router = AppRouter();
    final container = _detailsContainer(repository);
    addTearDown(router.dispose);
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: router.config(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    unawaited(router.push(IntentionDetailsRoute(intentionId: intention.id)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await waitForDetailRequests(repository, 1);
    repository.detailRequests[0].add(ResultSuccess(intention));
    await tester.pump();
    expect(router.current.name, IntentionDetailsRoute.name);

    final start = container
        .read(intentionCommandCoordinatorProvider.notifier)
        .accept(DeleteIntention(intention.id));
    repository.completeCommand(0, testDetailsDeletedResult(intention));
    await (start as IntentionCommandAccepted).future;
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(router.current.name, IntentionCatalogRoute.name);
    expect(find.byType(IntentionDetailsPage), findsNothing);
  });
}

Future<void> _pumpDetailsPage(
  WidgetTester tester,
  ControlledDetailsRepository repository,
  IntentionId intentionId,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [intentionRepositoryProvider.overrideWithValue(repository)],
      retry: (retryCount, error) => null,
      child: _localizedApp(IntentionDetailsPage(intentionId: intentionId)),
    ),
  );
  await tester.pump();
}

ProviderContainer _detailsContainer(ControlledDetailsRepository repository) =>
    ProviderContainer(
      overrides: [intentionRepositoryProvider.overrideWithValue(repository)],
      retry: (retryCount, error) => null,
    );

Widget _localizedApp(Widget home) => MaterialApp(
  locale: const Locale('en'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: home,
);

final class _DetailsTestRevision implements IntentionCatalogRevision {
  const _DetailsTestRevision();

  @override
  IntentionCatalogRevisionOrder compareTo(IntentionCatalogRevision other) =>
      other is _DetailsTestRevision
      ? IntentionCatalogRevisionOrder.same
      : IntentionCatalogRevisionOrder.differentEpoch;
}
