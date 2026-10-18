import 'package:flutter_riverpod/flutter_riverpod.dart';

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
