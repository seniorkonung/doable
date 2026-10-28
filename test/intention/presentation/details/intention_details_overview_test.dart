import 'package:auto_route/auto_route.dart';
import 'package:doable/src/app/routing/app_router.gr.dart';
import 'package:doable/src/design_system/components/button.dart';
import 'package:doable/src/design_system/components/top_bar.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:doable/src/intention/application/intention_result.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/intention/presentation/details/intention_details_page.dart';
import 'package:doable/src/intention/presentation/edit/intention_edit_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

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

    final archive = find.byKey(const ValueKey('intention-details-archive'));
    await tester.ensureVisible(archive);
    await tester.tap(archive);
    await tester.pump();
    tester
        .state<ScrollableState>(
          find
              .descendant(
                of: find.byType(CustomScrollView),
                matching: find.byType(Scrollable),
              )
              .first,
        )
        .position
        .jumpTo(0);
    await tester.pump();

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
}

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
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        personalGraphRepositoryProvider.overrideWithValue(repository),
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
