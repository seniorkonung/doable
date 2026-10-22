import 'dart:async';

import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/src/graph/application/graph_command_coordinator.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:doable/src/graph/presentation/graph_operation_presenter.dart';
import 'package:doable/src/graph/presentation/operation_failure_presentation.dart';
import 'package:doable/src/intention/application/intention_command.dart';
import 'package:doable/src/intention/application/intention_result.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/intention/presentation/editor/intention_editor_state.dart';
import 'package:doable/src/intention/presentation/editor/intention_editor_view_model.dart';
import 'package:doable/src/intention/presentation/operation/operation_state.dart';
import 'package:doable/src/tag/application/tag_command.dart';
import 'package:doable/src/tag/application/tag_result.dart';
import 'package:doable/src/tag/domain/tag_id.dart';
import 'package:doable/src/tag/presentation/catalog/tag_catalog_page.dart';
import 'package:doable/src/tag/presentation/catalog/tag_catalog_view.dart';
import 'package:doable/src/tag/presentation/catalog/tag_selection_context.dart';
import 'package:doable/src/tag/presentation/tag_failure_message.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../intention/presentation/details/details_test_support.dart';

void main() {
  setUp(() {
    WidgetsBinding.instance.handleAppLifecycleStateChanged(
      AppLifecycleState.resumed,
    );
  });

  testWidgets(
    'рисует конкретное сообщение с live-region семантикой и не повторяет его на общей поверхности',
    (tester) async {
      final harness = _FailureHarness();
      addTearDown(harness.dispose);
      final claim = await harness.createClaim(index: 1);

      await tester.pumpWidget(
        harness.app(
          OperationFailurePresentation(
            claim: claim,
            message: 'Ошибка сохранения',
            messageKey: const ValueKey('operation-failure-message'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Ошибка сохранения'), findsOneWidget);
      expect(
        tester.getSemantics(
          find.byKey(const ValueKey('operation-failure-message')),
        ),
        matchesSemantics(
          label: 'Ошибка сохранения',
          isLiveRegion: true,
          textDirection: TextDirection.ltr,
        ),
      );
      expect(find.byType(SnackBar), findsNothing);
    },
  );

  testWidgets(
    'не подменяет область ошибки видимым полем, а исчезнувший скрытый renderer передаёт отказ общей поверхности',
    (tester) async {
      final harness = _FailureHarness();
      addTearDown(harness.dispose);
      final claim = await harness.createClaim(index: 2);
      final showError = ValueNotifier(true);
      addTearDown(showError.dispose);

      await tester.pumpWidget(
        harness.app(
          Column(
            children: [
              const TextField(decoration: InputDecoration(labelText: 'Поле')),
              ValueListenableBuilder<bool>(
                valueListenable: showError,
                builder: (context, visible, _) => visible
                    ? ClipRect(
                        child: Align(
                          heightFactor: 0,
                          child: OperationFailurePresentation(
                            claim: claim,
                            message: 'Скрытая ошибка',
                          ),
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Невидимая ошибка не считается предъявленной, но и общая поверхность
      // её ещё не показывает.
      expect(find.text('Поле'), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);

      showError.value = false;
      await tester.pumpAndSettle();

      expect(find.text(_notDeleted('Намерение')), findsOneWidget);
      await _closeMessage(tester);
      expect(find.byType(SnackBar), findsNothing);
    },
  );

  testWidgets(
    'смена локализованного сообщения не отдаёт отказ общей поверхности',
    (tester) async {
      final harness = _FailureHarness();
      addTearDown(harness.dispose);
      final claim = await harness.createClaim(index: 9);
      final message = ValueNotifier('The operation failed.');
      addTearDown(message.dispose);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);

      await tester.pumpWidget(
        harness.app(
          ValueListenableBuilder<String>(
            valueListenable: message,
            builder: (context, value, _) =>
                OperationFailurePresentation(claim: claim, message: value),
          ),
        ),
      );
      await tester.pump();

      message.value = 'Операцию выполнить не удалось.';
      await tester.pump();
      await tester.pump();

      expect(find.text('The operation failed.'), findsNothing);
      expect(find.text('Операцию выполнить не удалось.'), findsOneWidget);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();

      expect(find.text('Операцию выполнить не удалось.'), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
    },
  );

  testWidgets('исчезновение после подтверждения не возвращает результат', (
    tester,
  ) async {
    final harness = _FailureHarness();
    addTearDown(harness.dispose);
    final claim = await harness.createClaim(index: 8);
    final showError = ValueNotifier(true);
    addTearDown(showError.dispose);

    await tester.pumpWidget(
      harness.app(
        ValueListenableBuilder<bool>(
          valueListenable: showError,
          builder: (context, visible, _) => visible
              ? OperationFailurePresentation(
                  claim: claim,
                  message: 'Предъявленная ошибка',
                )
              : const SizedBox.shrink(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Предъявленная ошибка'), findsOneWidget);

    showError.value = false;
    await tester.pumpAndSettle();

    expect(find.text('Предъявленная ошибка'), findsNothing);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets(
    'замена renderer передаёт общей поверхности только прежний отказ, а новый остаётся в renderer',
    (tester) async {
      final harness = _FailureHarness();
      addTearDown(harness.dispose);
      final first = await harness.createClaim(index: 5, title: 'Первое');
      final second = await harness.createClaim(index: 6, title: 'Второе');
      final current = ValueNotifier((claim: first, message: 'Первая ошибка'));
      addTearDown(current.dispose);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);

      await tester.pumpWidget(
        harness.app(
          ValueListenableBuilder<
            ({GraphInitiatorPresentationClaim claim, String message})
          >(
            valueListenable: current,
            builder: (context, value, _) => OperationFailurePresentation(
              claim: value.claim,
              message: value.message,
            ),
          ),
        ),
      );
      await tester.pump();

      current.value = (claim: second, message: 'Вторая ошибка');
      await tester.pump();
      await tester.pump();

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();

      expect(find.text('Вторая ошибка'), findsOneWidget);
      expect(find.text(_notDeleted('Первое')), findsOneWidget);
      expect(find.text(_notDeleted('Второе')), findsNothing);

      await _closeMessage(tester);
      expect(find.byType(SnackBar), findsNothing);
    },
  );

  testWidgets(
    'отказ назначения без права инициатора показывает общая поверхность, а '
    'занятость остаётся инлайн',
    (tester) async {
      final harness = _FailureHarness();
      addTearDown(harness.dispose);
      harness.failAssignment();

      await tester.pumpWidget(
        harness.app(
          Builder(
            builder: (context) => OperationFailurePresentation(
              claim: null,
              message: tagAssignmentStartMessage(
                AppLocalizations.of(context),
                const TagCommandAlreadyRunning(),
              )!,
              messageKey: const ValueKey('assignment-busy-message'),
            ),
          ),
          locale: const Locale('ru'),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text(
          'Изменение назначения тега уже выполняется. Дождитесь результата.',
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byType(SnackBar),
          matching: find.text(
            'Назначение — «назначение тега»: Этого намерения больше нет. '
            'Обновите подробности.',
          ),
        ),
        findsOneWidget,
      );
      await _closeMessage(tester);
      expect(find.byType(SnackBar), findsNothing);
    },
  );

  testWidgets(
    'исчезнувшая до кадра форма передаёт отказ отсутствующих тегов общей поверхности один раз',
    (tester) async {
      final harness = _FailureHarness();
      addTearDown(harness.dispose);
      final claim = await harness.createFullCreationTagsMissingClaim();
      final showError = ValueNotifier(true);
      addTearDown(showError.dispose);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);

      await tester.pumpWidget(
        harness.app(
          ValueListenableBuilder<bool>(
            valueListenable: showError,
            builder: (context, visible, _) => visible
                ? OperationFailurePresentation(
                    claim: claim,
                    message: 'Проверьте введённые данные.',
                  )
                : const SizedBox.shrink(),
          ),
        ),
      );
      await tester.pump();

      showError.value = false;
      await tester.pump();
      await tester.pump();

      // Возвращение фокуса не даёт кадру исчезнувшей формы подтвердить
      // предъявление: общая поверхность показывает отказ сама, один раз.
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.text(_tagsMissingMessage), findsOneWidget);
      expect(find.text('Проверьте введённые данные.'), findsNothing);

      await _closeMessage(tester);
      expect(find.byType(SnackBar), findsNothing);
    },
  );

  group('закрытие сессии создания', () {
    testWidgets(
      'отказ под подтверждением закрытия остаётся у живой формы, а запоздалый сброс её не закрывает',
      (tester) async {
        final harness = _FailureHarness();
        addTearDown(harness.dispose);
        final provider = intentionEditorViewModelProvider(
          IntentionCreationFormKey(),
        );
        await _openCreationSession(tester, harness, provider);
        harness.container.read(provider.notifier)
          ..changeTitle('Намерение')
          ..submit();

        await tester.tap(find.text('Закрыть'));
        await tester.pumpAndSettle();
        expect(find.text(_savingContinuesWarning), findsOneWidget);

        harness.repository.completeCommand(
          harness.repository.commands.length - 1,
          const ResultFailure(IntentionUnavailableFailure()),
        );
        await tester.pumpAndSettle();

        // Временное перекрытие подтверждением сохраняет отказ у формы.
        expect(find.text(_creationFailureMessage), findsOneWidget);
        expect(find.byType(SnackBar), findsNothing);

        await tester.tap(find.text('Сбросить'));
        await tester.pumpAndSettle();

        expect(find.text(_savingContinuesWarning), findsNothing);
        expect(find.text('Закрыть'), findsOneWidget);
        expect(find.text(_creationFailureMessage), findsOneWidget);
        expect(find.byType(SnackBar), findsNothing);
      },
    );

    testWidgets(
      'сброс сессии до предъявления отказа передаёт его общей поверхности один раз',
      (tester) async {
        final harness = _FailureHarness();
        addTearDown(harness.dispose);
        final provider = intentionEditorViewModelProvider(
          IntentionCreationFormKey(),
        );
        await _openCreationSession(tester, harness, provider);
        harness.container.read(provider.notifier)
          ..changeTitle('Намерение')
          ..submit();
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        harness.repository.completeCommand(
          harness.repository.commands.length - 1,
          const ResultFailure(IntentionUnavailableFailure()),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Закрыть'));
        await tester.pumpAndSettle();
        expect(find.text(_draftLossWarning), findsOneWidget);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pumpAndSettle();

        // Подтверждение перекрывает живую форму: отказ остаётся у неё.
        expect(find.byType(SnackBar), findsNothing);

        await tester.tap(find.text('Сбросить'));
        await tester.pumpAndSettle();

        expect(find.text('Закрыть'), findsNothing);
        expect(find.text(_creationFailureMessage), findsNothing);
        expect(find.text(_creationShellMessage), findsOneWidget);
        await _closeMessage(tester);
        expect(find.byType(SnackBar), findsNothing);
      },
    );
  });

  group('право отказа сессии создания под непрозрачным выбором тегов', () {
    testWidgets(
      'отказ под выбором тегов остаётся у формы и предъявляется ею один раз после возвращения',
      (tester) async {
        final harness = _FailureHarness();
        addTearDown(harness.dispose);
        final provider = intentionEditorViewModelProvider(
          IntentionCreationFormKey(),
        );
        await _openCreationSession(tester, harness, provider);
        harness.container.read(provider.notifier)
          ..changeTitle('Намерение')
          ..submit();
        await _openTagChooser(tester);

        harness.repository.completeCommand(
          harness.repository.commands.length - 1,
          const ResultFailure(IntentionUnavailableFailure()),
        );
        await tester.pumpAndSettle();

        // Перекрытая форма отказ не показывает, и общая поверхность тоже.
        expect(find.byType(TagCatalogView), findsOneWidget);
        expect(find.text(_creationFailureMessage), findsNothing);
        expect(find.byType(SnackBar), findsNothing);

        await tester.tap(find.byType(BackButton));
        await tester.pumpAndSettle();

        expect(find.byType(TagCatalogView), findsNothing);
        expect(find.text(_creationFailureMessage), findsOneWidget);
        expect(find.byType(SnackBar), findsNothing);
      },
    );

    for (final removal in _HostRemoval.values) {
      testWidgets(
        'удаление хоста под выбором тегов без возвращения (${removal.description}) передаёт отказ общей поверхности ровно один раз',
        (tester) async {
          final harness = _FailureHarness();
          addTearDown(harness.dispose);
          final provider = intentionEditorViewModelProvider(
            IntentionCreationFormKey(),
          );
          await _openCreationSession(tester, harness, provider);
          harness.container.read(provider.notifier)
            ..changeTitle('Намерение')
            ..submit();
          await _openTagChooser(tester);

          harness.repository.completeCommand(
            harness.repository.commands.length - 1,
            const ResultFailure(IntentionUnavailableFailure()),
          );
          await tester.pumpAndSettle();
          expect(find.text(_creationFailureMessage), findsNothing);
          expect(find.byType(SnackBar), findsNothing);

          removal.apply(
            Navigator.of(tester.element(find.byType(TagCatalogView))),
          );
          await tester.pumpAndSettle();

          expect(find.byType(TagCatalogView), findsNothing);
          expect(find.text(_creationFailureMessage), findsNothing);
          expect(find.text(_creationShellMessage), findsOneWidget);
          await _closeMessage(tester);
          expect(find.byType(SnackBar), findsNothing);
        },
      );
    }
  });
}

/// Способ окончательно удалить хост сессии вместе с перекрывающим его
/// выбором тегов, не возвращаясь к нему.
enum _HostRemoval {
  /// Хост может построиться во время анимации ухода выбора: право тогда
  /// освобождают и renderer, и сессия, а предъявление остаётся единственным.
  popUntil('popUntil к исходной странице'),

  /// Хост удаляется под непрозрачным маршрутом без нового построения: право
  /// передаёт только сессия.
  stackReset('сброс стека без нового построения хоста');

  const _HostRemoval(this.description);

  final String description;

  void apply(NavigatorState navigator) => switch (this) {
    _HostRemoval.popUntil => navigator.popUntil((route) => route.isFirst),
    _HostRemoval.stackReset => unawaited(
      navigator.pushAndRemoveUntil(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('Новый корень')),
        ),
        (_) => false,
      ),
    ),
  };
}

Future<void> _closeMessage(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 5));
  await tester.pumpAndSettle();
}

String _notDeleted(String title) =>
    'Delete — “$title”: The intention couldn’t be deleted. Try again.';

/// Открывает существующую страницу выбора тегов с контекстом черновика
/// сессии непрозрачным маршрутом поверх её хоста.
Future<void> _openTagChooser(WidgetTester tester) async {
  await tester.tap(find.text('Теги'));
  await tester.pumpAndSettle();
}

const _creationFailureMessage = 'Не удалось создать намерение';

/// Сообщение общей поверхности об отказе создания (английский язык по
/// умолчанию).
const _creationShellMessage =
    'Create — “new intention”: The intention couldn’t be created. Try again.';
const _tagsMissingMessage = 'Create — “new intention”: Check the entered data.';
const _draftLossWarning = 'Несохранённый черновик будет потерян';
const _savingContinuesWarning =
    'Несохранённый черновик будет потерян, сохранение продолжится';

/// Открывает управляемую сессию создания на собственном маршруте поверх
/// исходной страницы.
Future<void> _openCreationSession(
  WidgetTester tester,
  _FailureHarness harness,
  IntentionEditorViewModelProvider provider,
) async {
  await tester.pumpWidget(
    harness.app(
      Builder(
        builder: (context) => TextButton(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => _CreationSessionRoute(provider),
            ),
          ),
          child: const Text('Создать'),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Создать'));
  await tester.pumpAndSettle();
}

/// Управляемая сессия создания: рисует её отказ общим renderer, открывает
/// над собой существующий выбор тегов с контекстом её черновика и закрывает
/// свой маршрут только по решению сессии после её единственного
/// подтверждения.
final class _CreationSessionRoute extends ConsumerWidget {
  const _CreationSessionRoute(this.provider);

  final IntentionEditorViewModelProvider provider;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(provider);
    return Scaffold(
      body: Column(
        children: [
          TextButton(
            onPressed: () =>
                _requestClose(context, ref.read(provider.notifier)),
            child: const Text('Закрыть'),
          ),
          TextButton(
            onPressed: () => unawaited(
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => TagCatalogPage(
                    selectionContext: TagDraftContext(
                      ref.read(provider.notifier).draftTagSet,
                    ),
                  ),
                ),
              ),
            ),
            child: const Text('Теги'),
          ),
          if (session.operation case OperationFailed<Intention>())
            OperationFailurePresentation(
              claim: session.failurePresentation,
              message: _creationFailureMessage,
            ),
        ],
      ),
    );
  }

  Future<void> _requestClose(
    BuildContext context,
    IntentionEditorViewModel session,
  ) async {
    final navigator = Navigator.of(context);
    switch (session.requestClose()) {
      case IntentionCreationClosedImmediately():
        navigator.pop();
      case IntentionCreationCloseNeedsConfirmation(:final confirmation):
        final choice = await showDialog<IntentionCreationCloseChoice>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            content: Text(switch (confirmation.savingOnClose) {
              IntentionCreationSavingOnClose.notStarted => _draftLossWarning,
              IntentionCreationSavingOnClose.continues =>
                _savingContinuesWarning,
            }),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(
                  dialogContext,
                  IntentionCreationCloseChoice.continueEditing,
                ),
                child: const Text('Продолжить'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(
                  dialogContext,
                  IntentionCreationCloseChoice.discardDraft,
                ),
                child: const Text('Сбросить'),
              ),
            ],
          ),
        );
        final resolution = session.resolveClose(
          confirmation,
          choice ?? IntentionCreationCloseChoice.continueEditing,
        );
        switch (resolution) {
          case IntentionCreationCloseResolution.closed:
            navigator.pop();
          case IntentionCreationCloseResolution.continued ||
              IntentionCreationCloseResolution.outdated:
            return;
        }
      case IntentionCreationCloseAwaitingConfirmation() ||
          IntentionCreationCloseSessionEnded():
        return;
    }
  }
}

final class _FailureHarness {
  _FailureHarness._(this.repository, this.container);

  factory _FailureHarness() {
    final repository = ControlledDetailsRepository();
    return _FailureHarness._(
      repository,
      ProviderContainer(
        overrides: [
          personalGraphRepositoryProvider.overrideWithValue(repository),
        ],
        retry: (retryCount, error) => null,
      ),
    );
  }

  final ControlledDetailsRepository repository;
  final ProviderContainer container;

  GraphCommandCoordinator get coordinator =>
      container.read(graphCommandCoordinatorProvider.notifier);

  Future<GraphInitiatorPresentationClaim> createClaim({
    required int index,
    String title = 'Намерение',
  }) async {
    final intention = testDetailsIntention(index: index, title: title);
    final accepted = coordinator.acceptExisting(
      DeleteIntention(intention.id),
      presentationTitle: intention.title,
    ) as IntentionCommandAccepted;
    repository.completeCommand(
      repository.commands.length - 1,
      const ResultFailure(IntentionUnavailableFailure()),
    );
    await accepted.future;
    return coordinator.claimInitiatorFailure(accepted.token)!;
  }

  /// Право живой формы на отказ полного создания, один из выбранных тегов
  /// которого отсутствует.
  Future<GraphInitiatorPresentationClaim>
  createFullCreationTagsMissingClaim() async {
    final missingTag = switch (TagId.decode(
      '018f1400-0000-7000-8000-000000000004',
    )) {
      TagIdDecodingSuccess(:final id) => id,
      InvalidTagIdDecoding() => throw StateError('Некорректный ID тега.'),
    };
    final accepted = coordinator.acceptCreation(
      IntentionCreationFormKey(),
      CreateIntention.withInitialState(
        title: 'Полное намерение',
        description: null,
        readiness: IntentionReadiness.ready,
        tagIds: [missingTag],
      ),
    ) as IntentionCommandAccepted;
    repository.completeCommand(
      repository.commands.length - 1,
      ResultFailure(IntentionCreationTagsMissingFailure([missingTag])),
    );
    await accepted.future;
    return coordinator.claimInitiatorFailure(accepted.token)!;
  }

  void failAssignment() {
    final tagId = switch (TagId.decode(
      '018f1400-0000-7000-8000-000000000003',
    )) {
      TagIdDecodingSuccess(:final id) => id,
      InvalidTagIdDecoding() => throw StateError('Некорректный ID тега.'),
    };
    final intentionId = testDetailsIntentionId(1);
    coordinator.acceptTagAssign(
      AssignTag(tagId: tagId, intentionId: intentionId),
    );
    repository.completeTagCommand(
      repository.tagCommands.length - 1,
      TagCommandFailed(TagIntentionNotFoundFailure(intentionId)),
    );
  }

  Widget app(Widget body, {Locale locale = const Locale('en')}) =>
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          locale: locale,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) => GraphOperationPresenter(child: child!),
          home: Scaffold(body: body),
        ),
      );

  void dispose() {
    container.dispose();
  }
}
