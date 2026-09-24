import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/src/daily_choice/application/choice_path_suggestions.dart';
import 'package:doable/src/daily_choice/application/daily_choice_details.dart';
import 'package:doable/src/daily_choice/domain/calendar_date.dart';
import 'package:doable/src/daily_choice/domain/choice_path_step_id.dart';
import 'package:doable/src/daily_choice/domain/daily_choice.dart';
import 'package:doable/src/daily_choice/domain/daily_choice_id.dart';
import 'package:doable/src/daily_choice/presentation/path/choice_path_suggestions_state.dart';
import 'package:doable/src/daily_choice/presentation/path/choice_path_suggestions_view.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation_id.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('показывает основание, действие и одношаговый путь', (
    tester,
  ) async {
    final item = _suggestion();
    AvailableChoicePathSuggestion? selected;
    await _pump(tester, _ready(item), onSelected: (value) => selected = value);

    expect(find.text('Основание: Намерение 1'), findsOneWidget);
    expect(find.text('Выбранное действие: Намерение 2'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('choice-suggestion-view-0')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Нужно: Чтобы Намерение 1'), findsOneWidget);
    expect(find.text('Выбранное действие: Намерение 2'), findsWidgets);
    expect(find.text('Переход 1 из 1'), findsOneWidget);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('choice-suggestion-select-0')));
    expect(selected, same(item));
  });

  testWidgets('раскрывает длинный путь и различает одинаковые названия', (
    tester,
  ) async {
    await _pump(tester, _ready(_suggestion(length: 3, sameTitles: true)));
    await tester.tap(find.byKey(const ValueKey('choice-suggestion-view-0')));
    await tester.pumpAndSettle();

    expect(find.text('Основание: Повтор'), findsOneWidget);
    expect(find.text('Выбранное действие: Повтор'), findsWidgets);
    expect(find.text('Переход 1 из 3'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Переход 2 из 3'), 160);
    expect(find.textContaining('Можно: Чтобы Повтор'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Переход 3 из 3'), 160);
    expect(find.textContaining('Нужно: Чтобы Повтор'), findsNWidgets(2));
  });

  testWidgets('сохраняет порядок подсказок и передаёт выбранный маршрут', (
    tester,
  ) async {
    final first = _suggestion(choiceValue: 1);
    final second = _suggestion(choiceValue: 2);
    AvailableChoicePathSuggestion? selected;
    await _pump(
      tester,
      ChoicePathSuggestionsReady(_snapshot([first, second])),
      onSelected: (value) => selected = value,
    );

    expect(find.text('Подсказка 1 из 2'), findsOneWidget);
    expect(find.text('Подсказка 2 из 2'), findsOneWidget);
    await tester.ensureVisible(
      find.byKey(const ValueKey('choice-suggestion-select-1')),
    );
    await tester.tap(find.byKey(const ValueKey('choice-suggestion-select-1')));
    expect(selected, same(second));
  });

  testWidgets('недоступный путь остаётся видимым с причиной и архивом', (
    tester,
  ) async {
    var selected = false;
    await _pump(
      tester,
      _ready(_suggestion(archivedRelation: true)),
      onSelected: (_) => selected = true,
    );

    expect(find.textContaining('архивирована'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('choice-suggestion-select-0')),
      findsNothing,
    );
    await tester.tap(find.byKey(const ValueKey('choice-suggestion-view-0')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Архивировано'), findsWidgets);
    expect(find.textContaining('связь пути архивирована'), findsOneWidget);
    expect(selected, isFalse);
  });

  testWidgets('объясняет архив намерения и утрату готовности действия', (
    tester,
  ) async {
    await _pump(tester, _ready(_suggestion(archivedIntention: true)));
    expect(find.textContaining('намерений архивировано'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('choice-suggestion-select-0')),
      findsNothing,
    );
    await tester.tap(find.byKey(const ValueKey('choice-suggestion-view-0')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Архивировано'), findsWidgets);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    await _pump(tester, _ready(_suggestion(actionReady: false)));
    expect(find.textContaining('больше не готово'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('choice-suggestion-select-0')),
      findsNothing,
    );
    await tester.tap(find.byKey(const ValueKey('choice-suggestion-view-0')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Не готово к действию'), findsWidgets);
    expect(find.textContaining('больше не готово'), findsOneWidget);
  });

  testWidgets('различает загрузку, пустую выдачу и устранимую ошибку', (
    tester,
  ) async {
    final query = ChoicePathSuggestionsForSource(_id(1));
    await _pump(tester, ChoicePathSuggestionsLoading(query));
    expect(find.textContaining('Загружаем подсказки'), findsOneWidget);

    await _pump(tester, ChoicePathSuggestionsEmpty(_snapshot([])));
    expect(find.textContaining('Прежних маршрутов'), findsOneWidget);

    var retried = false;
    await _pump(
      tester,
      ChoicePathSuggestionsLoadFailure(
        query,
        const ChoicePathSuggestionsUnavailableFailure(),
      ),
      onRetry: () => retried = true,
    );
    expect(
      find.textContaining('Не удалось загрузить подсказки'),
      findsOneWidget,
    );
    await tester.tap(find.text('Повторить'));
    expect(retried, isTrue);
  });

  testWidgets('при обновлении и ошибке обновления запрещает выбор', (
    tester,
  ) async {
    final snapshot = _snapshot([_suggestion()]);
    await _pump(tester, ChoicePathSuggestionsUpdating(snapshot));
    expect(find.textContaining('Обновляем подсказки'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('choice-suggestion-select-0')),
      findsNothing,
    );

    await _pump(
      tester,
      ChoicePathSuggestionsRefreshFailure(
        snapshot,
        const ChoicePathSuggestionsCorruptionFailure(),
      ),
    );
    expect(find.textContaining('повреждены'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('choice-suggestion-select-0')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('choice-suggestion-view-0')),
      findsOneWidget,
    );
  });

  testWidgets('английская локаль, семантика и крупный текст сохраняют путь', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final semantics = tester.ensureSemantics();
    await _pump(
      tester,
      _ready(_suggestion(length: 2)),
      locale: const Locale('en'),
      textScale: 2,
    );
    expect(find.text('Source: Намерение 1'), findsOneWidget);
    expect(find.text('Selected action: Намерение 3'), findsOneWidget);
    expect(find.text('Suggestion 1 of 1'), findsOneWidget);
    expect(
      find.bySemanticsLabel(RegExp('View full route.*Suggestion 1 of 1')),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel(RegExp('Select route.*Suggestion 1 of 1')),
      findsOneWidget,
    );
    await tester.ensureVisible(
      find.byKey(const ValueKey('choice-suggestion-view-0')),
    );
    await tester.tap(find.byKey(const ValueKey('choice-suggestion-view-0')));
    await tester.pumpAndSettle();
    expect(find.text('Step 1 of 2'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Step 2 of 2'), 160);
    expect(find.text('Step 2 of 2'), findsOneWidget);
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });
}

Future<void> _pump(
  WidgetTester tester,
  ChoicePathSuggestionsState state, {
  ValueChanged<AvailableChoicePathSuggestion>? onSelected,
  VoidCallback? onRetry,
  Locale locale = const Locale('ru'),
  double textScale = 1,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Scaffold(
        body: SingleChildScrollView(
          child: ChoicePathSuggestionsView(
            state: state,
            onSelected: onSelected ?? (_) {},
            onRetry: onRetry,
          ),
        ),
      ),
    ),
  );
  if (state is ChoicePathSuggestionsLoading ||
      state is ChoicePathSuggestionsUpdating) {
    await tester.pump();
  } else {
    await tester.pumpAndSettle();
  }
}

ChoicePathSuggestionsReady _ready(ChoicePathSuggestion item) =>
    ChoicePathSuggestionsReady(_snapshot([item]));

ChoicePathSuggestionsSnapshot _snapshot(List<ChoicePathSuggestion> items) =>
    ChoicePathSuggestionsSnapshot(
      query: ChoicePathSuggestionsForSource(_id(1)),
      items: items,
      revision: const _Revision(),
    );

final class _Revision implements GraphRevision {
  const _Revision();

  @override
  GraphRevisionOrder compareTo(GraphRevision other) => GraphRevisionOrder.same;
}

ChoicePathSuggestion _suggestion({
  int choiceValue = 1,
  int length = 1,
  bool sameTitles = false,
  bool archivedRelation = false,
  bool archivedIntention = false,
  bool actionReady = true,
}) {
  final intentions = [
    for (var i = 1; i <= length + 1; i++)
      Intention(
        id: _id(i),
        title: sameTitles ? 'Повтор' : 'Намерение $i',
        description: null,
        readiness: i == length + 1 && !actionReady
            ? IntentionReadiness.notReady
            : IntentionReadiness.ready,
        archiveState: i == 1 && archivedIntention
            ? IntentionArchiveState.archived
            : IntentionArchiveState.active,
        createdAt: IntentionTimestamp(DateTime.utc(2026)),
        updatedAt: IntentionTimestamp(DateTime.utc(2026)),
      ),
  ];
  final choice = DailyChoice(
    id: _choiceId(choiceValue),
    sourceIntentionId: intentions.first.id,
    selectedIntentionId: intentions.last.id,
    date: CalendarDate.fromParts(2026, 9, 25),
    description: null,
    isCompleted: false,
  );
  final path = <DailyChoicePathStepDetails>[];
  ChoicePathStepId? previous;
  for (var i = 0; i < length; i++) {
    final relation = LongTermRelation(
      id: _relationId(i + 1 + (choiceValue - 1) * 10),
      sourceIntentionId: intentions[i].id,
      relatedIntentionId: intentions[i + 1].id,
      type: i == 1 ? LongTermRelationType.can : LongTermRelationType.need,
      priority: RelationPriority.p1,
      scope: archivedRelation && i == 0
          ? RelationScope.archived
          : RelationScope.active,
      creationSequence: RelationCreationSequence(i + 1),
    );
    final step = ChoicePathStep(
      id: _stepId(i + 1 + (choiceValue - 1) * 10),
      dailyChoiceId: choice.id,
      relationId: relation.id,
      previousStepId: previous,
    );
    path.add(
      DailyChoicePathStepDetails(
        step: step,
        relation: relation,
        description: null,
        source: intentions[i],
        related: intentions[i + 1],
      ),
    );
    previous = step.id;
  }
  return ChoicePathSuggestion.fromDetails(
    DailyChoiceDetails(
      choice: choice,
      source: intentions.first,
      selected: intentions.last,
      path: path,
    ),
  );
}

IntentionId _id(int value) => (IntentionId.decode(
  '00000000-0000-4000-8000-${value.toString().padLeft(12, '0')}',
) as IntentionIdDecodingSuccess).id;

DailyChoiceId _choiceId(int value) => (DailyChoiceId.decode(
  '00000000-0000-4000-8002-${value.toString().padLeft(12, '0')}',
) as DailyChoiceIdDecodingSuccess).id;

LongTermRelationId _relationId(int value) => (LongTermRelationId.decode(
  '00000000-0000-4000-8001-${value.toString().padLeft(12, '0')}',
) as LongTermRelationIdDecodingSuccess).id;

ChoicePathStepId _stepId(int value) => (ChoicePathStepId.decode(
  '00000000-0000-4000-8003-${value.toString().padLeft(12, '0')}',
) as ChoicePathStepIdDecodingSuccess).id;
