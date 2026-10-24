import 'dart:async';

import 'package:doable/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../design_system/components/action_sheet.dart';
import '../../design_system/components/option_row.dart';
import '../../design_system/components/sheet.dart';
import 'quick_creation_mode.dart';
import 'quick_creation_mode_controller.dart';
import 'quick_creation_mode_presentation.dart';

/// Открывает выбор режима над всей текущей страницей, включая её навигацию.
/// Выбор применяется без ожидания записи и не запускает создание.
Future<void> showQuickCreationModeMenu(BuildContext context) {
  return showDoableSheet<void>(
    context: context,
    builder: (_, sheet) => _QuickCreationModeMenu(sheet),
  );
}

final class _QuickCreationModeMenu extends ConsumerWidget {
  const _QuickCreationModeMenu(this.sheet);

  final SheetPresentation sheet;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final localizations = AppLocalizations.of(context);
    final selected = ref.watch(quickCreationModeControllerProvider);
    return ActionSheet(
      sheet,
      title: localizations.quickCreationMenuTitle,
      text: localizations.quickCreationMenuPrompt,
      options: [
        for (final mode in QuickCreationMode.values)
          OptionRow(
            icon: mode.icon,
            name: mode.title(localizations),
            hint: mode.hint(localizations),
            trailing: mode == selected
                ? OptionRowTrailing.selected
                : OptionRowTrailing.none,
            autofocus: mode == selected,
            onPressed: () {
              unawaited(
                ref
                    .read(quickCreationModeControllerProvider.notifier)
                    .select(mode),
              );
              Navigator.of(context).pop();
            },
          ),
      ],
    );
  }
}
