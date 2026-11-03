import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../design_system/components/option_row.dart';
import '../../../design_system/components/options_menu.dart';
import '../../../design_system/components/sheet.dart';
import '../../../design_system/doable_icon.dart';
import '../../../intention/domain/intention.dart';
import '../../application/long_term_relation_permissions.dart';
import '../../application/long_term_relation_projection.dart';
import '../../domain/long_term_relation.dart';
import 'relation_details_state.dart';
import 'relation_details_view_model.dart';

/// Действие, выбранное в параметрах связи на её панели.
enum RelationOption { archive, restore, delete }

/// Пункты листа параметров по последнему принятому снимку панели.
///
/// Пока для связи выполняется изменяющая операция, пункты недоступны и просят
/// дождаться её окончания. Исключение — удаление связи из пути дневного выбора:
/// окончание операции его не откроет, поэтому оно сохраняет свою причину.
List<OptionsMenuItem<RelationOption>> relationOptions(
  AppLocalizations localizations,
  RelationDetailsLoaded loaded,
) {
  final busy = loaded.isOperationRunning;
  final wait = localizations.detailsOptionWait;
  final details = loaded.details;

  final stateChange = switch (details.relation.scope) {
    RelationScope.active when busy =>
      OptionsMenuItem<RelationOption>.unavailable(
        icon: DoableIconData.archive,
        name: localizations.relationSheetOptionArchive,
        reason: wait,
      ),
    RelationScope.active => OptionsMenuItem(
      value: RelationOption.archive,
      icon: DoableIconData.archive,
      name: localizations.relationSheetOptionArchive,
    ),
    RelationScope.archived => switch (_restoreBlocker(localizations, details)) {
      final reason? => OptionsMenuItem<RelationOption>.unavailable(
        icon: DoableIconData.unarchive,
        name: localizations.relationSheetOptionRestore,
        reason: reason,
      ),
      null when busy => OptionsMenuItem<RelationOption>.unavailable(
        icon: DoableIconData.unarchive,
        name: localizations.relationSheetOptionRestore,
        reason: wait,
      ),
      null => OptionsMenuItem(
        value: RelationOption.restore,
        icon: DoableIconData.unarchive,
        name: localizations.relationSheetOptionRestore,
      ),
    },
  };

  final deleteBlocker = switch (loaded.permissions.restriction) {
    LongTermRelationPermissionRestriction.referencedByDailyPath =>
      localizations.relationDetailsPathProtection,
    null when busy => wait,
    null => null,
  };
  final delete = deleteBlocker == null
      ? OptionsMenuItem(
          value: RelationOption.delete,
          icon: DoableIconData.delete,
          name: localizations.relationSheetOptionDelete,
          tone: OptionRowTone.danger,
        )
      : OptionsMenuItem<RelationOption>.unavailable(
          icon: DoableIconData.delete,
          name: localizations.relationSheetOptionDelete,
          reason: deleteBlocker,
        );

  return [stateChange, delete];
}

/// Причина, по которой архивированную связь нельзя восстановить: пока
/// архивирован участник, связь не может стать активной.
String? _restoreBlocker(
  AppLocalizations localizations,
  LongTermRelationDetails details,
) {
  final sourceArchived =
      details.source.archiveState == IntentionArchiveState.archived;
  final relatedArchived =
      details.related.archiveState == IntentionArchiveState.archived;
  return switch ((sourceArchived, relatedArchived)) {
    (true, true) => localizations.relationSheetOptionRestoreBothArchived,
    (true, false) => localizations.relationRestoreSourceArchived,
    (false, true) => localizations.relationRestoreRelatedArchived,
    (false, false) => null,
  };
}

/// Лист параметров следит за снимком панели: операция, начатая или
/// завершённая при открытом листе, сразу меняет доступность пунктов.
final class RelationOptionsSheet extends ConsumerWidget {
  const RelationOptionsSheet({
    required this.sheet,
    required this.provider,
    super.key,
  });

  final SheetPresentation sheet;
  final RelationDetailsViewModelProvider provider;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final route = ModalRoute.of(context);
    ref.listen(provider, (_, next) {
      // Без подробных данных параметрам не к чему относиться. Лист, который
      // уже закрывается, не текущий, и панель под ним это не закрывает.
      if (next is! RelationDetailsLoaded && (route?.isCurrent ?? false)) {
        Navigator.of(context).pop();
      }
    });
    final localizations = AppLocalizations.of(context);
    return switch (ref.watch(provider)) {
      final RelationDetailsLoaded loaded => OptionsMenu<RelationOption>(
        sheet,
        title: localizations.relationDetailsTitle,
        items: relationOptions(localizations, loaded),
      ),
      // Лист уже закрывается вслед за утратой данных.
      _ => const SizedBox.shrink(),
    };
  }
}
