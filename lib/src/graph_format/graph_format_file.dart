import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import '../intention/domain/intention.dart';
import 'graph_format_codec.dart';
import 'graph_format_records.dart';

/// Файл формата — gzip поверх JSON Lines в UTF-8: строка заголовка, затем
/// секции тегов, намерений, назначений тегов, долговременных связей и
/// дневных выборов по строке на запись. Так устроены файл экспорта и снимок.
abstract final class GraphFormatFile {
  /// Сжатые байты файла с заголовком [header] и записями [records].
  ///
  /// Записи кодируются по мере прослушивания результата. Они должны идти по
  /// секциям в количествах заголовка, а намерения — строго по
  /// [compareIntentionsInFormatOrder], иначе поток завершается [StateError]:
  /// такой файл чтение не примет. Запись длиннее предела завершает поток
  /// отказом [GraphRecordTooLong].
  static Stream<List<int>> write(
    GraphFormatHeader header,
    Stream<GraphEntityRecord> records,
  ) => gzip.encoder.bind(_writeLines(header, records));

  /// Открывает файл из сжатых байтов [file] и читает его заголовок.
  ///
  /// Чужой, повреждённый или обрезанный файл даёт [GraphFormatCorruption]
  /// здесь или в [GraphFormatFileReading.records], файл более новой версии —
  /// [GraphFormatVersionTooNew]. Повреждение — в том числе намерения не
  /// строго по [compareIntentionsInFormatOrder]: в таком порядке их
  /// перечисляет база, поэтому прочитанные записи канонические. Ошибки самого
  /// [file] передаются как есть.
  static Future<GraphFormatFileReading> read(Stream<List<int>> file) async {
    final lines = StreamIterator(
      _readLines(_decompress(file), firstLineLimit: _headerByteLimit),
    );
    try {
      if (!await lines.moveNext()) throw const GraphFormatCorruption();
      final (:version, :header) = GraphFormatCodec.decodeHeader(lines.current);
      return GraphFormatFileReading._(
        header,
        _readRecords(lines, version, header.counts),
        lines.cancel,
      );
    } catch (_) {
      await lines.cancel();
      rethrow;
    }
  }

  /// Сжатые байты записей [records] без заголовка и секций — промежуточного
  /// файла, количества записей которого неизвестны до конца записи.
  ///
  /// Записи кодируются по мере прослушивания результата; запись длиннее
  /// предела завершает поток отказом [GraphRecordTooLong].
  static Stream<List<int>> writeRecords(Stream<GraphEntityRecord> records) =>
      gzip.encoder.bind(
        records.map((record) => _terminated(GraphFormatCodec.encode(record))),
      );

  /// Записи текущей версии из сжатых байтов [file], записанных
  /// [writeRecords], по мере прослушивания.
  ///
  /// Повреждённый или обрезанный файл даёт [GraphFormatCorruption]. Ошибки
  /// самого [file] передаются как есть.
  static Stream<GraphEntityRecord> readRecords(Stream<List<int>> file) async* {
    await for (final line in _readLines(
      _decompress(file),
      firstLineLimit: graphFormatRecordByteLimit,
    )) {
      for (final record in GraphFormatCodec.decodeEntityRecord(
        line,
        GraphFormatVersion.current,
      )) {
        yield record;
      }
    }
  }
}

/// Файл формата с прочитанным заголовком.
final class GraphFormatFileReading {
  const GraphFormatFileReading._(this.header, this.records, this._close);

  final GraphFormatHeader header;

  /// Записи текущей версии в порядке файла, прочитанные по мере
  /// прослушивания.
  ///
  /// Поток однократный и завершается без ошибки, только если записи совпали
  /// с секциями заголовка. Пока его не дослушали или не отменили подписку,
  /// файл остаётся открытым.
  final Stream<GraphEntityRecord> records;

  final Future<void> Function() _close;

  /// Закрывает источник после проверки одного заголовка, не начиная чтение
  /// записей и не дожидаясь остатка документа.
  Future<void> close() => _close();
}

const _lineFeed = 0x0a;

const _gzipMagic = [0x1f, 0x8b];

/// Наибольшая длина строки заголовка в байтах UTF-8 без перевода строки.
const _headerByteLimit = 4 * 1024;

/// Наибольшая порция сжатых байтов на шаг распаковки. Deflate увеличивает
/// данные не больше чем примерно в 1032 раза, поэтому шаг выдаёт около
/// мегабайта и на файле, подобранном для разрастания при распаковке.
const _compressedStepByteLimit = 1024;

Stream<List<int>> _writeLines(
  GraphFormatHeader header,
  Stream<GraphEntityRecord> records,
) async* {
  yield _terminated(GraphFormatCodec.encodeHeader(header));
  final sections = _Sections(header.counts);
  await for (final record in records) {
    if (!sections.accept(record)) {
      throw StateError(
        'Запись не совпадает с секциями заголовка или порядком намерений.',
      );
    }
    yield _terminated(GraphFormatCodec.encode(record));
  }
  if (!sections.isComplete) {
    throw StateError('Записей меньше, чем в заголовке.');
  }
}

Uint8List _terminated(Uint8List line) => Uint8List(line.length + 1)
  ..setAll(0, line)
  ..[line.length] = _lineFeed;

Stream<GraphEntityRecord> _readRecords(
  StreamIterator<List<int>> lines,
  GraphFormatVersion version,
  GraphRecordCounts counts,
) async* {
  try {
    final sections = _Sections(counts);
    while (await lines.moveNext()) {
      for (final record in GraphFormatCodec.decodeEntityRecord(
        lines.current,
        version,
      )) {
        if (!sections.accept(record)) throw const GraphFormatCorruption();
        yield record;
      }
    }
    if (!sections.isComplete) throw const GraphFormatCorruption();
  } finally {
    await lines.cancel();
  }
}

/// Распаковывает gzip, начиная с проверки его заголовка, поэтому чужой файл
/// отклоняется сразу. Отказ распаковки — повреждение.
///
/// Обрезанный поток распаковка не отличает от полного: его выдают
/// незавершённая строка и расхождение с количествами заголовка.
Stream<List<int>> _decompress(Stream<List<int>> file) async* {
  final decompressed = _Chunks();
  final decoder = gzip.decoder.startChunkedConversion(decompressed);
  var checkedMagicBytes = 0;
  await for (final chunk in file) {
    for (
      var index = 0;
      checkedMagicBytes < _gzipMagic.length && index < chunk.length;
      index++, checkedMagicBytes++
    ) {
      if (chunk[index] != _gzipMagic[checkedMagicBytes]) {
        throw const GraphFormatCorruption();
      }
    }
    for (
      var start = 0;
      start < chunk.length;
      start += _compressedStepByteLimit
    ) {
      final end = math.min(start + _compressedStepByteLimit, chunk.length);
      try {
        decoder.addSlice(chunk, start, end, false);
      } on FormatException {
        throw const GraphFormatCorruption();
      }
      for (final piece in decompressed.take()) {
        yield piece;
      }
    }
  }
  if (checkedMagicBytes < _gzipMagic.length) {
    throw const GraphFormatCorruption();
  }
  try {
    decoder.close();
  } on FormatException {
    throw const GraphFormatCorruption();
  }
  for (final piece in decompressed.take()) {
    yield piece;
  }
}

/// Делит распакованный текст на строки, каждая из которых завершена
/// переводом строки. Первая строка не длиннее [firstLineLimit], остальные —
/// предела записи.
///
/// Чтение строки длиннее предела прекращается, как только она его превысила,
/// поэтому память чтения ограничена и на чужом файле без переводов строк.
Stream<List<int>> _readLines(
  Stream<List<int>> content, {
  required int firstLineLimit,
}) async* {
  final pending = BytesBuilder(copy: false);
  var limit = firstLineLimit;
  await for (final chunk in content) {
    var start = 0;
    while (start < chunk.length) {
      final lineFeed = chunk.indexOf(_lineFeed, start);
      final end = lineFeed < 0 ? chunk.length : lineFeed;
      if (pending.length + end - start > limit) {
        throw const GraphFormatCorruption();
      }
      pending.add(chunk.sublist(start, end));
      if (lineFeed < 0) break;
      yield pending.takeBytes();
      limit = graphFormatRecordByteLimit;
      start = lineFeed + 1;
    }
  }
  if (pending.isNotEmpty) throw const GraphFormatCorruption();
}

final class _Chunks implements Sink<List<int>> {
  var _chunks = <List<int>>[];

  List<List<int>> take() {
    final chunks = _chunks;
    _chunks = [];
    return chunks;
  }

  @override
  void add(List<int> chunk) => _chunks.add(chunk);

  @override
  void close() {}
}

/// Сверяет записи с секциями, размеры которых задают количества заголовка, и
/// с каноническим порядком намерений.
final class _Sections {
  _Sections(GraphRecordCounts counts)
    : _remaining = [
        for (final section in _Section.values) section.countIn(counts),
      ];

  /// Сколько записей осталось в каждой секции, по номеру секции.
  final List<int> _remaining;
  var _current = 0;
  Intention? _lastIntention;

  bool get isComplete => _remaining.every((count) => count == 0);

  /// Учитывает [record], если запись следующая по порядку секций, а
  /// намерение идёт строго после предыдущего по
  /// [compareIntentionsInFormatOrder].
  bool accept(GraphEntityRecord record) {
    while (_current < _remaining.length && _remaining[_current] == 0) {
      _current++;
    }
    if (_current == _remaining.length ||
        _Section.of(record).index != _current) {
      return false;
    }
    if (record case IntentionRecord(:final intention)) {
      if (_lastIntention case final last?
          when compareIntentionsInFormatOrder(last, intention) >= 0) {
        return false;
      }
      _lastIntention = intention;
    }
    _remaining[_current]--;
    return true;
  }
}

/// Секции в порядке файла: запись ссылается только на сущности
/// предшествующих строк.
enum _Section {
  tags,
  intentions,
  tagAssignments,
  longTermRelations,
  dailyChoices;

  static _Section of(GraphEntityRecord record) => switch (record) {
    TagRecord() => tags,
    IntentionRecord() => intentions,
    TagAssignmentRecord() => tagAssignments,
    LongTermRelationRecord() => longTermRelations,
    DailyChoiceRecord() => dailyChoices,
  };

  int countIn(GraphRecordCounts counts) => switch (this) {
    tags => counts.tags,
    intentions => counts.intentions,
    tagAssignments => counts.tagAssignments,
    longTermRelations => counts.longTermRelations,
    dailyChoices => counts.dailyChoices,
  };
}
