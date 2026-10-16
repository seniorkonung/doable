import 'dart:async';

import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/src/daily_choice/application/daily_choice_command.dart';
import 'package:doable/src/daily_choice/application/daily_choice_details.dart';
import 'package:doable/src/daily_choice/application/daily_choice_result.dart';
import 'package:doable/src/daily_choice/domain/calendar_date.dart';
import 'package:doable/src/daily_choice/domain/daily_choice_priority.dart';
import 'package:doable/src/daily_choice/domain/daily_choice_schedule.dart';
import 'package:doable/src/daily_choice/presentation/editor/daily_choice_edit_page.dart';
import 'package:doable/src/data/local/app_database.dart';
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/application/personal_graph_repository.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:doable/src/graph/data/drift_personal_graph_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/daily_choice_durability_fixture.dart';

void main() {
  late AppDatabase database;
  late DriftPersonalGraphRepository repository;
  late DailyChoiceDetails original;

  setUp(() async {
    database = AppDatabase(openInMemoryLocalDatabase());
    await database.open();
    await seedDurabilityGraph(database);
    repository = durabilityRepository(database);
    await repository.execute(
      durabilityCreate(
        schedule: DailyChoiceTime(hour: 18, minute: 0),
        priority: DailyChoicePriority.p2,
      ),
    );
    original = (await repository.getDailyChoice(
      durabilityChoice(201),
    ) as DailyChoiceReadSuccess).value.value!;
  });

  tearDown(() => database.close());

  testWidgets('сохранённые 18:00/P2 редактируются в обеих локалях', (
    tester,
  ) async {
    final updates = _PendingUpdates();
    final semantics = tester.ensureSemantics();
    final locale = ValueNotifier(const Locale('ru'));
    addTearDown(locale.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          personalGraphRepositoryProvider.overrideWith((ref) => updates),
        ],
        child: ValueListenableBuilder(
          valueListenable: locale,
          builder: (_, value, _) => MaterialApp(
            locale: value,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: DailyChoiceEditPage(details: original),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Время: 18:00'), findsOneWidget);
    expect(find.text('Приоритет P2'), findsOneWidget);
    await _tap(tester, find.text('Весь день'));
    locale.value = const Locale('en');
    await tester.pumpAndSettle();
    expect(find.text('All day'), findsOneWidget);
    expect(find.text('Priority P2'), findsOneWidget);
    await _tap(tester, find.text('Priority P1'));
    await _tap(tester, find.byKey(const ValueKey('daily-choice-edit-submit')));
    await _tap(tester, find.text('Priority P3'), delta: -150);
    expect(
      tester.getSemantics(find.text('Priority P3')),
      matchesSemantics(
        label: 'Priority P3',
        isButton: true,
        hasEnabledState: true,
        hasSelectedState: true,
      ),
    );
    expect(
      (updates.command.patch.priority
              as DailyChoiceFieldSet<DailyChoicePriority>)
          .value,
      DailyChoicePriority.p1,
    );
    await _tap(tester, find.text('All day'), delta: -150);
    expect(
      tester.getSemantics(find.text('All day')),
      matchesSemantics(
        label: 'All day',
        isButton: true,
        hasEnabledState: true,
        hasSelectedState: true,
        isSelected: true,
      ),
    );
    updates.complete(const GraphCommandFailed(DailyChoiceUnavailableFailure()));
    await tester.pumpAndSettle();
    await _tap(tester, find.text('Priority P3'), delta: -150);
    await _tap(tester, find.byKey(const ValueKey('daily-choice-edit-submit')));
    updates.complete(
      (await tester.runAsync(() => repository.execute(updates.command)))!,
    );
    await tester.pumpAndSettle();
    final saved = (await tester.runAsync(
      () => repository.getDailyChoice(original.choice.id),
    ) as DailyChoiceReadSuccess).value.value!.choice;
    expect(saved.schedule, const DailyChoiceAllDay());
    expect(saved.priority, DailyChoicePriority.p3);
    expect(saved.description, original.choice.description);
    expect(saved.date, original.choice.date);
    expect(saved.isCompleted, original.choice.isCompleted);
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });

  testWidgets(
    'правка описания сохраняет независимые подтверждённые изменения',
    (tester) async {
      final updates = _PendingUpdates();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            personalGraphRepositoryProvider.overrideWith((ref) => updates),
          ],
          child: MaterialApp(
            locale: const Locale('ru'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: DailyChoiceEditPage(details: original),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final time = DailyChoiceTime(hour: 9, minute: 30);
      final date = CalendarDate.fromParts(2026, 10, 16);
      await tester.runAsync(
        () => repository.execute(
          UpdateDailyChoiceFields(
            choiceId: original.choice.id,
            patch: DailyChoiceFieldsPatch(
              date: DailyChoiceFieldSet(date),
              isCompleted: const DailyChoiceFieldSet(false),
              schedule: DailyChoiceFieldSet(time),
              priority: const DailyChoiceFieldSet(DailyChoicePriority.p4),
            ),
          ),
        ),
      );
      await tester.enterText(
        find.byKey(const ValueKey('daily-choice-edit-description')),
        'Правка из открытой формы',
      );
      await _tap(
        tester,
        find.byKey(const ValueKey('daily-choice-edit-submit')),
      );
      updates.complete(
        (await tester.runAsync(() => repository.execute(updates.command)))!,
      );
      await tester.pumpAndSettle();
      final saved = (await tester.runAsync(
        () => repository.getDailyChoice(original.choice.id),
      ) as DailyChoiceReadSuccess).value.value!.choice;
      expect(saved.description?.value, 'Правка из открытой формы');
      expect(saved.schedule, time);
      expect(saved.priority, DailyChoicePriority.p4);
      expect(saved.date, date);
      expect(saved.isCompleted, isFalse);
      expect(tester.takeException(), isNull);
    },
  );
}

final class _PendingUpdates implements PersonalGraphRepository {
  late UpdateDailyChoiceFields command;
  late Completer<DailyChoiceCommandResult> _pending;

  @override
  Future<GraphCommandResult<TSuccess, TFailure>> execute<
    TSuccess extends GraphCommandOutcome,
    TFailure extends GraphCommandFailure
  >(GraphCommand<TSuccess, TFailure> command) async {
    if (command is! UpdateDailyChoiceFields) throw UnimplementedError();
    this.command = command as UpdateDailyChoiceFields;
    _pending = Completer<DailyChoiceCommandResult>();
    return await _pending.future as GraphCommandResult<TSuccess, TFailure>;
  }

  void complete(DailyChoiceCommandResult result) => _pending.complete(result);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _tap(
  WidgetTester tester,
  Finder finder, {
  double delta = 150,
}) async {
  await tester.scrollUntilVisible(
    finder,
    delta,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}
