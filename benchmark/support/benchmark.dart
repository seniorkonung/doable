import 'dart:convert';
import 'dart:io';

const benchmarkSamples = int.fromEnvironment(
  'BENCHMARK_SAMPLES',
  defaultValue: 1,
);
const benchmarkWarmups = int.fromEnvironment(
  'BENCHMARK_WARMUPS',
  defaultValue: 0,
);
final _caseFilter = RegExp(const String.fromEnvironment('BENCHMARK_CASE'));

bool benchmarkIncludes(String name) {
  if (benchmarkSamples < 1 || benchmarkWarmups < 0) {
    throw ArgumentError(
      'Нужны положительное число замеров и неотрицательный прогрев',
    );
  }
  return _caseFilter.hasMatch(name);
}

double benchmarkP95(List<Duration> samples) {
  if (samples.length != benchmarkSamples) {
    throw StateError(
      'Серия содержит ${samples.length} замеров вместо $benchmarkSamples',
    );
  }
  final values = samples.map((value) => value.inMicroseconds).toList()..sort();
  return values[(values.length * 0.95).ceil() - 1] / 1000;
}

/// Время — результат измерения; ошибки точности по-прежнему отклоняют запуск.
void reportBenchmarkBudget(
  String benchmarkCase,
  String metric,
  List<Duration> samples,
  int limitMs,
) {
  final actual = benchmarkP95(samples);
  final comparable = benchmarkSamples >= 40 && benchmarkWarmups >= 3;
  stdout.writeln(
    jsonEncode({
      'case': benchmarkCase,
      'metric': metric,
      'p95Ms': actual,
      'budgetMs': limitMs,
      'samples': benchmarkSamples,
      'warmups': benchmarkWarmups,
      'budgetStatus': !comparable
          ? 'smoke'
          : actual <= limitMs
          ? 'withinBudget'
          : 'exceeded',
    }),
  );
}
