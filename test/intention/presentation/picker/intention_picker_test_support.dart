import 'package:doable/src/design_system/components/picker_row.dart';
import 'package:doable/src/design_system/doable_icon.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Строки экрана выбора в порядке выдачи.
final Finder intentionPickerRows = find.byType(PickerRow);

/// Стрелка строки [row] экрана выбора, которая открывает подробности
/// намерения без выбора.
Finder intentionPickerArrow(Finder row) => find.descendant(
  of: row,
  matching: find.byWidgetPredicate(
    (widget) =>
        widget is DoableIcon && widget.icon == DoableIconData.arrowUpRight,
  ),
);

/// Обработчик выбора строки [row], сохранённый для позднего вызова.
VoidCallback intentionPickerPick(WidgetTester tester, Finder row) => tester
    .widget<PickerRow>(
      find.descendant(
        of: row,
        matching: find.byType(PickerRow, skipOffstage: false),
        matchRoot: true,
        skipOffstage: false,
      ),
    )
    .onPick;
