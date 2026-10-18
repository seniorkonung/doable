import 'package:doable/src/design_system/doable_colors.dart';
import 'package:doable/src/design_system/doable_icon.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'иконка сохраняет размер и семантику своего элемента управления',
    (tester) async {
      final semantics = tester.ensureSemantics();

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: Semantics(
              container: true,
              explicitChildNodes: true,
              button: true,
              label: 'От намерения',
              onTap: () {},
              child: const DoableIcon(
                DoableIconData.fromIntention,
                size: 22,
                color: Color(0xff111114),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(tester.getSize(find.byType(DoableIcon)), const Size.square(22));
      final button = tester.getSemantics(find.bySemanticsLabel('От намерения'));
      expect(
        button,
        matchesSemantics(
          label: 'От намерения',
          isButton: true,
          hasTapAction: true,
        ),
      );
      expect(button.childrenCount, 0);
      semantics.dispose();
    },
  );

  testWidgets('все 21 ресурс сохраняет исходную графику в обеих темах', (
    tester,
  ) async {
    await (FontLoader('Inter')..addFont(
          rootBundle.load('lib/src/design_system/fonts/InterVariable.ttf'),
        ))
        .load();
    await tester.binding.setSurfaceSize(const Size(560, 672));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: RepaintBoundary(
          key: const ValueKey('таблица иконок'),
          child: Row(
            children: [
              for (final colors in [DoableColors.light, DoableColors.dark])
                Expanded(
                  child: ColoredBox(
                    color: colors.bg,
                    child: Column(
                      children: [
                        for (final icon in DoableIconData.values)
                          _sampleRow(icon, colors),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    await expectLater(
      find.byKey(const ValueKey('таблица иконок')),
      matchesGoldenFile('goldens/doable_icons.png'),
    );
  });
}

Widget _sampleRow(DoableIconData icon, DoableColors colors) {
  final (size, color, background) = switch (icon) {
    DoableIconData.home ||
    DoableIconData.calendarDays ||
    DoableIconData.graph ||
    DoableIconData.plus => (24.0, colors.muted, colors.bg),
    DoableIconData.homeFilled ||
    DoableIconData.calendarDaysFilled ||
    DoableIconData.graphFilled => (24.0, colors.ink, colors.fill),
    DoableIconData.intention ||
    DoableIconData.relation ||
    DoableIconData.calendar ||
    DoableIconData.fromIntention ||
    DoableIconData.fromAction ||
    DoableIconData.export ||
    DoableIconData.backups => (22.0, colors.ink, colors.fill),
    DoableIconData.intentionMini ||
    DoableIconData.relationMini ||
    DoableIconData.calendarMini => (14.0, colors.muted, colors.bg),
    DoableIconData.check => (20.0, colors.accent, colors.fill),
    DoableIconData.chevronRight => (20.0, colors.muted, colors.bg),
    DoableIconData.settings => (22.0, colors.ink, colors.bg),
    DoableIconData.lockOpen => (20.0, colors.muted, colors.fill),
  };

  return SizedBox(
    height: 32,
    child: Row(
      children: [
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            '${icon.name} · ${size.toInt()}',
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 12,
              color: colors.ink,
            ),
          ),
        ),
        ColoredBox(
          color: background,
          child: SizedBox.square(
            dimension: 32,
            child: Center(
              child: DoableIcon(icon, size: size, color: color),
            ),
          ),
        ),
        if (icon == DoableIconData.intention ||
            icon == DoableIconData.relation ||
            icon == DoableIconData.calendar)
          ColoredBox(
            color: colors.accent,
            child: SizedBox.square(
              dimension: 32,
              child: Center(
                child: DoableIcon(icon, size: size, color: colors.onAccent),
              ),
            ),
          )
        else
          const SizedBox(width: 32),
        const SizedBox(width: 8),
      ],
    ),
  );
}
