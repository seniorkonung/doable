import 'dart:async';

import 'package:doable/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'quick_creation_mode.dart';
import 'quick_creation_mode_controller.dart';
import 'quick_creation_mode_presentation.dart';

/// Открывает выбор режима над всей текущей страницей, включая её навигацию.
/// Выбор применяется без ожидания записи и не запускает создание.
///
/// Корневой модальный маршрут изолирует фон и забирает фокус:
/// https://api.flutter.dev/flutter/material/showModalBottomSheet.html
Future<void> showQuickCreationModeMenu(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    useSafeArea: true,
    isScrollControlled: true,
    requestFocus: true,
    showDragHandle: true,
    builder: (_) => const _QuickCreationModeMenu(),
  );
}

final class _QuickCreationModeMenu extends ConsumerWidget {
  const _QuickCreationModeMenu();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final localizations = AppLocalizations.of(context);
    final selected = ref.watch(quickCreationModeControllerProvider);
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Semantics(
                header: true,
                child: Text(
                  localizations.quickCreationMenuTitle,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
            ),
            for (final mode in QuickCreationMode.values)
              ListTile(
                leading: Icon(mode.icon),
                title: Text(mode.title(localizations)),
                selected: mode == selected,
                autofocus: mode == selected,
                trailing: mode == selected ? const Icon(Icons.check) : null,
                onTap: () {
                  unawaited(
                    ref
                        .read(quickCreationModeControllerProvider.notifier)
                        .select(mode),
                  );
                  Navigator.of(context).pop();
                },
              ),
          ],
        ),
      ),
    );
  }
}
