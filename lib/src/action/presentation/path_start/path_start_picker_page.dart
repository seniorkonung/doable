import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/widgets.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../app/routing/app_router.gr.dart';
import '../../../intention/domain/intention_id.dart';
import '../../../intention/presentation/catalog/intention_catalog_purpose.dart';
import '../../../intention/presentation/picker/intention_picker_view.dart';
import 'path_start_picker_purpose.dart';

/// Поток, в котором выбирается начало пути.
enum PathStartFlow { newAction, editPath }

/// Возвращает выбранное намерение или null при закрытии без выбора.
@RoutePage()
final class PathStartPickerPage extends StatefulWidget {
  const PathStartPickerPage({required this.flow, this.currentRoot, super.key});

  final PathStartFlow flow;
  final IntentionId? currentRoot;

  @override
  State<PathStartPickerPage> createState() => _PathStartPickerPageState();
}

final class _PathStartPickerPageState extends State<PathStartPickerPage> {
  late final _purpose = SelectPathStart(
    session: IntentionSearchSession(),
    currentRoot: widget.currentRoot,
  );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return IntentionPickerView(
      purpose: _purpose,
      purposeDescription: pathStartPickerPurpose(l10n, widget.flow),
      closeLabel: l10n.participantPickerCancel,
      emptyScopeMessage: l10n.pathStartPickerEmpty,
      onClose: () => unawaited(context.router.maybePop()),
      rowBehavior: IntentionPickerSingle(
        onPick: (snapshot) =>
            unawaited(context.router.maybePop(snapshot.value.id)),
      ),
      onOpenDetails: (id) => unawaited(
        context.router.push(IntentionDetailsRoute(intentionId: id)),
      ),
    );
  }
}
