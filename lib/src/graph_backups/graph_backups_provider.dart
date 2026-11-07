import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'graph_backup_registry.dart';
import 'graph_backups.dart';

/// Резервные копии графа на протяжении жизни контейнера приложения.
///
/// Композиция приложения переопределяет провайдер модулем копий, который
/// делает и ежедневные копии, поэтому копии делаются по одной.
final graphBackupsProvider = Provider<GraphBackups>(
  (ref) => throw StateError(
    'Резервные копии графа должны быть предоставлены композицией приложения.',
  ),
);

/// Список копий, пока его показывает хотя бы один экран: экраны делят одно
/// наблюдение, а без них список не перечитывается после каждого изменения.
final graphBackupListProvider = StreamProvider.autoDispose<GraphBackupsRead>(
  (ref) => ref.watch(graphBackupsProvider).watchBackups(),
);

/// Часы устройства, по которым делаются копии; по ним экраны подписывают
/// моменты копий относительно текущего дня.
///
/// Композиция приложения переопределяет провайдер часами модуля копий.
final graphBackupsClockProvider = Provider<DateTime Function()>(
  (ref) => DateTime.now,
);
