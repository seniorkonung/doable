import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/src/app/quick_creation/quick_creation_launcher.dart';
import 'package:doable/src/app/quick_creation/quick_creation_mode.dart';
import 'package:doable/src/app/routing/app_router.dart';
import 'package:doable/src/app/routing/app_router.gr.dart';
import 'package:doable/src/daily_choice/application/choice_path_draft.dart';
import 'package:doable/src/daily_choice/presentation/catalog/daily_choice_catalog_page.dart';
import 'package:doable/src/daily_choice/presentation/path/choice_path_page.dart';
import 'package:doable/src/data/local/app_database.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:doable/src/favorite/presentation/home/home_page.dart';
import 'package:doable/src/intention/presentation/catalog/intention_catalog_page.dart';
import 'package:doable/src/intention/presentation/details/intention_details_page.dart';
import 'package:doable/src/intention/presentation/intention_summary_view.dart';
import 'package:doable/src/long_term_relation/presentation/editor/relation_editor_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/daily_choice_durability_fixture.dart';

part 'quick_creation_launcher_test_support.dart';

void main() {
  for (final mode in QuickCreationMode.values) {
    for (final origin in _Origin.values) {
      testWidgets(
        '${_label(mode)} над ${origin.label}: один поток сохраняет историю и ввод',
        (tester) async {
          final router = await _openApp(tester);
          final source = await _source(tester, router, origin);
          final history = _history(router);
          final tabs = router.innerRouterOf<TabsRouter>(AppShellRoute.name)!;
          final selected = tabs.activeIndex;
          final launcher = QuickCreationLauncher();
          var finished = false;
          final running = launcher
              .launch(sourceContext: source, mode: mode)
              .then((_) => finished = true);
          unawaited(launcher.launch(sourceContext: source, mode: mode));
          await tester.pumpAndSettle();
          expect(router.current.name, _firstRoute(mode));
          expect(_history(router).take(history.length), history);
          expect(router.stackData, hasLength(history.length + 1));
          expect(tabs.activeIndex, selected);
          switch (mode) {
            case QuickCreationMode.intention:
              expect(finished, isTrue);
              await tester.tap(_key('intention-editor-close'));
            case QuickCreationMode.relation:
              expect(finished, isTrue);
              expect(
                router.current.argsAs<RelationEditorRouteArgs>().editorContext,
                isA<RelationBlankCreationContext>(),
              );
              await tester.tap(find.text('Отменить создание'));
            case QuickCreationMode.dailyChoiceFromIntention ||
                QuickCreationMode.dailyChoiceFromAction:
              expect(finished, isFalse);
              await _choose(tester, mode);
              expect(finished, isTrue);
              final path = tester.widget<ChoicePathPage>(
                find.byType(ChoicePathPage),
              );
              expect(path.direction, _direction(mode));
              expect(
                path.sourceIntentionId,
                durabilityIntention(_candidate(mode)),
              );
              expect(_history(router).take(history.length), history);
              expect(router.stackData, hasLength(history.length + 1));
              await tester.tap(find.text('Отменить создание'));
          }
          await tester.pumpAndSettle();
          await running;
          expect(_history(router), history);
          expect(tabs.activeIndex, selected);
          if (origin == _Origin.deep) {
            expect(
              tester
                  .widget<TextField>(_key('intention-details-edit-title'))
                  .controller!
                  .text,
              'Несохранённое название',
            );
            await router.maybePop();
            await tester.pumpAndSettle();
            expect(
              tester
                  .widget<TextField>(_key('relation-editor-description'))
                  .controller!
                  .text,
              'Чужой черновик',
            );
          }
          expect(tester.takeException(), isNull);
        },
      );
    }

    testWidgets(
      '${_label(mode)}: отказ открытия освобождает запуск без повтора',
      (tester) async {
        final errors = _captureLaunchErrors();
        final router = _FailingRouter(_firstRoute(mode));
        await _openApp(tester, router: router);
        final source = await _source(tester, router, _Origin.home);
        final history = _history(router);
        final launcher = QuickCreationLauncher();
        final first = launcher.launch(sourceContext: source, mode: mode);
        await tester.pumpAndSettle();
        await first;
        expect(_history(router), history);
        expect(errors, hasLength(1));
        expect(errors.single.exception.toString(), isNot(contains('Секрет')));
        final next = launcher.launch(sourceContext: source, mode: mode);
        await tester.pumpAndSettle();
        expect(router.current.name, _firstRoute(mode));
        await _cancel(tester, mode);
        await next;
        expect(_history(router), history);
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final mode in _dailyModes) {
    testWidgets('${_label(mode)}: отмена поиска разрешает новый запуск', (
      tester,
    ) async {
      final router = await _openApp(tester);
      final source = await _source(tester, router, _Origin.daily);
      final history = _history(router);
      final launcher = QuickCreationLauncher();
      final first = launcher.launch(sourceContext: source, mode: mode);
      await tester.pumpAndSettle();
      await _cancel(tester, mode);
      await first;
      expect(_history(router), history);
      final next = launcher.launch(sourceContext: source, mode: mode);
      await tester.pumpAndSettle();
      await _choose(tester, mode);
      await next;
      expect(router.current.name, ChoicePathRoute.name);
      await tester.tap(find.text('Отменить создание'));
      await tester.pumpAndSettle();
      expect(_history(router), history);
    });

    testWidgets('${_label(mode)}: страницы запускают независимые поиски', (
      tester,
    ) async {
      final router = await _openApp(tester);
      final source = await _source(tester, router, _Origin.home);
      final first = QuickCreationLauncher().launch(
        sourceContext: source,
        mode: mode,
      );
      await tester.pumpAndSettle();
      final firstPicker = router.current.matchId;
      await tester.enterText(
        _key('daily-choice-${_prefix(mode)}-filter'),
        'Намерение 3',
      );
      unawaited(
        router.push(IntentionDetailsRoute(intentionId: durabilityIntention(3))),
      );
      await tester.pumpAndSettle();
      final nested = QuickCreationLauncher().launch(
        sourceContext: tester.element(find.byType(IntentionDetailsPage)),
        mode: mode,
      );
      await tester.pumpAndSettle();
      expect(router.current.matchId, isNot(firstPicker));
      expect(
        tester
            .widget<TextField>(_key('daily-choice-${_prefix(mode)}-filter'))
            .controller!
            .text,
        isEmpty,
      );
      await _cancel(tester, mode);
      await nested;
      await router.maybePop();
      await tester.pumpAndSettle();
      expect(router.current.matchId, firstPicker);
      expect(
        tester
            .widget<TextField>(_key('daily-choice-${_prefix(mode)}-filter'))
            .controller!
            .text,
        'Намерение 3',
      );
      await _cancel(tester, mode);
      await first;
      expect(router.stackData, hasLength(1));
      expect(tester.takeException(), isNull);
    });

    for (final origin in [_Origin.home, _Origin.deep]) {
      testWidgets(
        '${_label(mode)}: поздний ID после сброса ${origin.label} не открывает путь',
        (tester) async {
          final router = _DelayedPickerRouter();
          await _openApp(tester, router: router);
          final source = await _source(tester, router, origin);
          final first = QuickCreationLauncher().launch(
            sourceContext: source,
            mode: mode,
          );
          await tester.pumpAndSettle();
          await _choose(tester, mode);
          router.popUntilRoot();
          final tabs = router.innerRouterOf<TabsRouter>(AppShellRoute.name)!;
          tabs.setActiveIndex(2);
          await tester.pumpAndSettle();
          if (origin == _Origin.deep) {
            unawaited(
              router.push(
                IntentionDetailsRoute(intentionId: durabilityIntention(2)),
              ),
            );
            await tester.pumpAndSettle();
          } else {
            tabs.setActiveIndex(0);
            await tester.pumpAndSettle();
          }
          final history = _history(router);
          router.release();
          await tester.pumpAndSettle();
          await first;
          expect(_history(router), history);
          expect(find.byType(ChoicePathPage), findsNothing);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
