/// Общие действия и наблюдения экрана пути.
library;

import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/src/action/domain/action_path.dart';
import 'package:doable/src/action/domain/action_priority.dart';
import 'package:doable/src/action/presentation/path/path_page.dart';
import 'package:doable/src/action/presentation/path_start/path_start_picker_page.dart';
import 'package:doable/src/app/routing/app_router.dart';
import 'package:doable/src/app/routing/app_router.gr.dart';
import 'package:doable/src/design_system/components/button.dart';
import 'package:doable/src/design_system/components/top_bar.dart';
import 'package:doable/src/design_system/doable_icon.dart';
import 'package:doable/src/design_system/doable_theme.dart';
import 'package:doable/src/graph/application/personal_graph_repository.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'in_memory_quick_creation_mode_store.dart';

/// Открытый экран пути. Экран, перекрытый страницей, тоже считается.
Finder get pathScreen => find.byType(PathPage);

/// «Сохранить» в верхней панели экрана пути.
Finder get pathSave => find.descendant(
  of: find.descendant(of: pathScreen, matching: find.byType(TopBar)),
  matching: find.byType(Button),
);

bool isPathSaveEnabled(WidgetTester tester) =>
    tester.widget<Button>(pathSave).onPressed != null;

/// Открывает экран пути над пустой корневой страницей приложения и
/// возвращает то, что экран отдаст вызывающему.
Future<Future<ActionPath?>> openPathScreen(
  WidgetTester tester, {
  required AppRouter router,
  required PersonalGraphRepository repository,
  ActionPath? originalPath,
  PathStartFlow flow = PathStartFlow.newAction,
  String actionTitle = '',
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        inMemoryQuickCreationModeOverride,
        personalGraphRepositoryProvider.overrideWithValue(repository),
      ],
      child: MaterialApp.router(
        theme: doableTheme(Brightness.light),
        locale: const Locale('ru'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router.config(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  final result = router.push<ActionPath>(
    PathRoute(
      flow: flow,
      originalPath: originalPath,
      actionTitle: actionTitle,
      actionPriority: ActionPriority.p4,
    ),
  );
  await settlePathScreen(tester);
  return result;
}

/// Дожидается чтения участка пути: транзакция хранилища завершается только
/// в настоящем времени.
Future<void> settlePathScreen(WidgetTester tester) async {
  await tester.pump();
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 50)),
  );
  await tester.pumpAndSettle();
}

/// Нажимает «Назад» в верхней панели экрана пути.
Future<void> tapPathBack(WidgetTester tester) async {
  await tester.tap(
    find.descendant(
      of: find.descendant(of: pathScreen, matching: find.byType(TopBar)),
      matching: find.byType(DoableIcon),
    ),
  );
  await tester.pumpAndSettle();
}
