import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/src/design_system/components/button.dart';
import 'package:doable/src/design_system/components/option_row.dart';
import 'package:doable/src/design_system/components/sheet.dart';
import 'package:doable/src/design_system/components/top_bar.dart';
import 'package:doable/src/design_system/doable_icon.dart';
import 'package:doable/src/intention/presentation/details/intention_details_page.dart';
import 'package:doable/src/intention/presentation/details/intention_options.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Кнопка «⋯» на верхней панели страницы намерения: открывает лист
/// «Намерение».
final intentionOptionsButton = find.descendant(
  of: find.descendant(
    of: find.byType(IntentionDetailsPage),
    matching: find.byType(TopBar),
  ),
  matching: find.byWidgetPredicate(
    (widget) => widget is DoableIcon && widget.icon == DoableIconData.more,
  ),
);

/// Пункт [option] открытого листа «Намерение» на языке приложения.
Finder intentionOption(IntentionOption option) => find.descendant(
  of: find.byType(Sheet),
  matching: find.byElementPredicate(
    (element) => switch (element.widget) {
      final OptionRow row => row.name == _optionName(element, option),
      _ => false,
    },
  ),
);

/// Открывает параметры намерения и выбирает [option].
///
/// Лист закрывается до начала действия, а индикатор выполняющейся команды не
/// даёт кадрам успокоиться, поэтому закрытие досматривается паузой.
Future<void> chooseIntentionOption(
  WidgetTester tester,
  IntentionOption option,
) async {
  await tester.tap(intentionOptionsButton);
  await tester.pumpAndSettle();
  await tester.tap(intentionOption(option));
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
}

/// «Восстановить из архива» в шапке архивированного намерения.
final intentionHeadRestore = find.byKey(
  const ValueKey('intention-details-head-restore'),
);

/// Подтверждение в диалоге «Удалить намерение?».
final intentionDeletionConfirm = _deletionDialogButton(
  (localizations) => localizations.detailsDeleteDialogConfirm,
);

/// Отмена в диалоге «Удалить намерение?».
final intentionDeletionCancel = _deletionDialogButton(
  (localizations) => localizations.detailsDeleteDialogCancel,
);

Finder _deletionDialogButton(String Function(AppLocalizations) label) =>
    find.descendant(
      of: find.byType(Dialog),
      matching: find.byElementPredicate(
        (element) => switch (element.widget) {
          final Button button =>
            button.label == label(AppLocalizations.of(element)),
          _ => false,
        },
      ),
    );

String _optionName(BuildContext context, IntentionOption option) {
  final localizations = AppLocalizations.of(context);
  return switch (option) {
    IntentionOption.edit => localizations.detailsOptionEdit,
    IntentionOption.archive => localizations.detailsOptionArchive,
    IntentionOption.restore => localizations.detailsRestoreFromArchiveAction,
    IntentionOption.delete => localizations.detailsOptionDelete,
  };
}
