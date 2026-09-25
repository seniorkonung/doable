import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../app/routing/app_router.gr.dart';
import '../../../intention/domain/intention_id.dart';
import '../../application/choice_path_draft.dart';
import '../../domain/daily_choice_id.dart';
import '../path/choice_path_page.dart';
import 'daily_choice_path_replace_page.dart';

/// Выбор нового маршрута и отдельное подтверждение для той же дневной связи.
final class DailyChoicePathReplacementFlow extends StatefulWidget {
  const DailyChoicePathReplacementFlow({required this.choiceId, super.key});

  final DailyChoiceId choiceId;

  @override
  State<DailyChoicePathReplacementFlow> createState() =>
      _DailyChoicePathReplacementFlowState();
}

final class _DailyChoicePathReplacementFlowState
    extends State<DailyChoicePathReplacementFlow> {
  bool _opening = false;

  Future<void> _choose(ChoicePathDraftDirection direction) async {
    if (_opening) return;
    setState(() => _opening = true);
    try {
      final router = context.router;
      final startingId = switch (direction) {
        ChoicePathDraftDirection.topDown => await router.push<IntentionId>(
          const DailyChoiceSourcePickerRoute(),
        ),
        ChoicePathDraftDirection.bottomUp => await router.push<IntentionId>(
          const DailyChoiceActionPickerRoute(),
        ),
      };
      if (!mounted || startingId == null) return;

      final selection = await Navigator.of(context).push<ChoicePathSelection>(
        MaterialPageRoute(
          builder: (_) => ChoicePathPage.forReplacement(
            startingIntentionId: startingId,
            direction: direction,
          ),
        ),
      );
      if (!mounted || selection == null) return;

      final replacedId = await Navigator.of(context).push<DailyChoiceId>(
        MaterialPageRoute(
          builder: (_) => DailyChoicePathReplacePage(
            choiceId: widget.choiceId,
            path: selection.path,
            steps: selection.steps,
            direction: direction,
          ),
        ),
      );
      if (mounted && replacedId == widget.choiceId) {
        Navigator.of(context).pop();
      }
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.dailyChoiceReplaceChooseDirection)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              l10n.dailyChoiceReplaceChooseDirectionDescription,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              key: const ValueKey('daily-choice-replace-top-down'),
              onPressed: _opening
                  ? null
                  : () => unawaited(_choose(ChoicePathDraftDirection.topDown)),
              icon: const Icon(Icons.arrow_downward),
              label: Text(l10n.dailyChoiceReplaceFromSource),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              key: const ValueKey('daily-choice-replace-bottom-up'),
              onPressed: _opening
                  ? null
                  : () => unawaited(_choose(ChoicePathDraftDirection.bottomUp)),
              icon: const Icon(Icons.arrow_upward),
              label: Text(l10n.dailyChoiceReplaceFromAction),
            ),
          ],
        ),
      ),
    );
  }
}
