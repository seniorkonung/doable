import 'dart:async';

import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/src/daily_choice/application/confirmed_choice_path.dart';
import 'package:doable/src/daily_choice/application/daily_choice_command.dart';
import 'package:doable/src/daily_choice/application/daily_choice_result.dart';
import 'package:doable/src/daily_choice/domain/calendar_date.dart';
import 'package:doable/src/daily_choice/domain/daily_choice_id.dart';
import 'package:doable/src/daily_choice/presentation/daily_choice_command_failure_message.dart';
import 'package:doable/src/graph/application/delete_blocking_relations.dart';
import 'package:doable/src/graph/application/graph_command_coordinator.dart';
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:doable/src/graph/presentation/operation_failure_presentation.dart';
import 'package:doable/src/intention/application/intention_command.dart';
import 'package:doable/src/intention/application/intention_result.dart';
import 'package:doable/src/long_term_relation/application/long_term_relation_command.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation_id.dart';
import 'package:doable/src/tag/application/tag_command.dart';
import 'package:doable/src/tag/application/tag_result.dart';
import 'package:doable/src/tag/domain/tag_name.dart';
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

  testWidgets('удерживает claim при временной прозрачности renderer', (
    tester,
  ) async {
    final harness = _FailureHarness();
    addTearDown(harness.dispose);
    final claim = await harness.createClaim(index: 3);
    final opacity = ValueNotifier(0.0);
    addTearDown(opacity.dispose);

    await tester.pumpWidget(
      harness.app(
        ValueListenableBuilder<double>(
          valueListenable: opacity,
          builder: (context, value, _) => Opacity(
            opacity: value,
            child: OperationFailurePresentation(
              claim: claim,
              message: 'Временно скрытая ошибка',
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(harness.claimAgain(claim), same(claim));

    opacity.value = 1;
    await tester.pump();

    expect(harness.claimAgain(claim), isNull);
  });

  testWidgets('не подтверждает claim без фокуса до возвращения в resumed', (
    tester,
  ) async {
    final harness = _FailureHarness();
    addTearDown(harness.dispose);
    final claim = await harness.createClaim(index: 4);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);

    await tester.pumpWidget(
      harness.app(
        OperationFailurePresentation(claim: claim, message: 'Ошибка'),
      ),
    );
    await tester.pump();

    expect(harness.claimAgain(claim), same(claim));

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();

    expect(harness.claimAgain(claim), isNull);
  });

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

  testWidgets('удерживает renderer на скрытом маршруте до его возвращения', (
    tester,
  ) async {
    final harness = _FailureHarness();
    addTearDown(harness.dispose);
    final claim = await harness.createClaim(index: 7);
    final currentClaim = ValueNotifier<GraphInitiatorPresentationClaim?>(null);
    addTearDown(currentClaim.dispose);

    await tester.pumpWidget(
      harness.app(
        Builder(
          builder: (context) => Column(
            children: [
              TextButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => const AlertDialog(content: Text('Диалог')),
                ),
                child: const Text('Открыть диалог'),
              ),
              ValueListenableBuilder<GraphInitiatorPresentationClaim?>(
                valueListenable: currentClaim,
                builder: (context, value, _) => OperationFailurePresentation(
                  claim: value,
                  message: 'Ошибка под диалогом',
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.tap(find.text('Открыть диалог'));
    await tester.pumpAndSettle();

    currentClaim.value = claim;
    await tester.pumpAndSettle();
    expect(harness.claimAgain(claim), same(claim));

    await tester.tapAt(const Offset(8, 8));
    await tester.pumpAndSettle();

    expect(find.text('Диалог'), findsNothing);
    expect(harness.claimAgain(claim), isNull);
  });

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

  testWidgets(
    'ошибка создания связи подтверждается кадром своего инлайн-renderer',
    (tester) async {
      final harness = _FailureHarness();
      addTearDown(harness.dispose);
      final claim = await harness.createRelationClaim();

      await tester.pumpWidget(
        harness.app(
          OperationFailurePresentation(
            claim: claim,
            message: 'Не удалось создать связь',
            messageKey: const ValueKey('relation-failure-message'),
          ),
        ),
      );

      expect(
        tester.getSemantics(
          find.byKey(const ValueKey('relation-failure-message')),
        ),
        matchesSemantics(
          label: 'Не удалось создать связь',
          isLiveRegion: true,
          textDirection: TextDirection.ltr,
        ),
      );
      expect(harness.claimAgain(claim), isNull);
    },
  );

  testWidgets(
    'исчезновение renderer связи до кадра передаёт результат оболочке',
    (tester) async {
      final harness = _FailureHarness();
      addTearDown(harness.dispose);
      final claim = await harness.createRelationClaim();
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
                    message: 'Не удалось создать связь',
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
        isA<LongTermRelationCommandCompletion>().having(
          (completion) => completion.kind,
          'вид операции',
          LongTermRelationCommandKind.create,
        ),
      );
    },
  );

  for (final scenario in <({Locale locale, String message})>[
    (locale: const Locale('en'), message: 'Enter a tag name.'),
    (locale: const Locale('ru'), message: 'Введите название тега.'),
  ]) {
    testWidgets(
      'ошибка тега предъявляется своим инлайн-сообщением для ${scenario.locale.languageCode}',
      (tester) async {
        final harness = _FailureHarness();
        addTearDown(harness.dispose);
        final claim = await harness.createTagClaim();

        await tester.pumpWidget(
          harness.app(
            Builder(
              builder: (context) => OperationFailurePresentation(
                claim: claim,
                message: tagFailureMessage(
                  AppLocalizations.of(context),
                  const TagNameInputFailure(TagNameFailureReason.empty),
                ),
                messageKey: const ValueKey('tag-failure-message'),
              ),
            ),
            locale: scenario.locale,
          ),
        );

        expect(find.text(scenario.message), findsOneWidget);
        expect(
          tester.getSemantics(
            find.byKey(const ValueKey('tag-failure-message')),
          ),
          matchesSemantics(
            label: scenario.message,
            isLiveRegion: true,
            textDirection: TextDirection.ltr,
          ),
        );
        expect(harness.claimAgain(claim), isNull);
      },
    );
  }

  testWidgets(
    'исчезнувшая до кадра ошибка тега передаёт право общей поверхности',
    (tester) async {
      final harness = _FailureHarness();
      addTearDown(harness.dispose);
      final claim = await harness.createTagClaim();
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
                    message: 'Введите название тега.',
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
      expect(fallback?.completion, isA<TagCommandCompletion>());
    },
  );

  testWidgets('массовый отказ подтверждается кадром инлайн-renderer', (
    tester,
  ) async {
    final harness = _FailureHarness();
    addTearDown(harness.dispose);
    final claim = await harness.createBlockingRelationsClaim();

    await tester.pumpWidget(
      harness.app(
        OperationFailurePresentation(
          claim: claim,
          message: 'Выбранные связи не удалены',
          messageKey: const ValueKey('blocking-relations-failure-message'),
        ),
      ),
    );

    expect(
      tester.getSemantics(
        find.byKey(const ValueKey('blocking-relations-failure-message')),
      ),
      matchesSemantics(
        label: 'Выбранные связи не удалены',
        isLiveRegion: true,
        textDirection: TextDirection.ltr,
      ),
    );
    expect(harness.claimAgain(claim), isNull);
  });

  testWidgets(
    'исчезновение массовой инлайн-ошибки до кадра передаёт тот же token оболочке',
    (tester) async {
      final harness = _FailureHarness();
      addTearDown(harness.dispose);
      final claim = await harness.createBlockingRelationsClaim();
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
                    message: 'Выбранные связи не удалены',
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
      expect(fallback?.completion, isA<BlockingRelationsDeleteCompletion>());
    },
  );

  for (final scenario in <({Locale locale, String message})>[
    (locale: const Locale('en'), message: 'Check the daily choice date.'),
    (locale: const Locale('ru'), message: 'Проверьте дату дневного выбора.'),
  ]) {
    testWidgets(
      'дневная ошибка поля доступна локально для ${scenario.locale.languageCode}',
      (tester) async {
        final harness = _FailureHarness();
        addTearDown(harness.dispose);
        final claim = await harness.createDailyChoiceClaim();

        await tester.pumpWidget(
          harness.app(
            Builder(
              builder: (context) => OperationFailurePresentation(
                claim: claim,
                message: dailyChoiceCommandFailureMessage(
                  AppLocalizations.of(context),
                  const DailyChoiceValidationFailure(
                    DailyChoiceValidationField.date,
                  ),
                ),
                messageKey: const ValueKey('daily-choice-failure-message'),
              ),
            ),
            locale: scenario.locale,
          ),
        );

        expect(find.text(scenario.message), findsOneWidget);
        expect(
          tester.getSemantics(
            find.byKey(const ValueKey('daily-choice-failure-message')),
          ),
          matchesSemantics(
            label: scenario.message,
            isLiveRegion: true,
            textDirection: TextDirection.ltr,
          ),
        );
        expect(harness.claimAgain(claim), isNull);
      },
    );
  }

  testWidgets(
    'исчезнувшая дневная ошибка передаётся оболочке после потери фокуса',
    (tester) async {
      final harness = _FailureHarness();
      addTearDown(harness.dispose);
      final claim = await harness.createDailyChoiceClaim();
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
                    message: 'Проверьте дату дневного выбора.',
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
      expect(fallback?.completion, isA<DailyChoiceCommandCompletion>());
    },
  );

  testWidgets(
    'запоздалый кадр ошибки повтора не подтверждает заменившую её ошибку замены',
    (tester) async {
      final harness = _FailureHarness();
      addTearDown(harness.dispose);
      final repeatClaim = await harness.createDailyPathClaim(replace: false);
      final replacementClaim = await harness.createDailyPathClaim(
        replace: true,
      );
      final current = ValueNotifier((
        claim: repeatClaim,
        message: 'Не удалось повторить маршрут',
      ));
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
      expect(harness.claimAgain(repeatClaim), same(repeatClaim));

      current.value = (
        claim: replacementClaim,
        message: 'Не удалось заменить путь',
      );
      await tester.pump();
      await tester.pump();
      expect(fallback?.token, same(repeatClaim.token));
      expect(harness.claimAgain(replacementClaim), same(replacementClaim));

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(harness.claimAgain(replacementClaim), isNull);
      expect(fallback?.token, same(repeatClaim.token));
    },
  );
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

  Future<GraphInitiatorPresentationClaim> createRelationClaim() async {
    final accepted = coordinator.acceptRelationCreation(
      LongTermRelationCreationFormKey(),
      CreateLongTermRelation(
        sourceIntentionId: testDetailsIntentionId(1),
        relatedIntentionId: testDetailsIntentionId(2),
        type: LongTermRelationType.need,
        priority: RelationPriority.p1,
        description: null,
      ),
    ) as LongTermRelationCommandAccepted;
    repository.completeRelationCommand(
      repository.relationCommands.length - 1,
      const GraphCommandFailed<
        LongTermRelationCommandSuccess,
        LongTermRelationCommandFailure
      >(LongTermRelationUnavailableFailure()),
    );
    await accepted.future;
    return coordinator.claimInitiatorFailure(accepted.token)!;
  }

  Future<GraphInitiatorPresentationClaim> createTagClaim() async {
    final accepted = coordinator.acceptTagCreation(
      TagCreationFormKey(),
      CreateTag(TagName.fromInput('Планы')),
    ) as TagCommandAccepted;
    repository.completeTagCommand(
      repository.tagCommands.length - 1,
      const TagCommandFailed(TagNameInputFailure(TagNameFailureReason.empty)),
    );
    await accepted.future;
    return coordinator.claimInitiatorFailure(accepted.token)!;
  }

  Future<GraphInitiatorPresentationClaim> createBlockingRelationsClaim() async {
    final relationId = switch (LongTermRelationId.decode(
      '018f47c2-6b7d-7abc-8def-0123456789ab',
    )) {
      LongTermRelationIdDecodingSuccess(:final id) => id,
      InvalidLongTermRelationIdDecoding() => throw StateError(
        'Некорректный fixture связи.',
      ),
    };
    final accepted = coordinator.acceptBlockingRelationsDelete(
      DeleteBlockingRelations.longTerm(
        intentionId: testDetailsIntentionId(1),
        relationIds: {relationId},
      ),
      presentationTitle: 'Намерение',
    ) as BlockingRelationsDeleteAccepted;
    repository.completeBlockingRelationsCommand(
      repository.blockingRelationsCommands.length - 1,
      const GraphCommandFailed<
        BlockingRelationsDeleted,
        DeleteBlockingRelationsFailure
      >(DeleteBlockingRelationsUnavailableFailure()),
    );
    await accepted.future;
    return coordinator.claimInitiatorFailure(accepted.token)!;
  }

  Future<GraphInitiatorPresentationClaim> createDailyChoiceClaim() async {
    final choiceId = switch (DailyChoiceId.decode(
      '018f1400-0000-7000-8000-000000000001',
    )) {
      DailyChoiceIdDecodingSuccess(:final id) => id,
      InvalidDailyChoiceIdDecoding() => throw StateError(
        'Некорректный ID дневного выбора.',
      ),
    };
    final accepted = coordinator.acceptDailyChoiceUpdate(
      UpdateDailyChoiceFields(
        choiceId: choiceId,
        patch: const DailyChoiceFieldsPatch(
          isCompleted: DailyChoiceFieldSet(true),
        ),
      ),
    ) as DailyChoiceCommandAccepted;
    repository.completeDailyChoiceCommand(
      repository.dailyChoiceCommands.length - 1,
      const GraphCommandFailed<
        DailyChoiceCommandSuccess,
        DailyChoiceCommandFailure
      >(DailyChoiceValidationFailure(DailyChoiceValidationField.date)),
    );
    await accepted.future;
    return coordinator.claimInitiatorFailure(accepted.token)!;
  }

  Future<GraphInitiatorPresentationClaim> createDailyPathClaim({
    required bool replace,
  }) async {
    final relationId = switch (LongTermRelationId.decode(
      '018f47c2-6b7d-7abc-8def-0123456789ab',
    )) {
      LongTermRelationIdDecodingSuccess(:final id) => id,
      InvalidLongTermRelationIdDecoding() => throw StateError(
        'Некорректный ID связи.',
      ),
    };
    final choiceId = switch (DailyChoiceId.decode(
      '018f1400-0000-7000-8000-000000000001',
    )) {
      DailyChoiceIdDecodingSuccess(:final id) => id,
      InvalidDailyChoiceIdDecoding() => throw StateError(
        'Некорректный ID дневного выбора.',
      ),
    };
    final path = ConfirmedChoicePath([
      ConfirmedChoicePathStep(
        relationId: relationId,
        sourceIntentionId: testDetailsIntentionId(1),
        type: LongTermRelationType.need,
        relatedIntentionId: testDetailsIntentionId(2),
      ),
    ]);
    final accepted = replace
        ? coordinator.acceptDailyChoiceReplace(
            ReplaceDailyChoicePath(
              choiceId: choiceId,
              sourceIntentionId: testDetailsIntentionId(1),
              selectedIntentionId: testDetailsIntentionId(2),
              path: path,
            ),
          )
        : coordinator.acceptDailyChoiceCreation(
            DailyChoiceCreationFormKey(),
            CreateDailyChoice(
              sourceIntentionId: testDetailsIntentionId(1),
              selectedIntentionId: testDetailsIntentionId(2),
              path: path,
              date: CalendarDate.fromParts(2026, 9, 25),
              description: null,
              isCompleted: false,
            ),
          );
    final token = (accepted as DailyChoiceCommandAccepted).token;
    repository.completeDailyChoiceCommand(
      repository.dailyChoiceCommands.length - 1,
      GraphCommandFailed<DailyChoiceCommandSuccess, DailyChoiceCommandFailure>(
        replace
            ? const DailyChoiceConflictFailure(
                DailyChoiceConflictReason.dependencyChanged,
              )
            : const DailyChoiceUnavailableFailure(),
      ),
    );
    await accepted.future;
    return coordinator.claimInitiatorFailure(token)!;
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
