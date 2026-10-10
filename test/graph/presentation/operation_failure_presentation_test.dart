import 'dart:async';

import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/src/graph/application/graph_command_coordinator.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:doable/src/graph/presentation/operation_failure_presentation.dart';
import 'package:doable/src/intention/application/intention_catalog.dart';
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
    'рисует конкретное сообщение с live-region семантикой и подтверждает его кадр',
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
      expect(harness.claimAgain(claim), isNull);
    },
  );

  testWidgets(
    'не подменяет область ошибки видимым полем и освобождает исчезнувший renderer',
    (tester) async {
      final harness = _FailureHarness();
      addTearDown(harness.dispose);
      final claim = await harness.createClaim(index: 2);
      final showError = ValueNotifier(true);
      addTearDown(showError.dispose);
      GraphAppPresentationClaim? fallback;
      unawaited(
        harness.registration.nextClaim().then((value) => fallback = value),
      );

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
      await tester.pump();

      expect(find.text('Поле'), findsOneWidget);
      expect(harness.claimAgain(claim), same(claim));
      expect(fallback, isNull);

      showError.value = false;
      await tester.pump();
      await tester.pump();

      expect(fallback?.token, same(claim.token));
    },
  );

  testWidgets(
    'смена локализованного сообщения сохраняет renderer и его claim',
    (tester) async {
      final harness = _FailureHarness();
      addTearDown(harness.dispose);
      final claim = await harness.createClaim(index: 9);
      final message = ValueNotifier('The operation failed.');
      addTearDown(message.dispose);
      GraphAppPresentationClaim? fallback;
      unawaited(
        harness.registration.nextClaim().then((value) => fallback = value),
      );
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
      expect(harness.claimAgain(claim), same(claim));
      expect(fallback, isNull);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();

      expect(harness.claimAgain(claim), isNull);
      expect(fallback, isNull);
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
    GraphAppPresentationClaim? fallback;
    unawaited(
      harness.registration.nextClaim().then((value) => fallback = value),
    );

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
    expect(harness.claimAgain(claim), isNull);

    showError.value = false;
    await tester.pump();
    await tester.pump();

    expect(fallback, isNull);
  });

  testWidgets(
    'замена renderer освобождает прежний claim и не даёт старому callback подтвердить новый',
    (tester) async {
      final harness = _FailureHarness();
      addTearDown(harness.dispose);
      final first = await harness.createClaim(index: 5);
      final second = await harness.createClaim(index: 6);
      final current = ValueNotifier((claim: first, message: 'Первая ошибка'));
      addTearDown(current.dispose);
      GraphAppPresentationClaim? fallback;
      unawaited(
        harness.registration.nextClaim().then((value) => fallback = value),
      );
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

      expect(fallback?.token, same(first.token));
      expect(harness.claimAgain(second), same(second));

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();

      expect(harness.claimAgain(second), isNull);
    },
  );

  // Тексты по языкам проверяют тесты сообщений об отказе; здесь важна проводка
  // инлайн-отображения, поэтому достаточно русского.
  const scenario = (
    locale: Locale('ru'),
    failure: 'Этого намерения больше нет. Обновите подробности.',
    busy: 'Изменение назначения тега уже выполняется. Дождитесь результата.',
  );
  testWidgets(
    'инлайн-отказ назначения и занятость доступны для ${scenario.locale.languageCode}',
    (tester) async {
      final harness = _FailureHarness();
      addTearDown(harness.dispose);
      final claim = await harness.createAssignmentClaim();

      await tester.pumpWidget(
        harness.app(
          Builder(
            builder: (context) => Column(
              children: [
                OperationFailurePresentation(
                  claim: claim,
                  message: tagAssignmentFailureMessage(
                    AppLocalizations.of(context),
                    TagIntentionNotFoundFailure(testDetailsIntentionId(1)),
                  ),
                  messageKey: const ValueKey('assignment-failure-message'),
                ),
                OperationFailurePresentation(
                  claim: null,
                  message: tagAssignmentStartMessage(
                    AppLocalizations.of(context),
                    const TagCommandAlreadyRunning(),
                  )!,
                  messageKey: const ValueKey('assignment-busy-message'),
                ),
              ],
            ),
          ),
          locale: scenario.locale,
        ),
      );

      expect(find.text(scenario.failure), findsOneWidget);
      expect(find.text(scenario.busy), findsOneWidget);
      expect(
        tester.getSemantics(
          find.byKey(const ValueKey('assignment-failure-message')),
        ),
        matchesSemantics(
          label: scenario.failure,
          isLiveRegion: true,
          textDirection: TextDirection.ltr,
        ),
      );
      expect(harness.claimAgain(claim), isNull);
    },
  );

  testWidgets(
    'исчезнувшая до кадра форма передаёт отказ отсутствующих тегов общей поверхности тем же token',
    (tester) async {
      final harness = _FailureHarness();
      addTearDown(harness.dispose);
      final claim = await harness.createFullCreationTagsMissingClaim();
      final showError = ValueNotifier(true);
      addTearDown(showError.dispose);
      GraphAppPresentationClaim? fallback;
      unawaited(
        harness.registration.nextClaim().then((value) => fallback = value),
      );
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
      expect(harness.claimAgain(claim), same(claim));
      expect(fallback, isNull);

      showError.value = false;
      await tester.pump();
      await tester.pump();
      expect(fallback?.token, same(claim.token));
      expect(
        fallback?.completion,
        isA<IntentionCommandCompletion>()
            .having(
              (completion) => completion.kind,
              'вид операции',
              IntentionCommandKind.create,
            )
            .having(
              (completion) => completion.result,
              'исход',
              isA<ResultFailure<IntentionCommandSuccess>>().having(
                (result) => result.failure,
                'отказ',
                isA<IntentionCreationTagsMissingFailure>(),
              ),
            ),
      );

      // Возвращение фокуса не даёт кадру исчезнувшей формы подтвердить
      // право общей поверхности.
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(harness.claimAgain(claim), isNull);
      harness.registration.release();
      final replacement = harness.coordinator.registerAppPresentation();
      addTearDown(replacement.release);
      expect((await replacement.nextClaim())?.token, same(claim.token));
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
        GraphAppPresentationClaim? fallback;
        unawaited(
          harness.registration.nextClaim().then((value) => fallback = value),
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

        // Временное перекрытие подтверждением сохраняет право renderer.
        final claim = harness.container.read(provider).failurePresentation!;
        expect(find.text(_creationFailureMessage), findsOneWidget);
        expect(harness.claimAgain(claim), same(claim));
        expect(fallback, isNull);

        await tester.tap(find.text('Сбросить'));
        await tester.pumpAndSettle();

        expect(find.text(_savingContinuesWarning), findsNothing);
        expect(find.text('Закрыть'), findsOneWidget);
        expect(harness.claimAgain(claim), isNull);
        expect(fallback, isNull);
        expect(harness.container.read(provider).draft.title, 'Намерение');
      },
    );

    testWidgets(
      'сброс сессии до предъявления отказа передаёт его право общей поверхности тем же token',
      (tester) async {
        final harness = _FailureHarness();
        addTearDown(harness.dispose);
        final provider = intentionEditorViewModelProvider(
          IntentionCreationFormKey(),
        );
        GraphAppPresentationClaim? fallback;
        unawaited(
          harness.registration.nextClaim().then((value) => fallback = value),
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
        final claim = harness.container.read(provider).failurePresentation!;
        expect(harness.claimAgain(claim), same(claim));

        await tester.tap(find.text('Закрыть'));
        await tester.pumpAndSettle();
        expect(find.text(_draftLossWarning), findsOneWidget);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pumpAndSettle();

        // Подтверждение перекрывает живой renderer: право остаётся у него.
        expect(harness.claimAgain(claim), same(claim));
        expect(fallback, isNull);

        await tester.tap(find.text('Сбросить'));
        await tester.pumpAndSettle();

        expect(find.text('Закрыть'), findsNothing);
        expect(find.text(_creationFailureMessage), findsNothing);
        expect(fallback?.token, same(claim.token));
        expect(
          fallback?.completion,
          isA<IntentionCommandCompletion>().having(
            (completion) => completion.result,
            'исход',
            isA<ResultFailure<IntentionCommandSuccess>>().having(
              (result) => result.failure,
              'отказ',
              isA<IntentionUnavailableFailure>(),
            ),
          ),
        );
        expect(harness.claimAgain(claim), isNull);
        harness.coordinator.confirmPresentation(fallback!);
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
        final appSurface = _presentOnAppSurface(harness);
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

        // Перекрытая форма не построила отказ и не предъявила его, а общая
        // поверхность его не получила.
        final claim = harness.container.read(provider).failurePresentation!;
        expect(find.byType(TagCatalogView), findsOneWidget);
        expect(
          find.text(_creationFailureMessage, skipOffstage: false),
          findsNothing,
        );
        expect(harness.claimAgain(claim), same(claim));
        expect(appSurface, isEmpty);

        await tester.tap(find.byType(BackButton));
        await tester.pumpAndSettle();

        expect(find.byType(TagCatalogView), findsNothing);
        expect(find.text(_creationFailureMessage), findsOneWidget);
        expect(harness.claimAgain(claim), isNull);
        expect(appSurface, isEmpty);
        expect(harness.repository.commands, hasLength(1));
      },
    );

    for (final removal in _HostRemoval.values) {
      testWidgets(
        'удаление хоста под выбором тегов без возвращения (${removal.description}) передаёт отказ общей поверхности ровно один раз',
        (tester) async {
          final harness = _FailureHarness();
          addTearDown(harness.dispose);
          final formKey = IntentionCreationFormKey();
          final provider = intentionEditorViewModelProvider(formKey);
          final appSurface = _presentOnAppSurface(harness);
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
          // Renderer перекрытого хоста право не получал.
          final claim = harness.container.read(provider).failurePresentation!;
          expect(
            find.text(_creationFailureMessage, skipOffstage: false),
            findsNothing,
          );
          expect(harness.claimAgain(claim), same(claim));
          expect(appSurface, isEmpty);

          removal.apply(
            Navigator.of(tester.element(find.byType(TagCatalogView))),
          );
          await tester.pumpAndSettle();

          expect(find.byType(TagCatalogView), findsNothing);
          expect(find.text('Закрыть'), findsNothing);
          expect(find.text(_creationFailureMessage), findsNothing);
          expect(appSurface.map((claim) => claim.completion), [
            isA<IntentionCommandCompletion>()
                .having(
                  (completion) => completion.token,
                  'token',
                  same(claim.token),
                )
                .having(
                  (completion) => completion.result,
                  'исход',
                  isA<ResultFailure<IntentionCommandSuccess>>().having(
                    (result) => result.failure,
                    'отказ',
                    isA<IntentionUnavailableFailure>(),
                  ),
                ),
          ]);
          // Запись координатора не остаётся: право больше никому не выдаётся.
          expect(harness.claimAgain(claim), isNull);
          expect(harness.coordinator.isKeyRunning(formKey), isFalse);
          expect(harness.repository.commands, hasLength(1));
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

/// Общая поверхность приложения: получает права по очереди и сразу
/// подтверждает каждое предъявление; возвращает предъявленные права.
List<GraphAppPresentationClaim> _presentOnAppSurface(_FailureHarness harness) {
  final presented = <GraphAppPresentationClaim>[];
  void requestNext() => unawaited(
    harness.registration.nextClaim().then((claim) {
      if (claim == null) {
        return;
      }
      presented.add(claim);
      harness.coordinator.confirmPresentation(claim);
      requestNext();
    }),
  );
  requestNext();
  return presented;
}

/// Открывает существующую страницу выбора тегов с контекстом черновика
/// сессии непрозрачным маршрутом поверх её хоста.
Future<void> _openTagChooser(WidgetTester tester) async {
  await tester.tap(find.text('Теги'));
  await tester.pumpAndSettle();
}

const _creationFailureMessage = 'Не удалось создать намерение';
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
  _FailureHarness._(this.repository, this.container) {
    registration = coordinator.registerAppPresentation();
  }

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
  late final GraphAppPresentationRegistration registration;

  GraphCommandCoordinator get coordinator =>
      container.read(graphCommandCoordinatorProvider.notifier);

  Future<GraphInitiatorPresentationClaim> createClaim({
    required int index,
  }) async {
    final intention = testDetailsIntention(index: index);
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
        favoriteMark: FavoriteMark.favorite,
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

  Future<GraphInitiatorPresentationClaim> createAssignmentClaim() async {
    final tagId = switch (TagId.decode(
      '018f1400-0000-7000-8000-000000000003',
    )) {
      TagIdDecodingSuccess(:final id) => id,
      InvalidTagIdDecoding() => throw StateError('Некорректный ID тега.'),
    };
    final intentionId = testDetailsIntentionId(1);
    final accepted = coordinator.acceptTagAssign(
      AssignTag(tagId: tagId, intentionId: intentionId),
    ) as TagCommandAccepted;
    repository.completeTagCommand(
      repository.tagCommands.length - 1,
      TagCommandFailed(TagIntentionNotFoundFailure(intentionId)),
    );
    await accepted.future;
    return coordinator.claimInitiatorFailure(accepted.token)!;
  }

  GraphInitiatorPresentationClaim? claimAgain(
    GraphInitiatorPresentationClaim claim,
  ) => coordinator.claimInitiatorFailure(claim.token);

  Widget app(Widget body, {Locale locale = const Locale('en')}) =>
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          locale: locale,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: body),
        ),
      );

  void dispose() {
    registration.release();
    container.dispose();
  }
}
