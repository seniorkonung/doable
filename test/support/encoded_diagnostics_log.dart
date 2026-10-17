import 'dart:convert';

import 'package:doable/src/shared/diagnostics/developer_diagnostics_sink.dart';
import 'package:doable/src/shared/diagnostics/diagnostics_sink.dart';

/// Получатель, который кодирует события так же, как журнал разработчика.
///
/// Длительность у каждого запуска своя, поэтому [events] отдаёт события без
/// неё.
final class EncodedDiagnosticsLog implements DiagnosticsSink {
  final _messages = <String>[];
  late final _sink = DeveloperDiagnosticsSink(_messages.add);

  @override
  void record(DiagnosticsEvent event) => _sink.record(event);

  List<Map<String, Object?>> get events => [
    for (final message in _messages)
      (jsonDecode(message) as Map<String, Object?>)..remove('durationMicros'),
  ];
}
