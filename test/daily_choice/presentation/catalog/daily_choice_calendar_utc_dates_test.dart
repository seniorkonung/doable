import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

/// Каталог календарного компонента относительно корня пакета: проверяется
/// каждый файл `daily_choice_calendar*.dart`, в том числе добавленный позже.
const _catalogDirectory = 'lib/src/daily_choice/presentation/catalog/';
const _calendarFilePrefix = 'daily_choice_calendar';

/// Предметная дата, части которой компонент переводит в технические даты
/// библиотеки и обратно.
const _calendarDatePath = 'lib/src/daily_choice/domain/calendar_date.dart';

// Календарный компонент передаёт библиотеке технические даты в UTC и читает из
// них только календарные части. Дата в местном времени процесса сдвигает день
// или неделю лишь в отдельных часовых поясах и на отдельных датах, поэтому
// проверка ищет такие конструкции в исходниках и не зависит от часового пояса,
// в котором выполняется.
void main() {
  test('исходники календарного компонента не получают даты в местном времени процесса', () {
    final root = Directory.current.uri;
    final paths = [
      for (final entity in Directory.fromUri(
        root.resolve(_catalogDirectory),
      ).listSync())
        if (entity is File &&
            entity.uri.pathSegments.last.startsWith(_calendarFilePrefix) &&
            entity.uri.pathSegments.last.endsWith('.dart'))
          '$_catalogDirectory${entity.uri.pathSegments.last}',
      _calendarDatePath,
    ]..sort();
    expect(
      paths,
      containsAll([
        '${_catalogDirectory}daily_choice_calendar.dart',
        _calendarDatePath,
      ]),
    );

    final usages = [
      for (final path in paths)
        ..._localTimeUsages(
          path,
          File.fromUri(root.resolve(path)).readAsStringSync(),
        ),
    ];

    expect(
      [for (final usage in usages) '$usage'],
      isEmpty,
      reason:
          'Календарный компонент получает даты в местном времени процесса. '
          'Технические даты строятся через DateTime.utc, а календарные части '
          'читаются без toLocal().',
    );
  });

  group('поиск дат в местном времени', () {
    for (final (code, construct) in [
      (
        'DateTime(date.year, date.month, date.day)',
        _LocalTimeConstruct.constructor,
      ),
      ('new DateTime(2026, 10, 4)', _LocalTimeConstruct.constructor),
      ('DateTime.new(2026, 10, 4)', _LocalTimeConstruct.constructorTearOff),
      ('dates.map(DateTime.new)', _LocalTimeConstruct.constructorTearOff),
      ('DateTime.now()', _LocalTimeConstruct.now),
      ('day.toLocal().year', _LocalTimeConstruct.toLocal),
      ('day?.toLocal()', _LocalTimeConstruct.toLocal),
      ("DateTime.parse('2026-10-04')", _LocalTimeConstruct.parse),
      ('DateTime.tryParse(value)', _LocalTimeConstruct.tryParse),
      (
        'DateTime.fromMillisecondsSinceEpoch(0)',
        _LocalTimeConstruct.fromMillisecondsSinceEpoch,
      ),
      (
        'DateTime.fromMillisecondsSinceEpoch(0, isUtc: false)',
        _LocalTimeConstruct.fromMillisecondsSinceEpoch,
      ),
      (
        'DateTime.fromMicrosecondsSinceEpoch(0, isUtc: utc)',
        _LocalTimeConstruct.fromMicrosecondsSinceEpoch,
      ),
      (
        'values.map(DateTime.fromMicrosecondsSinceEpoch)',
        _LocalTimeConstruct.fromMicrosecondsSinceEpoch,
      ),
    ]) {
      test('находит ${construct.label} в «$code» и называет файл и строку', () {
        final usages = _localTimeUsages(
          'lib/example.dart',
          'import "a.dart";\n\nfinal value = $code;\n',
        );

        expect(usages, hasLength(1));
        expect(usages.single.construct, construct);
        expect(usages.single.line, 3);
        expect(
          usages.single.toString(),
          allOf(
            startsWith('lib/example.dart:3:'),
            contains(': ${construct.label} — final value = $code;'),
          ),
        );
      });
    }

    test('пропускает DateTime.utc, константы, типы и комментарии', () {
      const source = r'''
/// Технический `DateTime(...)` вместо `DateTime.now()` и `toLocal()`.
DateTime _technicalDate(CalendarDate date) =>
    DateTime.utc(date.year, date.month, date.day);
// DateTime.parse(value)
/* DateTime(2026) /* вложенный DateTime.now() */ day.toLocal() */
final days = DateTime.daysPerWeek * DateTime.monday;
DateTime? focused;
final List<DateTime> visible = <DateTime>[];
DateTime Function(DateTime day) normalize = (day) => day;
final isTechnical = focused is DateTime;
final DateTime(:year, month: final month) = focused!;
final millis = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
final micros = DateTime.fromMicrosecondsSinceEpoch(
  int.parse('0'),
  isUtc: true,
);
''';

      expect(_localTimeUsages('lib/example.dart', source), isEmpty);
    });

    test('пропускает содержимое строк, но проверяет код интерполяций', () {
      const source = r'''
final text = 'DateTime(2026) DateTime.now() ${focused.year}';
final raw = r'${DateTime.now()}';
final multiline = """
  day.toLocal()
""";
final url = 'https://example.com/*'; final local = DateTime(2026);
final interpolated = 'Сегодня: ${DateTime.now()} \'${day.toLocal()}\'';
''';

      expect(
        [
          for (final usage in _localTimeUsages('lib/example.dart', source))
            (usage.line, usage.construct),
        ],
        [
          (6, _LocalTimeConstruct.constructor),
          (7, _LocalTimeConstruct.now),
          (7, _LocalTimeConstruct.toLocal),
        ],
      );
    });
  });
}

/// Конструкция, которая создаёт или читает дату в местном времени процесса.
enum _LocalTimeConstruct {
  constructor('DateTime(...)', r'\bDateTime\s*\('),
  constructorTearOff('DateTime.new', r'\bDateTime\s*\.\s*new\b'),
  now('DateTime.now()', r'\bDateTime\s*\.\s*now\b'),
  toLocal('toLocal()', r'\.\s*toLocal\b'),
  parse('DateTime.parse', r'\bDateTime\s*\.\s*parse\b'),
  tryParse('DateTime.tryParse', r'\bDateTime\s*\.\s*tryParse\b'),
  fromMillisecondsSinceEpoch(
    'DateTime.fromMillisecondsSinceEpoch без isUtc: true',
    r'\bDateTime\s*\.\s*fromMillisecondsSinceEpoch\b(?:\s*\()?',
  ),
  fromMicrosecondsSinceEpoch(
    'DateTime.fromMicrosecondsSinceEpoch без isUtc: true',
    r'\bDateTime\s*\.\s*fromMicrosecondsSinceEpoch\b(?:\s*\()?',
  );

  const _LocalTimeConstruct(this.label, this.pattern);

  final String label;

  /// Выражение, совпадение с которым заканчивается открывающей скобкой
  /// аргументов, если она у конструкции есть.
  final String pattern;
}

final class _LocalTimeUsage {
  const _LocalTimeUsage({
    required this.path,
    required this.line,
    required this.column,
    required this.construct,
    required this.sourceLine,
  });

  final String path;

  /// Номера строки и символа в ней, начиная с 1.
  final int line;
  final int column;
  final _LocalTimeConstruct construct;
  final String sourceLine;

  @override
  String toString() =>
      '$path:$line:$column: ${construct.label} — ${sourceLine.trim()}';
}

/// Конструкции [_LocalTimeConstruct] в коде [source] в порядке их положения.
List<_LocalTimeUsage> _localTimeUsages(String path, String source) {
  final code = _maskCommentsAndStrings(source);
  final lines = source.split('\n');
  final usages = <_LocalTimeUsage>[];
  for (final construct in _LocalTimeConstruct.values) {
    for (final match in RegExp(construct.pattern).allMatches(code)) {
      if (!_obtainsLocalTime(construct, code, match)) continue;
      final before = code.substring(0, match.start);
      final line = '\n'.allMatches(before).length + 1;
      usages.add(
        _LocalTimeUsage(
          path: path,
          line: line,
          column: match.start - before.lastIndexOf('\n'),
          construct: construct,
          sourceLine: lines[line - 1],
        ),
      );
    }
  }
  return usages..sort(
    (first, second) => switch (first.line.compareTo(second.line)) {
      0 => first.column.compareTo(second.column),
      final byLine => byLine,
    },
  );
}

/// Создаёт ли совпадение [match] дату в местном времени: часть совпадений
/// [_LocalTimeConstruct] безопасна в зависимости от аргументов.
bool _obtainsLocalTime(
  _LocalTimeConstruct construct,
  String code,
  RegExpMatch match,
) {
  switch (construct) {
    case _LocalTimeConstruct.constructor:
      // У безымянного конструктора нет именованных параметров и есть
      // обязательный год: без аргументов или с именованными полями это
      // объектный шаблон, который только читает дату.
      final arguments = _topLevelArguments(code, match.end);
      return arguments.isNotEmpty && !arguments.any(_namedArgument.hasMatch);
    case _LocalTimeConstruct.fromMillisecondsSinceEpoch ||
        _LocalTimeConstruct.fromMicrosecondsSinceEpoch:
      // Без скобок это ссылка на конструктор, который по умолчанию создаёт
      // местное время.
      return !match[0]!.endsWith('(') ||
          !_topLevelArguments(code, match.end).any(_utcFlag.hasMatch);
    case _LocalTimeConstruct.constructorTearOff ||
        _LocalTimeConstruct.now ||
        _LocalTimeConstruct.toLocal ||
        _LocalTimeConstruct.parse ||
        _LocalTimeConstruct.tryParse:
      return true;
  }
}

/// Именованный аргумент или поле объектного шаблона: `name: …` или `:name`.
final _namedArgument = RegExp(r'^\s*(?:[A-Za-z_$][\w$]*\s*)?:');
final _utcFlag = RegExp(r'^\s*isUtc\s*:\s*true\s*$');

/// Аргументы верхнего уровня скобок, которые открываются перед [start] в коде
/// без комментариев и строк.
List<String> _topLevelArguments(String code, int start) {
  final arguments = <String>[];
  var depth = 0;
  var argumentStart = start;
  for (var position = start; position < code.length; position++) {
    switch (code[position]) {
      case '(' || '[' || '{':
        depth++;
      case ')' when depth == 0:
        final last = code.substring(argumentStart, position);
        if (last.trim().isNotEmpty) arguments.add(last);
        return arguments;
      case ')' || ']' || '}':
        depth--;
      case ',' when depth == 0:
        arguments.add(code.substring(argumentStart, position));
        argumentStart = position + 1;
    }
  }
  return arguments;
}

/// Исходник [source] той же длины, в котором комментарии и содержимое
/// строковых литералов заменены пробелами. Код интерполяций `${...}` и
/// переводы строк сохранены, поэтому позиции и строки совпадают с исходником.
String _maskCommentsAndStrings(String source) =>
    (_DartCodeMask(source)..maskCode(untilInterpolationEnd: false)).code;

/// Разбор исходника Dart, достаточный, чтобы отличить код от комментариев и
/// содержимого строковых литералов.
final class _DartCodeMask {
  _DartCodeMask(this._source) : _units = List.of(_source.codeUnits);

  final String _source;
  final List<int> _units;
  var _position = 0;

  String get code => String.fromCharCodes(_units);

  /// Проходит код до конца исходника либо, если [untilInterpolationEnd], до
  /// `}`, закрывающей интерполяцию; позиция остаётся на этой `}`.
  void maskCode({required bool untilInterpolationEnd}) {
    var braceDepth = 0;
    while (_position < _source.length) {
      if (_source.startsWith('//', _position)) {
        _maskLineComment();
      } else if (_source.startsWith('/*', _position)) {
        _maskBlockComment();
      } else if (_stringStart() case (:final raw, :final quote)?) {
        _maskString(raw: raw, quote: quote);
      } else {
        switch (_source[_position]) {
          case '{':
            braceDepth++;
          case '}' when untilInterpolationEnd && braceDepth == 0:
            return;
          case '}':
            braceDepth--;
        }
        _position++;
      }
    }
  }

  /// Строковый литерал, который начинается в текущей позиции: признак сырой
  /// строки `r` и открывающие кавычки.
  ({bool raw, String quote})? _stringStart() {
    final raw =
        _source.startsWith('r', _position) &&
        (_position == 0 || !_identifierPart.hasMatch(_source[_position - 1]));
    final quoteStart = raw ? _position + 1 : _position;
    for (final quote in const ["'''", '"""', "'", '"']) {
      if (_source.startsWith(quote, quoteStart)) {
        return (raw: raw, quote: quote);
      }
    }
    return null;
  }

  void _maskString({required bool raw, required String quote}) {
    _mask((raw ? 1 : 0) + quote.length);
    while (_position < _source.length) {
      if (_source.startsWith(quote, _position)) {
        _mask(quote.length);
        return;
      }
      if (quote.length == 1 && _source[_position] == '\n') return;
      if (!raw && _source.startsWith(r'\', _position)) {
        _mask(2);
      } else if (!raw && _source.startsWith(r'${', _position)) {
        _mask(2);
        maskCode(untilInterpolationEnd: true);
        _mask(1);
      } else {
        _mask(1);
      }
    }
  }

  void _maskLineComment() {
    final end = _source.indexOf('\n', _position);
    _mask((end == -1 ? _source.length : end) - _position);
  }

  /// Блочные комментарии Dart могут быть вложенными.
  void _maskBlockComment() {
    var depth = 0;
    while (_position < _source.length) {
      if (_source.startsWith('/*', _position)) {
        depth++;
        _mask(2);
      } else if (_source.startsWith('*/', _position)) {
        depth--;
        _mask(2);
        if (depth == 0) return;
      } else {
        _mask(1);
      }
    }
  }

  /// Заменяет пробелами [length] символов с текущей позиции, сохраняя
  /// переводы строк.
  void _mask(int length) {
    final end = math.min(_position + length, _source.length);
    for (; _position < end; _position++) {
      if (_units[_position] != _newline) _units[_position] = _space;
    }
  }
}

final _identifierPart = RegExp(r'[\w$]');
final _newline = '\n'.codeUnitAt(0);
final _space = ' '.codeUnitAt(0);
