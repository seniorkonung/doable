import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/widgets.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../app/routing/app_router.gr.dart';
import '../../../intention/domain/intention_id.dart';
import '../../../intention/presentation/catalog/intention_catalog_purpose.dart';
import '../../../intention/presentation/picker/intention_picker_view.dart';
import '../daily_choice_picker_context.dart';

/// Выбор активного действия перед поиском основания дневного выбора.
///
/// Список использует отдельную сессию ограниченного каталога. Только открытие
/// подробностей читает полный текст выбранного намерения; результат выбора —
/// его идентификатор, поэтому одноимённые действия не смешиваются.
@RoutePage()
final class DailyChoiceActionPickerPage extends StatefulWidget {
  const DailyChoiceActionPickerPage({required this.pickerContext, super.key});

  final DailyChoicePickerContext pickerContext;

  @override
  State<DailyChoiceActionPickerPage> createState() =>
      _DailyChoiceActionPickerPageState();
}

final class _DailyChoiceActionPickerPageState
    extends State<DailyChoiceActionPickerPage> {
  final _purpose = SelectDailyChoiceAction(session: IntentionSearchSession());
  bool _closing = false;
  bool _returnedSelection = false;

  @override
  void dispose() {
    if (!_returnedSelection) widget.pickerContext.cancelLaunch();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // PopScope сообщает о закрытии именно этого маршрута, а не его дочерних
    // страниц: https://api.flutter.dev/flutter/widgets/PopScope-class.html
    return PopScope<IntentionId>(
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) return;
        _returnedSelection = result != null;
        if (!_returnedSelection) widget.pickerContext.cancelLaunch();
      },
      child: IntentionPickerView(
        purpose: _purpose,
        closeLabel: switch (widget.pickerContext) {
          InitialDailyChoicePickerContext() => l10n.creationCancelAction,
          PathReplacementDailyChoicePickerContext() => l10n.actionPickerCancel,
        },
        emptyScopeMessage: l10n.actionPickerEmpty,
        onClose: () => unawaited(_close()),
        onPick: (pick) => unawaited(_close(pick.value.id)),
        onOpenDetails: (id) {
          if (!_canSelect) return;
          unawaited(
            context.router.push(IntentionDetailsRoute(intentionId: id)),
          );
        },
      ),
    );
  }

  bool get _ownsTopRoute =>
      mounted &&
      context.router.stackData.lastOrNull?.matchId ==
          context.routeData.matchId &&
      !context.router.hasPagelessTopRoute;

  bool get _canSelect =>
      _ownsTopRoute && !_closing && widget.pickerContext.canContinue;

  Future<void> _close([IntentionId? id]) async {
    if (!_ownsTopRoute || _closing) return;
    if (id != null && !widget.pickerContext.canContinue) return;
    _closing = true;
    if (id == null) widget.pickerContext.cancelLaunch();
    try {
      await context.router.maybePop(id);
    } finally {
      _closing = false;
    }
  }
}
