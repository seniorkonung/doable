import 'dart:async';

import 'package:doable/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../daily_choice/presentation/catalog/daily_choice_local_date_provider.dart';
import '../../daily_choice/presentation/catalog/daily_choice_local_day_observer.dart';
import '../../design_system/components/notice.dart';
import '../../design_system/components/option_row.dart';
import '../../design_system/doable_colors.dart';
import '../../design_system/doable_icon.dart';
import '../../design_system/doable_metrics.dart';
import '../../design_system/doable_type.dart';
import '../../graph/application/graph_command_coordinator.dart';
import '../../graph/presentation/operation_failure_presentation.dart';
import '../../graph_backups/graph_backup_registry.dart';
import '../../graph_backups/graph_backups_provider.dart';
import '../application/graph_composition.dart';
import '../application/graph_composition_provider.dart';
import '../application/graph_export_provider.dart';
import '../application/graph_import_provider.dart';
import '../application/graph_restore_provider.dart';
import 'backup_descriptions.dart';
import 'backups_sheet.dart';
import 'export_data_sheet.dart';
import 'graph_import_failure_message.dart';
import 'restore_backup_confirmation.dart';

/// Раздел «Данные» страницы «Настройки»: пояснение, что граф хранится только
/// на устройстве, и строки операций с данными.
final class SettingsDataSection extends StatelessWidget {
  const SettingsDataSection({super.key});

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final colors = Theme.of(context).extension<DoableColors>()!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Заголовок и пояснение выровнены по значкам строк.
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: DoableMetrics.space2),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(
                header: true,
                child: Text(
                  localizations.dataSectionTitle,
                  style: DoableType.section.copyWith(color: colors.ink),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                localizations.dataSectionLocalOnly,
                style: DoableType.hint.copyWith(color: colors.muted),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        const _BackupsRow(),
        const _ExportRow(),
        const _ImportRow(),
      ],
    );
  }
}

/// Сколько после копии строка «Резервные копии» сообщает, что она сделана
/// только что.
const _justNowWindow = Duration(minutes: 1);

/// Строка «Резервные копии» открывает панель копий и сообщает, когда сделана
/// последняя по созданию копия. Без копий пустой граф копировать нечего, а
/// отказ чтения копий не выдаётся за их отсутствие.
///
/// Строка начинает восстановление копии, подтверждённое в панели, и по праву
/// инициатора (ADR-0012) предъявляет под собой его отказ, пока открыта
/// страница. Успех предъявляет общая поверхность результатов.
final class _BackupsRow extends ConsumerStatefulWidget {
  const _BackupsRow();

  @override
  ConsumerState<_BackupsRow> createState() => _BackupsRowState();
}

/// Отказ восстановления копии [backup], который строка предъявляет по праву
/// [claim].
final class _RestoreFailure {
  const _RestoreFailure(
    this.backup, {
    required this.isStorageFull,
    required this.claim,
  });

  final GraphBackupEntry backup;

  /// Восстановлению не хватило места; после того как место освобождено, его
  /// можно повторить.
  final bool isStorageFull;
  final GraphInitiatorPresentationClaim? claim;
}

final class _BackupsRowState extends ConsumerState<_BackupsRow> {
  late final GraphCommandCoordinator _coordinator;

  /// Перестраивает строку, когда подпись «только что» перестаёт быть верной.
  Timer? _justNowExpiry;

  /// Перестраивает строку с началом другой местной даты, чтобы день
  /// последней копии назывался относительно нового сегодня.
  late final DailyChoiceLocalDayObserver _localDay;

  /// Восстановление, начатое строкой, пока она ждёт его исхода или
  /// предъявляет его отказ.
  GraphBackupRestoreOperationToken? _restoreToken;
  _RestoreFailure? _restoreFailure;

  @override
  void initState() {
    super.initState();
    _coordinator = ref.read(graphCommandCoordinatorProvider.notifier);
    _localDay = DailyChoiceLocalDayObserver(
      readLocalDay: ref.read(dailyChoiceLocalDateSourceProvider),
      onTodayChanged: () => setState(() {}),
    );
  }

  @override
  void dispose() {
    _justNowExpiry?.cancel();
    _localDay.dispose();
    _releaseRestorePresentation();
    super.dispose();
  }

  /// Неподтверждённый отказ прежнего восстановления переходит к общей
  /// поверхности результатов.
  void _releaseRestorePresentation() {
    if (_restoreToken case final token?) {
      _coordinator.releaseInitiatorPresentation(token);
    }
    _restoreToken = null;
  }

  Future<void> _openSheet() async {
    final backup = await showBackupsSheet(context);
    if (backup != null && mounted) await _restore(backup);
  }

  /// Снова открывает подтверждение восстановления копии [backup]: пока
  /// освобождалось место, граф мог измениться, поэтому изменения с тех пор
  /// считаются заново.
  Future<void> _retryRestore(GraphBackupEntry backup) async {
    final confirmed = await confirmBackupRestore(
      context,
      backup: backup,
      changesSince: ref
          .read(graphRestoreControllerProvider.notifier)
          .countChangesSince(backup),
    );
    if (confirmed && mounted) await _restore(backup);
  }

  Future<void> _restore(GraphBackupEntry backup) async {
    _releaseRestorePresentation();
    setState(() => _restoreFailure = null);
    switch (ref.read(graphRestoreControllerProvider.notifier).start(backup)) {
      case GraphBackupRestoreAccepted(:final token, :final future):
        _restoreToken = token;
        final outcome = await future;
        if (!mounted || !identical(_restoreToken, token)) return;
        switch (outcome) {
          case GraphBackupRestoreFailed() || GraphBackupRestoreStorageFull():
            setState(
              () => _restoreFailure = _RestoreFailure(
                backup,
                isStorageFull: outcome is GraphBackupRestoreStorageFull,
                claim: _coordinator.claimInitiatorFailure(token),
              ),
            );
          // Успех предъявляет общая поверхность, а отмена сообщения не даёт.
          case GraphBackupRestored() || GraphBackupRestoreCancelled():
            _restoreToken = null;
        }
      // Восстановление не принято: идёт другая замена графа или приложение
      // завершает работу.
      case GraphReplacementAlreadyRunning() ||
          GraphCommandCoordinatorDraining():
    }
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final failure = _restoreFailure;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _row(localizations),
        if (failure != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              DoableMetrics.space2,
              0,
              DoableMetrics.space2,
              DoableMetrics.space2,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                OperationFailurePresentation(
                  claim: failure.claim,
                  message: failure.isStorageFull
                      ? localizations.dataReplacementStorageFull
                      : localizations.dataBackupRestoreFailed,
                ),
                if (failure.isStorageFull)
                  TextButton(
                    onPressed: () => unawaited(_retryRestore(failure.backup)),
                    child: Text(localizations.commonRetry),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  /// Строка по прочитанным копиям и составу графа.
  OptionRow _row(AppLocalizations localizations) {
    OptionRow row({String? hint, VoidCallback? onPressed}) => OptionRow(
      icon: DoableIconData.backups,
      name: localizations.dataBackupsTitle,
      hint: hint,
      onPressed: onPressed,
    );
    void openSheet() => unawaited(_openSheet());
    return switch ((
      ref.watch(graphBackupListProvider).value,
      ref.watch(graphCompositionProvider).value,
    )) {
      // Пока копии не прочитаны, неизвестно, есть ли последняя копия.
      (null, _) => row(),
      (GraphBackupsReadSucceeded(backups: [final last, ...]), _) => row(
        hint: _lastBackupText(localizations, last.madeAt),
        onPressed: openSheet,
      ),
      // Пока состав не прочитан, неизвестно, есть ли что копировать.
      (GraphBackupsReadSucceeded(), null) => row(
        hint: localizations.dataBackupsNone,
      ),
      (
        GraphBackupsReadSucceeded(),
        GraphCompositionReadSucceeded(:final composition),
      )
          when composition.isEmpty =>
        row(hint: localizations.dataBackupsNothing),
      // Отказ чтения состава не означает пустого графа.
      (
        GraphBackupsReadSucceeded(),
        GraphCompositionReadSucceeded() || GraphCompositionReadFailed(),
      ) =>
        row(hint: localizations.dataBackupsNone, onPressed: openSheet),
      // Отказ чтения не означает, что копий нет.
      (GraphBackupsReadFailed(), _) => row(onPressed: openSheet),
    };
  }

  /// Когда сделана последняя копия с моментом [madeAt]: только что, а затем
  /// день и время по правилам локали.
  String _lastBackupText(AppLocalizations localizations, DateTime madeAt) {
    final now = ref.watch(graphBackupsClockProvider)();
    final elapsed = now.difference(madeAt);
    _justNowExpiry?.cancel();
    // Копия с моментом позже текущего сделана до перевода часов назад.
    if (!elapsed.isNegative && elapsed < _justNowWindow) {
      _justNowExpiry = Timer(_justNowWindow - elapsed, () {
        if (mounted) setState(() {});
      });
      return localizations.dataBackupsLastJustNow;
    }
    return switch (BackupMoment.of(context, madeAt, now: now)) {
      BackupMadeToday(:final time) => localizations.dataBackupsLastToday(time),
      BackupMadeYesterday(:final time) =>
        localizations.dataBackupsLastYesterday(time),
      BackupMadeEarlier(:final date, :final time) =>
        localizations.dataBackupsLastOn(date, time),
    };
  }
}

/// Строка «Экспорт данных» открывает панель экспорта. Пустой граф
/// экспортировать нельзя, а пока экспорт идёт, строка показывает его ход и
/// не принимает выбор.
final class _ExportRow extends ConsumerWidget {
  const _ExportRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final localizations = AppLocalizations.of(context);
    OptionRow row({
      required String hint,
      VoidCallback? onPressed,
      OptionRowProgress? progress,
    }) => OptionRow(
      icon: DoableIconData.export,
      name: localizations.dataExportTitle,
      hint: hint,
      onPressed: onPressed,
      progress: progress,
    );
    return switch ((
      ref.watch(graphExportControllerProvider),
      ref.watch(graphCompositionProvider).value,
    )) {
      (GraphExportRunning(:final progress), _) => row(
        hint: localizations.dataExportRunning,
        progress: OptionRowProgress(
          share: progress,
          label: localizations.dataExportProgress(progress),
        ),
      ),
      // Пока состав не прочитан, неизвестно, есть ли что экспортировать.
      (GraphExportIdle(), null) => row(hint: localizations.dataExportHint),
      (GraphExportIdle(), GraphCompositionReadSucceeded(:final composition))
          when composition.isEmpty =>
        row(hint: localizations.dataExportNothing),
      // Отказ чтения состава не означает пустого графа.
      (
        GraphExportIdle(),
        GraphCompositionReadSucceeded() || GraphCompositionReadFailed(),
      ) =>
        row(
          hint: localizations.dataExportHint,
          onPressed: () => showExportDataSheet(context),
        ),
    };
  }
}

/// Строка «Импорт данных» доступна всегда, в том числе пока идёт экспорт, и
/// начинает импорт файла экспорта. Пустой граф она предлагает вернуть из
/// файла, а отказ чтения состава не выдаётся за пустой граф.
///
/// Отказ начатого строкой импорта она по праву инициатора (ADR-0012)
/// предъявляет под собой, пока открыта страница, с действием, которое снова
/// начинает импорт, если отказ так можно исправить. Успех предъявляет общая
/// поверхность результатов.
final class _ImportRow extends ConsumerStatefulWidget {
  const _ImportRow();

  @override
  ConsumerState<_ImportRow> createState() => _ImportRowState();
}

/// Отказ импорта [failure], который строка предъявляет по праву [claim].
final class _ImportFailure {
  const _ImportFailure(this.failure, {required this.claim});

  final GraphImportFailure failure;
  final GraphInitiatorPresentationClaim? claim;
}

final class _ImportRowState extends ConsumerState<_ImportRow> {
  late final GraphCommandCoordinator _coordinator;

  /// Импорт, начатый строкой, пока она ждёт его исхода или предъявляет его
  /// отказ.
  GraphImportOperationToken? _importToken;
  _ImportFailure? _importFailure;

  @override
  void initState() {
    super.initState();
    _coordinator = ref.read(graphCommandCoordinatorProvider.notifier);
  }

  @override
  void dispose() {
    _releaseImportPresentation();
    super.dispose();
  }

  /// Неподтверждённый отказ прежнего импорта переходит к общей поверхности
  /// результатов.
  void _releaseImportPresentation() {
    if (_importToken case final token?) {
      _coordinator.releaseInitiatorPresentation(token);
    }
    _importToken = null;
  }

  /// Начинает импорт с системного диалога выбора файла и убирает прежний
  /// отказ.
  Future<void> _import() async {
    _releaseImportPresentation();
    setState(() => _importFailure = null);
    final accepted = await ref
        .read(graphImportControllerProvider.notifier)
        .start();
    // Импорт отменён, от замены отказались, или координатор его не принял.
    if (accepted == null) return;
    _importToken = accepted.token;
    // Страница закрыта, пока импорт ещё не был принят.
    if (!mounted) {
      _releaseImportPresentation();
      return;
    }
    final outcome = await accepted.future;
    if (!mounted || !identical(_importToken, accepted.token)) return;
    switch (outcome) {
      case GraphImportFailed(:final failure):
        setState(
          () => _importFailure = _ImportFailure(
            failure,
            claim: _coordinator.claimInitiatorFailure(accepted.token),
          ),
        );
      // Успех предъявляет общая поверхность, а отмена сообщения не даёт.
      case GraphImported() || GraphImportCancelled():
        _importToken = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final failure = _importFailure;
    void import() => unawaited(_import());
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OptionRow(
          icon: DoableIconData.import,
          name: localizations.dataImportTitle,
          hint: switch (ref.watch(graphCompositionProvider).value) {
            GraphCompositionReadSucceeded(:final composition)
                when composition.isEmpty =>
              localizations.dataImportHintEmptyGraph,
            // Пока состав не прочитан и после отказа его чтения неизвестно,
            // пуст ли граф.
            null ||
            GraphCompositionReadSucceeded() ||
            GraphCompositionReadFailed() => localizations.dataImportHint,
          },
          onPressed: import,
        ),
        if (failure != null)
          Padding(
            // Сообщение выровнено по значку строки.
            padding: const EdgeInsets.fromLTRB(
              DoableMetrics.space2,
              DoableMetrics.space1,
              DoableMetrics.space2,
              DoableMetrics.space2,
            ),
            child: Notice.content(
              message: OperationFailurePresentation(
                claim: failure.claim,
                message: graphImportFailureMessage(
                  localizations,
                  failure.failure,
                ),
                inheritsColor: true,
              ),
              // Право на прежний документ и временные файлы к этому моменту
              // отпущены и удалены, поэтому исправление — новый импорт.
              action: switch (failure.failure) {
                GraphImportFailure.invalidFile => (
                  label: localizations.dataImportChooseAnotherFile,
                  onPressed: import,
                ),
                GraphImportFailure.storageFull ||
                GraphImportFailure.documentUnreadable => (
                  label: localizations.commonRetry,
                  onPressed: import,
                ),
                GraphImportFailure.newerFormatVersion ||
                GraphImportFailure.unknown => null,
              },
            ),
          ),
      ],
    );
  }
}
