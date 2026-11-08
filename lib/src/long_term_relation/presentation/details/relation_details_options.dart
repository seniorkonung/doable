import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../design_system/components/option_row.dart';
import '../../../design_system/components/options_menu.dart';
import '../../../design_system/components/sheet.dart';
import '../../../design_system/doable_icon.dart';
import '../../../graph/application/personal_graph_repository_provider.dart';
import '../../../intention/application/cascade/intention_cascade.dart';
import '../../domain/long_term_relation.dart';
import 'relation_details_state.dart';
import 'relation_details_view_model.dart';

/// Действие, выбранное в параметрах связи на её панели.
enum RelationOption { archive, restore, delete }

/// Пункты листа параметров по последнему принятому снимку панели.
///
/// Пока для связи выполняется изменяющая операция, пункты недоступны и просят
/// дождаться её окончания.
List<OptionsMenuItem<RelationOption>> relationOptions(
  AppLocalizations localizations,
  RelationDetailsLoaded loaded, {
  CascadePreviewResult? statePreview,
  CascadePreviewResult? deletePreview,
}) {
  final busy = loaded.isOperationRunning;
  final wait = localizations.detailsOptionWait;
  final details = loaded.details;

  final stateHint = switch (statePreview) {
    ArchiveCascadePreview(:final plan) => [
      localizations.relationArchivePathsHint,
      if (plan.withSupporting.departing.isNotEmpty)
        localizations.relationArchiveIntentionsHint(
          plan.withSupporting.departing.length,
        ),
    ].join('; '),
    RestoreCascadePreview(:final plan) => [
      localizations.relationRestorePathsHint,
      if (plan.withSupporting.restored.isNotEmpty)
        localizations.relationRestoreIntentionsHint(
          plan.withSupporting.restored.length,
        ),
    ].join('; '),
    _ => null,
  };
  final deleteHint = switch (deletePreview) {
    RelationDeleteCascadePreview(:final plan) => [
      localizations.detailsOptionDeleteKeepsPaths,
      if (plan.withSupporting.departing.isNotEmpty)
        localizations.relationDeleteIntentionsHint(
          plan.withSupporting.departing.length,
        ),
      if (plan.withSupporting.archivedByInvariant.isNotEmpty)
        localizations.detailsCascadeDeleteArchiveHint(
          plan.withSupporting.archivedByInvariant.length,
        ),
    ].join('; '),
    _ => null,
  };

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
      hint: stateHint,
    ),
    RelationScope.archived when busy =>
      OptionsMenuItem<RelationOption>.unavailable(
        icon: DoableIconData.unarchive,
        name: localizations.relationSheetOptionRestore,
        reason: wait,
      ),
    RelationScope.archived => OptionsMenuItem(
      value: RelationOption.restore,
      icon: DoableIconData.unarchive,
      name: localizations.relationSheetOptionRestore,
      hint: stateHint,
    ),
  };

  final delete = busy
      ? OptionsMenuItem<RelationOption>.unavailable(
          icon: DoableIconData.delete,
          name: localizations.relationSheetOptionDelete,
          reason: wait,
        )
      : OptionsMenuItem(
          value: RelationOption.delete,
          icon: DoableIconData.delete,
          name: localizations.relationSheetOptionDelete,
          hint: deleteHint,
          tone: OptionRowTone.danger,
        );

  return [stateChange, delete];
}

/// Лист параметров следит за снимком панели: операция, начатая или
/// завершённая при открытом листе, сразу меняет доступность пунктов.
final class RelationOptionsSheet extends ConsumerStatefulWidget {
  const RelationOptionsSheet({
    required this.sheet,
    required this.provider,
    super.key,
  });

  final SheetPresentation sheet;
  final RelationDetailsViewModelProvider provider;

  @override
  ConsumerState<RelationOptionsSheet> createState() =>
      _RelationOptionsSheetState();
}

final class _RelationOptionsSheetState
    extends ConsumerState<RelationOptionsSheet> {
  CascadePreviewResult? statePreview;
  CascadePreviewResult? deletePreview;
  int generation = 0;

  @override
  void initState() {
    super.initState();
    final loaded = ref.read(widget.provider);
    if (loaded is RelationDetailsLoaded) _readPreviews(loaded);
  }

  void _readPreviews(RelationDetailsLoaded loaded) {
    final current = ++generation;
    final repository = ref.read(personalGraphRepositoryProvider);
    final subject = RelationCascadeSubject(loaded.details.relation.id);
    final operation = loaded.details.relation.scope == RelationScope.active
        ? CascadeOperation.archive
        : CascadeOperation.restore;
    repository.previewCurrentCascade(subject, operation).then((value) {
      if (mounted && current == generation)
        setState(() => statePreview = value);
    });
    repository.previewCurrentCascade(subject, CascadeOperation.delete).then((
      value,
    ) {
      if (mounted && current == generation)
        setState(() => deletePreview = value);
    });
  }

  @override
  Widget build(BuildContext context) {
    final route = ModalRoute.of(context);
    ref.listen(widget.provider, (previous, next) {
      // Без подробных данных параметрам не к чему относиться. Лист, который
      // уже закрывается, не текущий, и панель под ним это не закрывает.
      if (next is! RelationDetailsLoaded && (route?.isCurrent ?? false)) {
        Navigator.of(context).pop();
      } else if (next is RelationDetailsLoaded &&
          previous is RelationDetailsLoaded &&
          (next.revision != previous.revision ||
              next.details.relation.scope != previous.details.relation.scope)) {
        setState(() {
          statePreview = null;
          deletePreview = null;
        });
        _readPreviews(next);
      }
    });
    final localizations = AppLocalizations.of(context);
    return switch (ref.watch(widget.provider)) {
      final RelationDetailsLoaded loaded => OptionsMenu<RelationOption>(
        widget.sheet,
        title: localizations.relationDetailsTitle,
        items: relationOptions(
          localizations,
          loaded,
          statePreview: statePreview,
          deletePreview: deletePreview,
        ),
      ),
      // Лист уже закрывается вслед за утратой данных.
      _ => const SizedBox.shrink(),
    };
  }
}
