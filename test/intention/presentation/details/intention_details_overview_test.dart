import 'package:auto_route/auto_route.dart';
import 'package:doable/src/app/routing/app_router.gr.dart';
import 'package:doable/src/daily_choice/domain/calendar_date.dart';
import 'package:doable/src/design_system/components/button.dart';
import 'package:doable/src/design_system/components/option_tiles.dart';
import 'package:doable/src/design_system/components/tag_chip.dart';
import 'package:doable/src/design_system/components/tags_section.dart';
import 'package:doable/src/design_system/components/top_bar.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:doable/src/intention/application/intention_command.dart';
import 'package:doable/src/intention/application/intention_result.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/intention/presentation/details/intention_details_page.dart';
import 'package:doable/src/intention/presentation/details/intention_options.dart';
import 'package:doable/src/intention/presentation/edit/intention_edit_page.dart';
import 'package:doable/src/tag/application/tag_assignments.dart';
import 'package:doable/src/tag/application/tag_read_result.dart';
import 'package:doable/src/tag/presentation/assignments/tag_assignments_view_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/daily_choice_local_date.dart';
import '../../../support/intention_options.dart';
import '../../../support/ordinary_page_test_app.dart';
import 'details_test_support.dart';

void main() {
  for (final (locale, editLabel) in [
    (const Locale('ru'), 'Изменить описание: Утром\nв парке'),
    (const Locale('en'), 'Edit the description: Утром\nв парке'),
  ]) {
    testWidgets('нажатие на описание открывает его изменение: '
        '${locale.languageCode}', (tester) async {
      final semantics = tester.ensureSemantics();
      final repository = ControlledDetailsRepository();
      final intention = testDetailsIntention(
        title: 'Бегать',
        description: 'Утром\nв парке',
      );
      await _pumpPage(tester, repository, intention, locale: locale);
      await waitForDetailRequests(repository, 1);
      repository.detailRequests.single.add(ResultSuccess(intention));
      await tester.pumpAndSettle();

      expect(find.text('Утром\nв парке'), findsOneWidget);
      final description = find.bySemanticsLabel(editLabel);
      expect(
        tester.getSemantics(description),
        isSemantics(
          label: editLabel,
          isButton: true,
          hasEnabledState: true,
          isEnabled: true,
          hasTapAction: true,
        ),
      );
      await tester.tap(description);
      await tester.pumpAndSettle();

      expect(find.byType(IntentionEditPage), findsOneWidget);
      expect(_editable(tester, _editTitle).controller.text, 'Бегать');
      final editDescription = _editable(tester, _editDescription);
      expect(editDescription.controller.text, 'Утром\nв парке');
      expect(editDescription.focusNode.hasFocus, isTrue);
      expect(
        editDescription.controller.selection,
        const TextSelection.collapsed(offset: 'Утром\nв парке'.length),
      );
      expect(
        tester
            .widget<Button>(
              find.descendant(
                of: find.byType(TopBar),
                matching: find.byType(Button),
              ),
            )
            .onPressed,
        isNull,
      );
      semantics.dispose();
    });
  }

  for (final (locale, invitation) in [
    (const Locale('ru'), 'Добавить описание'),
    (const Locale('en'), 'Add a description'),
  ]) {
    testWidgets('без описания приглашение добавить его открывает пустое поле '
        'описания: ${locale.languageCode}', (tester) async {
      final semantics = tester.ensureSemantics();
      final repository = ControlledDetailsRepository();
      final intention = testDetailsIntention(description: null);
      await _pumpPage(tester, repository, intention, locale: locale);
      await waitForDetailRequests(repository, 1);
      repository.detailRequests.single.add(ResultSuccess(intention));
      await tester.pumpAndSettle();

      expect(find.text(invitation), findsOneWidget);
      final description = find.bySemanticsLabel(invitation);
      expect(
        tester.getSemantics(description),
        isSemantics(
          label: invitation,
          isButton: true,
          hasEnabledState: true,
          isEnabled: true,
          hasTapAction: true,
        ),
      );
      await tester.tap(description);
      await tester.pumpAndSettle();

      final editDescription = _editable(tester, _editDescription);
      expect(editDescription.controller.text, isEmpty);
      expect(editDescription.focusNode.hasFocus, isTrue);
      semantics.dispose();
    });
  }

  testWidgets('описание недоступно и не открывает экран изменения, пока '
      'выполняется команда страницы', (tester) async {
    final semantics = tester.ensureSemantics();
    final repository = ControlledDetailsRepository();
    final intention = testDetailsIntention(description: 'Утром в парке');
    await _pumpPage(tester, repository, intention);
    await waitForDetailRequests(repository, 1);
    repository.detailRequests.single.add(ResultSuccess(intention));
    await tester.pumpAndSettle();

    await chooseIntentionOption(tester, IntentionOption.archive);

    const label = 'Изменить описание: Утром в парке';
    expect(
      tester.getSemantics(find.bySemanticsLabel(label)),
      isSemantics(
        label: label,
        isButton: true,
        hasEnabledState: true,
        isEnabled: false,
        hasTapAction: false,
      ),
    );
    await tester.tap(find.text('Утром в парке'));
    // Индикатор выполняющейся команды не даёт кадрам успокоиться.
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(IntentionEditPage), findsNothing);
    semantics.dispose();
  });
  testWidgets('включение готовности плиткой сохраняется без отдельного '
      'подтверждения и без сообщения об успехе', (tester) async {
    final semantics = tester.ensureSemantics();
    final repository = ControlledDetailsRepository();
    final before = testDetailsIntention(index: 30);
    final saved = testDetailsIntention(
      index: 30,
      readiness: IntentionReadiness.ready,
    );
    await _pumpPage(tester, repository, before);
    await waitForDetailRequests(repository, 1);
    repository.detailRequests.single.add(ResultSuccess(before));
    await tester.pumpAndSettle();

    expect(
      tester.getSemantics(_typeTile('Намерение')),
      _typeTileSemantics(_intentionTileLabel, selected: true),
    );
    expect(
      tester.getSemantics(_typeTile('Действие')),
      _typeTileSemantics(_actionTileLabel, selected: false),
    );
    await tester.tap(_typeTile('Действие'));
    await tester.pump();

    expect(repository.commands.single, isA<EnableIntentionReadiness>());
    expect(find.byType(Dialog), findsNothing);
    repository.completeCommand(
      0,
      testDetailsSavedResult(saved, before: before),
    );
    await tester.pump();
    await waitForDetailRequests(repository, 2);
    repository.detailRequests[1].add(ResultSuccess(saved));
    await tester.pumpAndSettle();

    expect(
      tester.getSemantics(_typeTile('Действие')),
      _typeTileSemantics(_actionTileLabel, selected: true),
    );
    expect(
      find.descendant(of: find.byType(TopBar), matching: find.text('Действие')),
      findsOneWidget,
    );
    expect(find.byType(SnackBar), findsNothing);
    semantics.dispose();
  });

  testWidgets('плитка «Намерение» обратимо выключает готовность', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final repository = ControlledDetailsRepository();
    final ready = testDetailsIntention(
      index: 31,
      readiness: IntentionReadiness.ready,
    );
    final notReady = testDetailsIntention(index: 31);
    await _pumpPage(tester, repository, ready);
    await waitForDetailRequests(repository, 1);
    repository.detailRequests.single.add(ResultSuccess(ready));
    await tester.pumpAndSettle();

    await tester.tap(_typeTile('Намерение'));
    await tester.pump();

    expect(repository.commands.single, isA<DisableIntentionReadiness>());
    repository.completeCommand(
      0,
      testDetailsSavedResult(notReady, before: ready),
    );
    await tester.pump();
    await waitForDetailRequests(repository, 2);
    repository.detailRequests[1].add(ResultSuccess(notReady));
    await tester.pumpAndSettle();

    expect(
      tester.getSemantics(_typeTile('Намерение')),
      _typeTileSemantics(_intentionTileLabel, selected: true),
    );
    semantics.dispose();
  });

  testWidgets('плитки доступны у архивированного намерения и недоступны, '
      'пока выполняется команда', (tester) async {
    final semantics = tester.ensureSemantics();
    final repository = ControlledDetailsRepository();
    final intention = testDetailsIntention(
      index: 32,
      archiveState: IntentionArchiveState.archived,
    );
    await _pumpPage(tester, repository, intention);
    await waitForDetailRequests(repository, 1);
    repository.detailRequests.single.add(ResultSuccess(intention));
    await tester.pumpAndSettle();

    await tester.tap(_typeTile('Действие'));
    await tester.pump();
    expect(repository.commands.single, isA<EnableIntentionReadiness>());

    expect(
      tester.getSemantics(_typeTile('Намерение')),
      isSemantics(
        label: _intentionTileLabel,
        isButton: true,
        hasEnabledState: true,
        isEnabled: false,
        hasSelectedState: true,
        isSelected: true,
        isInMutuallyExclusiveGroup: true,
        hasTapAction: false,
      ),
    );
    await tester.tap(_typeTile('Действие'));
    // Индикатор выполняющейся команды не даёт кадрам успокоиться.
    await tester.pump(const Duration(seconds: 1));
    expect(repository.commands, hasLength(1));
    semantics.dispose();
  });

  testWidgets('обзор только что созданного намерения кончается одной '
      'сегодняшней датой создания', (tester) async {
    final semantics = tester.ensureSemantics();
    final repository = ControlledDetailsRepository();
    final createdNow = IntentionTimestamp(DateTime(2026, 10, 29, 9, 30));
    final intention = Intention(
      id: testDetailsIntentionId(41),
      title: 'Бегать',
      description: null,
      readiness: IntentionReadiness.notReady,
      archiveState: IntentionArchiveState.active,
      createdAt: createdNow,
      updatedAt: createdNow,
    );
    await _pumpPage(
      tester,
      repository,
      intention,
      overrides: [
        ControlledDailyChoiceLocalDate(CalendarDate.fromParts(2026, 10, 29))
            .override,
        tagAssignmentsReaderProvider.overrideWithValue(_NoTagReads()),
      ],
    );
    await waitForDetailRequests(repository, 1);
    repository.detailRequests.single.add(ResultSuccess(intention));
    await tester.pumpAndSettle();

    expect(find.text('Добавить описание'), findsOneWidget);
    expect(
      tester.getSemantics(_typeTile('Намерение')),
      _typeTileSemantics(_intentionTileLabel, selected: true),
    );
    final tags = find.byType(TagsSection);
    expect(
      find.descendant(of: tags, matching: find.text('Теги')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: tags, matching: find.text('Добавить')),
      findsOneWidget,
    );
    expect(find.byType(TagChip), findsNothing);
    final dates = find.text('Создано 29 окт.');
    expect(dates, findsOneWidget);
    expect(find.textContaining('Изменено'), findsNothing);
    // Строка стоит в 10 под блоком тегов вровень со словом «Теги».
    expect(
      tester.getTopLeft(dates),
      Offset(
        tester
            .getTopLeft(find.descendant(of: tags, matching: find.text('Теги')))
            .dx,
        tester.getBottomLeft(tags).dy + 10,
      ),
    );
    semantics.dispose();
  });
}

final class _NoTagReads extends Fake implements TagReadContract {
  @override
  Future<TagAssignmentsResult> getTagAssignments(
    IntentionId intentionId,
  ) async => TagAssignmentsSuccess(
    TagAssignmentsSnapshot(
      intentionId: intentionId,
      items: const [],
      revision: const TestDetailsRevision(0),
    ),
  );
}

const _intentionTileLabel =
    'Намерение\nЛюбого размера. Может занять больше дня.';
const _actionTileLabel =
    'Действие\nВыполнимо за один день, и понятно, что делать.';

Finder _typeTile(String title) => find.descendant(
  of: find.byType(OptionTiles<IntentionReadiness>),
  matching: find.text(title),
);

Matcher _typeTileSemantics(String label, {required bool selected}) =>
    isSemantics(
      label: label,
      isButton: true,
      hasEnabledState: true,
      isEnabled: true,
      hasSelectedState: true,
      isSelected: selected,
      isInMutuallyExclusiveGroup: true,
      hasTapAction: true,
    );

final _editTitle = find.byKey(const ValueKey('intention-edit-title'));
final _editDescription = find.byKey(
  const ValueKey('intention-edit-description'),
);

EditableText _editable(WidgetTester tester, Finder field) =>
    tester.widget<EditableText>(
      find.descendant(of: field, matching: find.byType(EditableText)),
    );

Future<void> _pumpPage(
  WidgetTester tester,
  ControlledDetailsRepository repository,
  Intention intention, {
  Locale locale = const Locale('ru'),
  List<Override> overrides = const [],
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        personalGraphRepositoryProvider.overrideWithValue(repository),
        ...overrides,
      ],
      child: OrdinaryPageTestApp(
        locale: locale,
        routes: [AutoRoute(page: IntentionEditRoute.page)],
        home: IntentionDetailsPage(intentionId: intention.id),
      ),
    ),
  );
  await tester.pump();
}
