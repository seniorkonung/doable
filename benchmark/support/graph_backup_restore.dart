import 'dart:async';
import 'dart:io';

import 'package:doable/src/data_transfer/application/graph_restore.dart';
import 'package:doable/src/data_transfer/application/graph_restore_provider.dart';
import 'package:doable/src/graph/application/graph_command_coordinator.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:doable/src/graph/data/drift_personal_graph_repository.dart';
import 'package:doable/src/graph_backups/graph_backup_registry.dart';
import 'package:doable/src/graph_backups/graph_backups.dart';
import 'package:doable/src/graph_snapshots/graph_log_compaction.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../test/support/in_memory_diagnostics_sink.dart';

/// Восстановление резервной копии графа операцией приложения: модель
/// восстановления передаёт его координатору, как после подтверждения
/// «Восстановить эту копию?», а координатор заменяет граф в монопольном
/// режиме.
final class BenchmarkGraphRestore {
  BenchmarkGraphRestore(
    this._repository, {
    required Directory snapshots,
    required DateTime Function() clock,
  }) : _compaction = GraphLogCompaction(
         log: _repository,
         directory: snapshots,
         clock: clock,
         diagnosticsSink: InMemoryDiagnosticsSink(),
       ),
       _clock = clock {
    _container = ProviderContainer(
      overrides: [
        personalGraphRepositoryProvider.overrideWithValue(_repository),
        graphRestoreControllerProvider.overrideWith(
          () => GraphRestoreController(
            GraphRestore(
              backups: _repository,
              compaction: _compaction,
              replacement: _repository,
              snapshotFiles: Future.value(),
            ),
          ),
        ),
      ],
    );
  }

  final DriftPersonalGraphRepository _repository;
  final GraphLogCompaction _compaction;
  final DateTime Function() _clock;
  late final ProviderContainer _container;

  /// Делает ручную копию текущего состояния графа.
  Future<void> makeManualBackup() async {
    final outcome = await GraphBackups(
      registry: _repository,
      compaction: _compaction,
      clock: _clock,
      diagnosticsSink: InMemoryDiagnosticsSink(),
    ).makeManualBackup();
    if (outcome != ManualGraphBackupOutcome.made) {
      throw StateError('Ручная копия не сделана.');
    }
  }

  /// Единственная ручная копия в реестре.
  Future<GraphBackupEntry> readManualBackup() async =>
      switch (await _repository.watchBackups().first) {
        GraphBackupsReadSucceeded(:final backups) => backups.singleWhere(
          (backup) => backup.kind == GraphBackupKind.manual,
        ),
        GraphBackupsReadFailed() => throw StateError('Копии не прочитаны.'),
      };

  /// Восстанавливает копию [backup] от подтверждения до замены графа;
  /// [onProgress] получает ход обеих фаз.
  Future<void> restore(
    GraphBackupEntry backup, {
    void Function(GraphRestoreProgress progress)? onProgress,
  }) async {
    final subscription = onProgress == null
        ? null
        : _container.listen(graphRestoreControllerProvider, (_, state) {
            if (state case GraphRestoreRunning(:final progress)) {
              onProgress(progress);
            }
          });
    try {
      final start = _container
          .read(graphRestoreControllerProvider.notifier)
          .start(backup);
      final outcome = await (start as GraphBackupRestoreAccepted).future;
      if (outcome is! GraphBackupRestored) {
        throw StateError('Копия не восстановлена: $outcome.');
      }
    } finally {
      subscription?.close();
    }
  }

  Future<void> dispose() async {
    await _container.read(graphCommandCoordinatorProvider.notifier).shutdown();
    _container.dispose();
    await _compaction.shutdown();
  }
}
