import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/widgets.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../app/routing/app_router.gr.dart';
import '../../../intention/domain/intention_id.dart';
import '../../../intention/presentation/catalog/intention_catalog_purpose.dart';
import '../../../intention/presentation/editor/intention_creation_launch.dart';
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
        onCreate: (title, _) {
          final router = context.router;
          final pickerMatchId = context.routeData.matchId;
          if (router.stackData
              .skipWhile((entry) => entry.matchId != pickerMatchId)
              .skip(1)
              .any((entry) => entry.name == IntentionEditorRoute.name)) {
            return;
          }
          unawaited(
            router.push(
              IntentionEditorRoute(
                launch: IntentionCreationForPathStart(
                  initialTitle: title,
                  onCreated: (id) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted &&
                          router.stackData.lastOrNull?.matchId ==
                              pickerMatchId) {
                        unawaited(router.maybePop(id));
                      }
                    });
                  },
                ),
              ),
            ),
          );
        },
      ),
      onOpenDetails: (id) => unawaited(
        context.router.push(IntentionDetailsRoute(intentionId: id)),
      ),
    );
  }
}
