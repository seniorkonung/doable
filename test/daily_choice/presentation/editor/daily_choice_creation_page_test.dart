import 'dart:async';

import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/src/daily_choice/application/confirmed_choice_path.dart';
import 'package:doable/src/daily_choice/application/choice_path_draft.dart';
import 'package:doable/src/daily_choice/application/daily_choice_command.dart';
import 'package:doable/src/daily_choice/application/daily_choice_result.dart';
import 'package:doable/src/daily_choice/domain/calendar_date.dart';
import 'package:doable/src/daily_choice/domain/choice_path_step_id.dart';
import 'package:doable/src/daily_choice/domain/daily_choice.dart';
import 'package:doable/src/daily_choice/domain/daily_choice_id.dart';
import 'package:doable/src/daily_choice/presentation/editor/daily_choice_creation_page.dart';
import 'package:doable/src/daily_choice/presentation/path/choice_path_page.dart';
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/application/personal_graph_repository.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:doable/src/graph/presentation/graph_operation_presenter.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/long_term_relation/application/long_term_relation_projection.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation_id.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() {
    WidgetsBinding.instance.handleAppLifecycleStateChanged(
      AppLifecycleState.resumed,
    );
  });

  testWidgets(
    'успех предъявляется после результата команды, затем форма закрывается',
    (tester) async {
      final repository = _Repository();
      final navigatorKey = GlobalKey<NavigatorState>();
      await _pump(tester, repository, navigatorKey: navigatorKey);
      await tester.ensureVisible(
        find.byKey(const ValueKey('daily-choice-submit')),
      );
      await tester.tap(find.byKey(const ValueKey('daily-choice-submit')));
      await tester.pump();
      expect(find.byKey(const ValueKey('daily-choice-date')), findsOneWidget);
      expect(find.text('Домашний экран'), findsNothing);
      expect(repository.commands, hasLength(1));
      repository.succeed(0);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('daily-choice-date')), findsNothing);
      expect(find.text('Домашний экран'), findsOneWidget);
      expect(find.textContaining('Дневной выбор создан'), findsOneWidget);
    },
  );

  testWidgets('результат после ухода формы предъявляет оболочка', (
    tester,
  ) async {
    final repository = _Repository();
    final navigatorKey = GlobalKey<NavigatorState>();
    await _pump(tester, repository, navigatorKey: navigatorKey);
    await tester.ensureVisible(
      find.byKey(const ValueKey('daily-choice-submit')),
    );
    await tester.tap(find.byKey(const ValueKey('daily-choice-submit')));
    await tester.pump();
    navigatorKey.currentState!.pop();
    await tester.pumpAndSettle();
    expect(find.text('Домашний экран'), findsOneWidget);
    repository.succeed(0);
    await tester.pumpAndSettle();
    expect(find.textContaining('Дневной выбор создан'), findsOneWidget);
  });

  testWidgets('поздний результат ждёт возвращения фокуса', (tester) async {
    final repository = _Repository();
    final navigatorKey = GlobalKey<NavigatorState>();
    await _pump(tester, repository, navigatorKey: navigatorKey);
    await tester.ensureVisible(
      find.byKey(const ValueKey('daily-choice-submit')),
    );
    await tester.tap(find.byKey(const ValueKey('daily-choice-submit')));
    await tester.pump();
    WidgetsBinding.instance.handleAppLifecycleStateChanged(
      AppLifecycleState.inactive,
    );
    repository.succeed(0);
    await tester.pumpAndSettle();
    expect(find.textContaining('Дневной выбор создан'), findsNothing);
    WidgetsBinding.instance.handleAppLifecycleStateChanged(
      AppLifecycleState.resumed,
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Дневной выбор создан'), findsOneWidget);
  });

  testWidgets(
    'крупный текст и английская семантика сохраняют пользовательские названия',
    (tester) async {
      final repository = _Repository();
      await _pump(tester, repository, locale: const Locale('en'), textScale: 2);
      final semantics = tester.ensureSemantics();
      expect(find.textContaining('Основание'), findsWidgets);
      expect(find.textContaining('Действие'), findsWidgets);
      expect(find.bySemanticsLabel(RegExp('Step 1:')), findsOneWidget);
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('daily-choice-completed')),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Already completed'), findsOneWidget);
      semantics.dispose();
    },
  );

  testWidgets('ошибка поля показана в форме без потери ввода', (tester) async {
    final repository = _Repository();
    await _pump(tester, repository);
    await tester.enterText(
      find.byKey(const ValueKey('daily-choice-description')),
      'Сохранить меня',
    );
    await tester.ensureVisible(
      find.byKey(const ValueKey('daily-choice-submit')),
    );
    await tester.tap(find.byKey(const ValueKey('daily-choice-submit')));
    await tester.pump();
    repository.fail(
      0,
      const DailyChoiceValidationFailure(
        DailyChoiceValidationField.description,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Сохранить меня'), findsOneWidget);
    expect(find.textContaining('Проверьте описание'), findsWidgets);
    expect(find.byKey(const ValueKey('daily-choice-failure')), findsOneWidget);
    expect(find.byKey(const ValueKey('daily-choice-submit')), findsOneWidget);
  });

  testWidgets('описание блокируется при записи и обновляется перед повтором', (
    tester,
  ) async {
    final repository = _Repository();
    final navigatorKey = GlobalKey<NavigatorState>();
    await _pump(tester, repository, navigatorKey: navigatorKey);
    const descriptionKey = ValueKey('daily-choice-description');
    const submitKey = ValueKey('daily-choice-submit');

    await tester.enterText(find.byKey(descriptionKey), 'Первый текст');
    await tester.ensureVisible(find.byKey(submitKey));
    await tester.tap(find.byKey(submitKey));
    await tester.pump();

    expect(repository.commands, hasLength(1));
    expect(repository.commands.single.description?.value, 'Первый текст');
    expect(
      tester.widget<TextField>(find.byKey(descriptionKey)).enabled,
      isFalse,
    );
    expect(
      tester.widget<TextField>(find.byKey(descriptionKey)).controller!.text,
      'Первый текст',
    );
    expect(
      tester.widget<FilledButton>(find.byKey(submitKey)).onPressed,
      isNull,
    );

    repository.fail(0, const DailyChoiceUnavailableFailure());
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byKey(descriptionKey)).enabled,
      isTrue,
    );
    expect(
      tester.widget<TextField>(find.byKey(descriptionKey)).controller!.text,
      'Первый текст',
    );

    await tester.enterText(find.byKey(descriptionKey), 'Исправленный текст');
    await tester.ensureVisible(find.byKey(submitKey));
    await tester.tap(find.byKey(submitKey));
    await tester.pump();
    expect(repository.commands, hasLength(2));
    expect(repository.commands.last.description?.value, 'Исправленный текст');
    expect(
      tester.widget<TextField>(find.byKey(descriptionKey)).enabled,
      isFalse,
    );
    repository.succeed(1);
    await tester.pumpAndSettle();
    expect(find.text('Домашний экран'), findsOneWidget);
    expect(find.textContaining('Дневной выбор создан'), findsOneWidget);
  });

  testWidgets('подтверждение явно сохраняет показанный путь и поля', (
    tester,
  ) async {
    final repository = _Repository();
    await _pump(tester, repository);
    expect(repository.commands, isEmpty);
    expect(find.textContaining('Основание'), findsWidgets);
    expect(find.textContaining('Действие'), findsWidgets);
    await tester.enterText(
      find.byKey(const ValueKey('daily-choice-date')),
      '0001-01-01',
    );
    await tester.enterText(
      find.byKey(const ValueKey('daily-choice-description')),
      'Мой текст',
    );
    await tester.tap(find.byKey(const ValueKey('daily-choice-completed')));
    await tester.ensureVisible(
      find.byKey(const ValueKey('daily-choice-submit')),
    );
    await tester.tap(find.byKey(const ValueKey('daily-choice-submit')));
    await tester.pump();
    expect(repository.commands, hasLength(1));
    expect(repository.commands.single.date, CalendarDate.fromParts(1, 1, 1));
    expect(repository.commands.single.description?.value, 'Мой текст');
    expect(repository.commands.single.isCompleted, isTrue);
    expect(repository.commands.single.path.steps.length, 1);
  });

  testWidgets('неверную дату и описание можно исправить без потери ввода', (
    tester,
  ) async {
    final repository = _Repository();
    await _pump(tester, repository, locale: const Locale('en'));
    await tester.enterText(
      find.byKey(const ValueKey('daily-choice-date')),
      '9999-02-30',
    );
    await tester.ensureVisible(
      find.byKey(const ValueKey('daily-choice-submit')),
    );
    await tester.tap(find.byKey(const ValueKey('daily-choice-submit')));
    await tester.pump();
    expect(repository.commands, isEmpty);
    await tester.enterText(
      find.byKey(const ValueKey('daily-choice-date')),
      '9999-12-31',
    );
    await tester.enterText(
      find.byKey(const ValueKey('daily-choice-description')),
      'x' * 4097,
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const ValueKey('daily-choice-submit')),
    );
    await tester.tap(find.byKey(const ValueKey('daily-choice-submit')));
    await tester.pump();
    expect(repository.commands, isEmpty);
    expect(find.text('x' * 4097), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('daily-choice-description')),
      'corrected',
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const ValueKey('daily-choice-submit')),
    );
    await tester.tap(find.byKey(const ValueKey('daily-choice-submit')));
    await tester.pump();
    expect(
      repository.commands.single.date,
      CalendarDate.fromParts(9999, 12, 31),
    );
    expect(repository.commands.single.description?.value, 'corrected');
  });

  testWidgets(
    'нижняя актуализация начинается от прежнего действия и сохраняет поля',
    (tester) async {
      final repository = _Repository();
      final navigatorKey = GlobalKey<NavigatorState>();
      final observer = _RouteObserver();
      await _pump(
        tester,
        repository,
        navigatorKey: navigatorKey,
        navigatorObserver: observer,
        direction: ChoicePathDraftDirection.bottomUp,
      );
      await tester.enterText(
        find.byKey(const ValueKey('daily-choice-date')),
        '2026-09-25',
      );
      await tester.enterText(
        find.byKey(const ValueKey('daily-choice-description')),
        'Прежнее описание',
      );
      await tester.tap(find.byKey(const ValueKey('daily-choice-completed')));
      await tester.ensureVisible(
        find.byKey(const ValueKey('daily-choice-submit')),
      );
      await tester.tap(find.byKey(const ValueKey('daily-choice-submit')));
      await tester.pump();
      repository.fail(
        0,
        const DailyChoiceConflictFailure(
          DailyChoiceConflictReason.confirmedPathChanged,
        ),
      );
      await tester.pumpAndSettle();

      await tester.ensureVisible(
        find.text('Вернуться к пути и актуализировать его'),
      );
      await tester.tap(find.text('Вернуться к пути и актуализировать его'));
      await tester.pumpAndSettle();
      final refreshPage = tester.widget<ChoicePathPage>(
        find.byType(ChoicePathPage),
      );
      expect(refreshPage.direction, ChoicePathDraftDirection.bottomUp);
      expect(refreshPage.sourceIntentionId, _intention(2));
      expect(repository.commands, hasLength(1));

      navigatorKey.currentState!.removeRoute(observer.routes.last);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('daily-choice-date')))
            .controller!
            .text,
        '2026-09-25',
      );
      expect(
        tester
            .widget<TextField>(
              find.byKey(const ValueKey('daily-choice-description')),
            )
            .controller!
            .text,
        'Прежнее описание',
      );
      expect(
        tester
            .widget<SwitchListTile>(
              find.byKey(const ValueKey('daily-choice-completed')),
            )
            .value,
        isTrue,
      );
      expect(repository.commands, hasLength(1));
    },
  );

  for (final olderFirst in [true, false]) {
    testWidgets(
      'два результата актуализации в порядке ${olderFirst ? 'старый–новый' : 'новый–старый'} показывают отправляемый путь',
      (tester) async {
        final repository = _Repository();
        final navigatorKey = GlobalKey<NavigatorState>();
        final observer = _RouteObserver();
        await _pump(
          tester,
          repository,
          navigatorKey: navigatorKey,
          navigatorObserver: observer,
        );
        await tester.enterText(
          find.byKey(const ValueKey('daily-choice-date')),
          '2026-09-25',
        );
        await tester.enterText(
          find.byKey(const ValueKey('daily-choice-description')),
          'Сохранённое описание',
        );
        await tester.tap(find.byKey(const ValueKey('daily-choice-completed')));
        await tester.ensureVisible(
          find.byKey(const ValueKey('daily-choice-submit')),
        );
        await tester.tap(find.byKey(const ValueKey('daily-choice-submit')));
        await tester.pump();
        repository.fail(
          0,
          const DailyChoiceConflictFailure(
            DailyChoiceConflictReason.confirmedPathChanged,
          ),
        );
        await tester.pumpAndSettle();

        final refresh = tester.widget<TextButton>(
          find.widgetWithText(
            TextButton,
            'Вернуться к пути и актуализировать его',
          ),
        );
        refresh.onPressed!();
        final olderRoute = observer.routes.last;
        refresh.onPressed!();
        final newerRoute = observer.routes.last;
        await tester.pumpAndSettle();

        final older = _selection(2, 3, 'Старое действие');
        final newer = _selection(3, 4, 'Новое действие');
        if (olderFirst) {
          navigatorKey.currentState!.removeRoute(olderRoute, older);
          await tester.pumpAndSettle();
          navigatorKey.currentState!.removeRoute(newerRoute, newer);
        } else {
          navigatorKey.currentState!.removeRoute(newerRoute, newer);
          await tester.pumpAndSettle();
          navigatorKey.currentState!.removeRoute(olderRoute, older);
        }
        await tester.pumpAndSettle();

        expect(find.textContaining('Новое действие'), findsWidgets);
        expect(find.textContaining('Старое действие'), findsNothing);
        expect(repository.commands, hasLength(1));
        await tester.ensureVisible(
          find.byKey(const ValueKey('daily-choice-submit')),
        );
        await tester.tap(find.byKey(const ValueKey('daily-choice-submit')));
        await tester.pump();
        expect(repository.commands, hasLength(2));
        expect(repository.commands.last.path, same(newer.path));
        expect(
          repository.commands.last.date,
          CalendarDate.fromParts(2026, 9, 25),
        );
        expect(
          repository.commands.last.description?.value,
          'Сохранённое описание',
        );
        expect(repository.commands.last.isCompleted, isTrue);

        repository.fail(
          1,
          const DailyChoiceConflictFailure(
            DailyChoiceConflictReason.confirmedPathChanged,
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.text('Вернуться к пути и актуализировать его'),
          findsOneWidget,
        );
        expect(
          tester
              .widget<FilledButton>(
                find.byKey(const ValueKey('daily-choice-submit')),
              )
              .onPressed,
          isNull,
        );
        expect(repository.commands, hasLength(2));
        expect(find.textContaining('Дневной выбор создан'), findsNothing);
      },
    );
  }

  for (final olderFirst in [true, false]) {
    testWidgets(
      'нижняя актуализация в порядке ${olderFirst ? 'старый–новый' : 'новый–старый'} принимает только последнее основание',
      (tester) async {
        final repository = _Repository();
        final navigatorKey = GlobalKey<NavigatorState>();
        final observer = _RouteObserver();
        await _pump(
          tester,
          repository,
          navigatorKey: navigatorKey,
          navigatorObserver: observer,
          direction: ChoicePathDraftDirection.bottomUp,
        );
        await tester.enterText(
          find.byKey(const ValueKey('daily-choice-date')),
          '2026-09-25',
        );
        await tester.enterText(
          find.byKey(const ValueKey('daily-choice-description')),
          'Сохранённое описание',
        );
        await tester.tap(find.byKey(const ValueKey('daily-choice-completed')));
        await tester.ensureVisible(
          find.byKey(const ValueKey('daily-choice-submit')),
        );
        await tester.tap(find.byKey(const ValueKey('daily-choice-submit')));
        await tester.pump();
        repository.fail(
          0,
          const DailyChoiceConflictFailure(
            DailyChoiceConflictReason.confirmedPathChanged,
          ),
        );
        await tester.pumpAndSettle();
        final refresh = tester.widget<TextButton>(
          find.widgetWithText(
            TextButton,
            'Вернуться к пути и актуализировать его',
          ),
        );
        refresh.onPressed!();
        final olderRoute = observer.routes.last;
        refresh.onPressed!();
        final newerRoute = observer.routes.last;
        await tester.pumpAndSettle();

        final older = _bottomSelection(2, 3, 'Старое основание');
        final newer = _bottomSelection(3, 4, 'Новое основание');
        if (olderFirst) {
          navigatorKey.currentState!.removeRoute(olderRoute, older);
          await tester.pumpAndSettle();
          navigatorKey.currentState!.removeRoute(newerRoute, newer);
        } else {
          navigatorKey.currentState!.removeRoute(newerRoute, newer);
          await tester.pumpAndSettle();
          navigatorKey.currentState!.removeRoute(olderRoute, older);
        }
        await tester.pumpAndSettle();

        expect(find.textContaining('Новое основание'), findsWidgets);
        expect(find.textContaining('Старое основание'), findsNothing);
        expect(repository.commands, hasLength(1));
        await tester.ensureVisible(
          find.byKey(const ValueKey('daily-choice-submit')),
        );
        await tester.tap(find.byKey(const ValueKey('daily-choice-submit')));
        await tester.pump();
        expect(repository.commands, hasLength(2));
        expect(repository.commands.last.path, same(newer.path));
        expect(repository.commands.last.selectedIntentionId, _intention(2));
        expect(
          repository.commands.last.date,
          CalendarDate.fromParts(2026, 9, 25),
        );
        expect(
          repository.commands.last.description?.value,
          'Сохранённое описание',
        );
        expect(repository.commands.last.isCompleted, isTrue);
      },
    );
  }

  testWidgets('отмена нового выбора не принимает поздний прежний путь', (
    tester,
  ) async {
    final repository = _Repository();
    final navigatorKey = GlobalKey<NavigatorState>();
    final observer = _RouteObserver();
    await _pump(
      tester,
      repository,
      navigatorKey: navigatorKey,
      navigatorObserver: observer,
    );
    await tester.ensureVisible(
      find.byKey(const ValueKey('daily-choice-submit')),
    );
    await tester.tap(find.byKey(const ValueKey('daily-choice-submit')));
    await tester.pump();
    repository.fail(
      0,
      const DailyChoiceConflictFailure(
        DailyChoiceConflictReason.confirmedPathChanged,
      ),
    );
    await tester.pumpAndSettle();

    final refresh = tester.widget<TextButton>(
      find.widgetWithText(TextButton, 'Вернуться к пути и актуализировать его'),
    );
    refresh.onPressed!();
    final olderRoute = observer.routes.last;
    refresh.onPressed!();
    final newerRoute = observer.routes.last;
    await tester.pumpAndSettle();
    navigatorKey.currentState!.removeRoute(newerRoute);
    await tester.pumpAndSettle();
    navigatorKey.currentState!.removeRoute(
      olderRoute,
      _selection(2, 3, 'Позднее действие'),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Позднее действие'), findsNothing);
    expect(find.textContaining('Действие'), findsWidgets);
    expect(find.text('Вернуться к пути и актуализировать его'), findsOneWidget);
    expect(repository.commands, hasLength(1));
  });
}

Future<void> _pump(
  WidgetTester tester,
  _Repository repository, {
  Locale locale = const Locale('ru'),
  GlobalKey<NavigatorState>? navigatorKey,
  NavigatorObserver? navigatorObserver,
  ChoicePathDraftDirection direction = ChoicePathDraftDirection.topDown,
  double textScale = 1,
}) async {
  final page = DailyChoiceCreationPage(
    path: ConfirmedChoicePath([
      ConfirmedChoicePathStep(
        relationId: _relation(1),
        sourceIntentionId: _intention(1),
        relatedIntentionId: _intention(2),
        type: LongTermRelationType.need,
      ),
    ]),
    steps: [_step()],
    initialDate: CalendarDate.fromParts(2026, 9, 24),
    direction: direction,
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        personalGraphRepositoryProvider.overrideWithValue(repository),
      ],
      child: MaterialApp(
        navigatorKey: navigatorKey,
        navigatorObservers: [?navigatorObserver],
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: GraphOperationPresenter(child: child!),
        ),
        home: navigatorKey == null
            ? page
            : const Scaffold(body: Text('Домашний экран')),
      ),
    ),
  );
  if (navigatorKey != null) {
    navigatorKey.currentState!.push(
      MaterialPageRoute<void>(builder: (_) => page),
    );
    await tester.pumpAndSettle();
  }
}

final class _Repository implements PersonalGraphRepository {
  final commands = <CreateDailyChoice>[];
  final requests = <Completer<DailyChoiceCommandResult>>[];

  void fail(int index, DailyChoiceCommandFailure failure) =>
      requests[index].complete(GraphCommandFailed(failure));

  void succeed(int index) {
    final command = commands[index];
    final id = (DailyChoiceId.decode(
      '00000000-0000-4000-8002-000000000001',
    ) as DailyChoiceIdDecodingSuccess).id;
    final stepId = (ChoicePathStepId.decode(
      '00000000-0000-4000-8003-000000000001',
    ) as ChoicePathStepIdDecodingSuccess).id;
    requests[index].complete(
      GraphCommandSucceeded(
        ConfirmedGraphResult(
          revision: const _Revision(),
          value: DailyChoiceCreated(
            choice: DailyChoice(
              id: id,
              sourceIntentionId: command.sourceIntentionId,
              selectedIntentionId: command.selectedIntentionId,
              date: command.date,
              description: command.description,
              isCompleted: command.isCompleted,
            ),
            path: StoredChoicePath([
              ChoicePathStep(
                id: stepId,
                dailyChoiceId: id,
                relationId: command.path.steps.first.relationId,
                previousStepId: null,
              ),
            ]),
            changes: const [_Change()],
          ),
        ),
      ),
    );
  }

  @override
  Future<GraphCommandResult<TSuccess, TFailure>> execute<
    TSuccess extends GraphCommandOutcome,
    TFailure extends GraphCommandFailure
  >(GraphCommand<TSuccess, TFailure> command) async {
    commands.add(command as CreateDailyChoice);
    final request = Completer<DailyChoiceCommandResult>();
    requests.add(request);
    return await request.future as GraphCommandResult<TSuccess, TFailure>;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _Revision implements GraphRevision {
  const _Revision();
  @override
  GraphRevisionOrder compareTo(GraphRevision other) => other is _Revision
      ? GraphRevisionOrder.same
      : GraphRevisionOrder.differentEpoch;
}

final class _Change implements GraphChange {
  const _Change();
  @override
  GraphRevision get revision => const _Revision();
}

IntentionId _intention(int value) => (IntentionId.decode(
  '00000000-0000-4000-8000-${value.toString().padLeft(12, '0')}',
) as IntentionIdDecodingSuccess).id;
LongTermRelationId _relation(int value) => (LongTermRelationId.decode(
  '00000000-0000-4000-8001-${value.toString().padLeft(12, '0')}',
) as LongTermRelationIdDecodingSuccess).id;

LongTermRelationSummary _step() => LongTermRelationSummary(
  relation: LongTermRelation(
    id: _relation(1),
    sourceIntentionId: _intention(1),
    relatedIntentionId: _intention(2),
    type: LongTermRelationType.need,
    priority: RelationPriority.p1,
    scope: RelationScope.active,
    creationSequence: RelationCreationSequence(1),
  ),
  source: RelationParticipantSummary(
    id: _intention(1),
    title: 'Основание',
    archiveState: IntentionArchiveState.active,
    activeRelationCount: 1,
  ),
  related: RelationParticipantSummary(
    id: _intention(2),
    title: 'Действие',
    archiveState: IntentionArchiveState.active,
    activeRelationCount: 0,
  ),
  hasDescription: false,
);

ChoicePathSelection _selection(int relation, int action, String title) =>
    ChoicePathSelection(
      path: ConfirmedChoicePath([
        ConfirmedChoicePathStep(
          relationId: _relation(relation),
          sourceIntentionId: _intention(1),
          relatedIntentionId: _intention(action),
          type: LongTermRelationType.need,
        ),
      ]),
      steps: [
        LongTermRelationSummary(
          relation: LongTermRelation(
            id: _relation(relation),
            sourceIntentionId: _intention(1),
            relatedIntentionId: _intention(action),
            type: LongTermRelationType.need,
            priority: RelationPriority.p1,
            scope: RelationScope.active,
            creationSequence: RelationCreationSequence(relation),
          ),
          source: RelationParticipantSummary(
            id: _intention(1),
            title: 'Основание',
            archiveState: IntentionArchiveState.active,
            activeRelationCount: 1,
          ),
          related: RelationParticipantSummary(
            id: _intention(action),
            title: title,
            archiveState: IntentionArchiveState.active,
            activeRelationCount: 0,
          ),
          hasDescription: false,
        ),
      ],
    );

ChoicePathSelection _bottomSelection(int relation, int source, String title) =>
    ChoicePathSelection(
      path: ConfirmedChoicePath([
        ConfirmedChoicePathStep(
          relationId: _relation(relation),
          sourceIntentionId: _intention(source),
          relatedIntentionId: _intention(2),
          type: LongTermRelationType.need,
        ),
      ]),
      steps: [
        LongTermRelationSummary(
          relation: LongTermRelation(
            id: _relation(relation),
            sourceIntentionId: _intention(source),
            relatedIntentionId: _intention(2),
            type: LongTermRelationType.need,
            priority: RelationPriority.p1,
            scope: RelationScope.active,
            creationSequence: RelationCreationSequence(relation),
          ),
          source: RelationParticipantSummary(
            id: _intention(source),
            title: title,
            archiveState: IntentionArchiveState.active,
            activeRelationCount: 1,
          ),
          related: RelationParticipantSummary(
            id: _intention(2),
            title: 'Действие',
            archiveState: IntentionArchiveState.active,
            activeRelationCount: 0,
          ),
          hasDescription: false,
        ),
      ],
    );

final class _RouteObserver extends NavigatorObserver {
  final routes = <Route<dynamic>>[];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    routes.add(route);
  }
}
