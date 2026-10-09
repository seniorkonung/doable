import 'dart:ui' show Tristate;

import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/src/app/quick_creation/quick_creation_button.dart';
import 'package:doable/src/app/quick_creation/quick_creation_mode.dart';
import 'package:doable/src/app/quick_creation/quick_creation_mode_controller.dart';
import 'package:doable/src/app/quick_creation/quick_creation_mode_menu.dart';
import 'package:doable/src/app/quick_creation/quick_creation_mode_presentation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/in_memory_quick_creation_mode_store.dart';

void main() {
  for (final locale in [const Locale('ru'), const Locale('en')]) {
    for (final mode in QuickCreationMode.values) {
      testWidgets('нажатие запускает только текущий режим, долгое нажатие '
          'и доступное действие открывают меню: ${locale.languageCode}, '
          '${mode.name}', (tester) async {
        final launches = await _pumpButton(tester, locale: locale, mode: mode);
        final button = find.byType(QuickCreationButton);
        final localizations = AppLocalizations.of(tester.element(button));
        final node = tester.getSemantics(button);
        expect(
          node.label,
          '${localizations.quickCreationLabel}, '
          '${mode.title(localizations)}',
        );
        expect(node.hint, localizations.quickCreationLongPressHint);
        expect(node.flagsCollection.isButton, isTrue);
        expect(node.flagsCollection.isSelected, Tristate.none);
        expect(node.role, isNot(SemanticsRole.tab));
        expect(node.indexInParent, isNull);
        expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
        expect(
          node.getSemanticsData().hasAction(SemanticsAction.longPress),
          isTrue,
        );
        expect(
          node.hintOverrides?.onLongPressHint,
          localizations.quickCreationChangeMode,
        );
        final actions = [
          for (final id in node.getSemanticsData().customSemanticsActionIds!)
            CustomSemanticsAction.getAction(id)!,
        ];
        expect(
          actions
              .where((action) => action.label != null)
              .map((action) => action.label),
          [localizations.quickCreationChangeMode],
        );

        await tester.tap(button);
        await tester.pumpAndSettle();
        expect(launches, [mode]);
        expect(find.byType(BottomSheet), findsNothing);

        await tester.longPress(button);
        await tester.pumpAndSettle();
        expect(find.byType(BottomSheet), findsOneWidget);
        expect(find.byType(Tooltip), findsNothing);
        expect(launches, [mode]);
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();

        tester.semantics.customAction(
          find.semantics.byLabel(node.label),
          actions.singleWhere((action) => action.label != null),
        );
        await tester.pumpAndSettle();
        expect(find.byType(BottomSheet), findsOneWidget);
        expect(launches, [mode]);
        final next = QuickCreationMode.values[(mode.index + 1) % 4];
        final nextTitle = find.text(next.title(localizations));
        await tester.ensureVisible(nextTitle);
        await tester.tap(nextTitle);
        await tester.pumpAndSettle();
        expect(find.byType(BottomSheet), findsNothing);
        expect(find.byIcon(next.icon), findsOneWidget);
        expect(
          tester.getSemantics(button).label,
          '${localizations.quickCreationLabel}, ${next.title(localizations)}',
        );
        expect(launches, [mode]);
        await tester.tap(button);
        await tester.pumpAndSettle();
        expect(launches, [mode, next]);
        expect(tester.takeException(), isNull);
      });

      for (final textScale in [1.0, 2.6]) {
        testWidgets('плюс, значок режима и стрелки видны целиком без подписи, '
            'вся зона доступна при тексте $textScale: '
            '${locale.languageCode}, ${mode.name}', (tester) async {
          final launches = await _pumpButton(
            tester,
            locale: locale,
            mode: mode,
            textScale: textScale,
          );
          final button = find.byType(QuickCreationButton);
          final bounds = tester.getRect(button);
          expect(bounds.width, greaterThanOrEqualTo(48));
          expect(bounds.height, greaterThanOrEqualTo(48));
          expect(button.hitTestable(), findsOneWidget);
          expect(
            MediaQuery.textScalerOf(tester.element(button)).scale(10),
            10 * textScale,
          );
          expect(
            find.descendant(of: button, matching: find.byType(Text)),
            findsNothing,
          );
          for (final icon in [Icons.add, mode.icon, Icons.unfold_more]) {
            final finder = find.byIcon(icon);
            expect(finder.hitTestable(), findsOneWidget);
            final rect = tester.getRect(finder);
            expect(rect.isEmpty, isFalse);
            for (final container in [
              bounds,
              tester.getRect(find.byType(InkWell)),
              Offset.zero & tester.view.physicalSize,
            ]) {
              expect(container.contains(rect.topLeft), isTrue);
              expect(
                container.contains(rect.bottomRight - const Offset(0.1, 0.1)),
                isTrue,
              );
            }
          }
          for (final corner in [
            bounds.topLeft + const Offset(10, 10),
            bounds.topRight + const Offset(-10, 10),
            bounds.bottomLeft + const Offset(10, -10),
            bounds.bottomRight - const Offset(10, 10),
          ]) {
            await tester.tapAt(corner);
          }
          await tester.pumpAndSettle();
          expect(launches, List.filled(4, mode));
          expect(find.byType(BottomSheet), findsNothing);
          expect(tester.takeException(), isNull);
        });
      }
    }

    testWidgets('кнопка запускается действием экранного диктора и клавиатурой: '
        '${locale.languageCode}', (tester) async {
      final launches = await _pumpButton(
        tester,
        locale: locale,
        mode: QuickCreationMode.relation,
      );
      final node = tester.getSemantics(find.byType(QuickCreationButton));
      tester.semantics.tap(find.semantics.byLabel(node.label));
      await tester.pumpAndSettle();
      expect(launches, [QuickCreationMode.relation]);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(launches, List.filled(2, QuickCreationMode.relation));
      expect(find.byType(BottomSheet), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}

Future<List<QuickCreationMode>> _pumpButton(
  WidgetTester tester, {
  required Locale locale,
  required QuickCreationMode mode,
  double textScale = 2.6,
}) async {
  tester.view.physicalSize = const Size(320, 568);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  final launches = <QuickCreationMode>[];
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        quickCreationModeControllerProvider.overrideWith(
          () => QuickCreationModeController(
            initialMode: mode,
            store: InMemoryQuickCreationModeStore(),
          ),
        ),
      ],
      child: MaterialApp(
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Consumer(
          builder: (context, ref, _) {
            final current = ref.watch(quickCreationModeControllerProvider);
            return Scaffold(
              bottomNavigationBar: SizedBox(
                height: 64,
                child: Center(
                  child: QuickCreationButton(
                    mode: current,
                    onPressed: () => launches.add(current),
                    onChangeMode: () => showQuickCreationModeMenu(context),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return launches;
}
