import 'package:doable/src/shared/diagnostics/diagnostics_sink.dart';

final class InMemoryDiagnosticsSink implements DiagnosticsSink {
  final List<DiagnosticsEvent> _events = [];

  List<DiagnosticsEvent> get events => List.unmodifiable(_events);

  @override
  void record(DiagnosticsEvent event) {
    _events.add(event);
  }
}
