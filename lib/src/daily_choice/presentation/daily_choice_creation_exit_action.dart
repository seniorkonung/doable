import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/widgets.dart';

import '../../shared/presentation/creation_exit_action.dart';
import 'daily_choice_creation_completion.dart';
import 'daily_choice_creation_flow_session.dart';

/// Все оставшиеся страницы наблюдают одну сессию, включая повтор выхода.
final class DailyChoiceCreationExitAction extends StatefulWidget {
  const DailyChoiceCreationExitAction({
    required this.session,
    required this.ownerMatchId,
    this.previewRoute,
    super.key,
  });

  final DailyChoiceCreationFlowSession session;
  final LocalKey ownerMatchId;
  final Route<void>? previewRoute;

  @override
  State<DailyChoiceCreationExitAction> createState() =>
      _DailyChoiceCreationExitActionState();
}

final class _DailyChoiceCreationExitActionState
    extends State<DailyChoiceCreationExitAction> {
  @override
  void initState() {
    super.initState();
    widget.session.changes.addListener(_changed);
  }

  void _changed() {
    // Право создания прекращается синхронно; отрисовка ждёт освобождения
    // дерева, если корень завершил сессию во время своего dispose.
    scheduleMicrotask(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void didUpdateWidget(DailyChoiceCreationExitAction oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.session, widget.session)) {
      oldWidget.session.changes.removeListener(_changed);
      widget.session.changes.addListener(_changed);
    }
  }

  @override
  void deactivate() {
    // Корень может завершить сессию в dispose при уже неактивных потомках.
    // Отключаем UI раньше, сохраняя синхронную утрату прав самой сессией:
    // https://api.flutter.dev/flutter/widgets/State/deactivate.html
    widget.session.changes.removeListener(_changed);
    super.deactivate();
  }

  @override
  void activate() {
    super.activate();
    widget.session.changes.addListener(_changed);
  }

  @override
  void dispose() {
    widget.session.changes.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final router = context.router.root;
    final session = widget.session;
    return CreationExitAction(
      state: switch (session.state) {
        DailyChoiceCreationFlowEditing() => CreationExitState.cancellable,
        DailyChoiceCreationFlowSubmitting() ||
        DailyChoiceCreationFlowLeft(
          lastActiveState: DailyChoiceCreationFlowSubmitting(),
        ) => CreationExitState.submitting,
        DailyChoiceCreationFlowSaved() ||
        DailyChoiceCreationFlowLeft() => CreationExitState.terminal,
      },
      onExit: () => leaveDailyChoiceCreation(
        router: router,
        session: session,
        ownerMatchId: widget.ownerMatchId,
        previewRoute: widget.previewRoute,
      ),
    );
  }
}
