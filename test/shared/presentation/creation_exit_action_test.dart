import 'dart:ui' show Tristate;

import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/src/shared/presentation/creation_exit_action.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

const _translations = [
  (
    locale: Locale('ru'),
    cancel: 'Отменить создание',
    leave: 'Выйти из создания',
    saving: 'Сохранение продолжится после выхода из создания.',
  ),
  (
    locale: Locale('en'),
    cancel: 'Cancel creation',
    leave: 'Leave creation',
    saving: 'Saving will continue after you leave creation.',
  ),
];

void main() {
  for (final translation in _translations) {
    for (final state in CreationExitState.values) {
      final label = state == CreationExitState.cancellable
          ? translation.cancel
          : translation.leave;
      final submitting = state == CreationExitState.submitting;

      testWidgets('доступное действие и объяснение соответствуют состоянию '
          '${state.name}: ${translation.locale.languageCode}', (tester) async {
        final semantics = tester.ensureSemantics();
        var exits = 0;
        await tester.pumpWidget(
          _app(locale: translation.locale, state: state, onExit: () => exits++),
        );

        expect(find.text(label), findsOneWidget);
        expect(find.byType(TextButton), findsOneWidget);
        expect(
          find.text(translation.saving),
          submitting ? findsOneWidget : findsNothing,
        );
        if (state != CreationExitState.cancellable) {
          expect(find.text(translation.cancel), findsNothing);
        }
        final node = tester
            .getSemantics(find.bySemanticsLabel(label))
            .getSemanticsData();
        expect(node.label, label);
        expect(node.flagsCollection.isButton, isTrue);
        expect(node.flagsCollection.isEnabled, Tristate.isTrue);
        expect(node.hint, submitting ? translation.saving : isEmpty);
        expect(exits, 0);

        tester.semantics.tap(find.semantics.byLabel(label));
        await tester.pump();
        expect(exits, 1);
        expect(tester.takeException(), isNull);
        semantics.dispose();
      });

      testWidgets('текст 2.6 и малая высота сохраняют целые строки и выход '
          '${state.name}: ${translation.locale.languageCode}', (tester) async {
        var exits = 0;
        await tester.pumpWidget(
          _app(
            locale: translation.locale,
            state: state,
            onExit: () => exits++,
            textScale: 2.6,
            size: const Size(240, 160),
          ),
        );
        expect(tester.takeException(), isNull);
        final viewport = tester.getRect(find.byType(CreationExitAction));
        for (final paragraph in tester.renderObjectList<RenderParagraph>(
          find.byType(RichText),
        )) {
          expect(paragraph.didExceedMaxLines, isFalse);
          expect(paragraph.size.width, lessThanOrEqualTo(viewport.width));
        }
        final button = find.byType(TextButton);
        expect(button.hitTestable(), findsOneWidget);
        await tester.tap(button);
        await tester.pump();
        expect(exits, 1);

        if (submitting) {
          final explanation = find.text(translation.saving);
          expect(
            tester.getRect(explanation).bottom,
            greaterThan(viewport.bottom),
          );
          await tester.drag(
            find.byType(CreationExitAction),
            const Offset(0, -800),
          );
          await tester.pumpAndSettle();
          expect(
            tester.getRect(explanation).bottom,
            closeTo(viewport.bottom, 1),
          );
          await tester.drag(
            find.byType(CreationExitAction),
            const Offset(0, 800),
          );
          await tester.pumpAndSettle();
          expect(button.hitTestable(), findsOneWidget);
          await tester.tap(button);
          await tester.pump();
          expect(exits, 2);
        }
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('смена состояния убирает прежнее обещание отмены и объяснение '
        'сохранения: ${translation.locale.languageCode}', (tester) async {
      final semantics = tester.ensureSemantics();
      for (final state in [
        CreationExitState.cancellable,
        CreationExitState.submitting,
        CreationExitState.terminal,
        CreationExitState.cancellable,
      ]) {
        await tester.pumpWidget(
          _app(locale: translation.locale, state: state, onExit: () {}),
        );
        final cancellable = state == CreationExitState.cancellable;
        final submitting = state == CreationExitState.submitting;
        expect(
          find.text(translation.cancel),
          cancellable ? findsOneWidget : findsNothing,
        );
        expect(
          find.text(translation.leave),
          cancellable ? findsNothing : findsOneWidget,
        );
        expect(
          tester
              .getSemantics(
                find.bySemanticsLabel(
                  cancellable ? translation.cancel : translation.leave,
                ),
              )
              .getSemanticsData()
              .hint,
          submitting ? translation.saving : isEmpty,
        );
      }
      expect(tester.takeException(), isNull);
      semantics.dispose();
    });
  }
}

Widget _app({
  required Locale locale,
  required CreationExitState state,
  required VoidCallback onExit,
  double textScale = 1,
  Size size = const Size(320, 240),
}) => MaterialApp(
  locale: locale,
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(
    body: Center(
      child: SizedBox.fromSize(
        size: size,
        child: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
          child: CreationExitAction(state: state, onExit: onExit),
        ),
      ),
    ),
  ),
);
