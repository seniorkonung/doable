import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import '../intention/domain/intention.dart';
import '../intention/domain/intention_id.dart';
import '../tag/domain/tag_position.dart';
import 'graph_format_codec.dart';
import 'graph_format_records.dart';

/// Файл формата — gzip поверх JSON Lines в UTF-8: строка заголовка, затем
/// секции тегов, намерений, надгробий удалённых намерений, назначений тегов,
/// долговременных связей, надгробий удалённых связей, действий с путями и
/// дневных выборов по строке на запись. Так устроены файл экспорта и снимок.
abstract final class GraphFormatFile {
  /// Сжатые байты файла с заголовком [header] и записями [records].
  ///
  /// Записи кодируются по мере прослушивания результата. Они должны идти по
  /// секциям в количествах заголовка, места тегов — не повторяться, намерения
  /// — строго по [compareIntentionsInFormatOrder], а путь действия и пара
  /// надгробия связи — ссылаться на намерения и надгробия намерений
  /// предшествующих строк, иначе поток завершается [StateError]: такой файл
  /// чтение не примет. Запись длиннее предела завершает поток отказом
  /// [GraphRecordTooLong].
  static Stream<List<int>> write(
    GraphFormatHeader header,
    Stream<GraphEntityRecord> records,
  ) => gzip.encoder.bind(_writeLines(header, records));

  /// Открывает файл из сжатых байтов [file] и читает его заголовок.
  ///
  /// Чужой, повреждённый или обрезанный файл даёт [GraphFormatCorruption]
  /// здесь или в [GraphFormatFileReading.records], файл более новой версии —
  /// [GraphFormatVersionTooNew]. Повреждение — в том числе повторённое место
  /// тега, намерения не строго по [compareIntentionsInFormatOrder]: в таком
  /// порядке их перечисляет база, поэтому прочитанные записи канонические, и
  /// путь действия или пара надгробия связи со ссылкой на намерение, которого
  /// нет в предшествующих строках.
  /// Ошибки самого [file] передаются как есть.
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
        'Запись не совпадает с секциями заголовка, порядком намерений или '
        'ссылками на предшествующие записи.',
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

/// Сверяет записи с секциями, размеры которых задают количества заголовка,
/// с единственностью мест тегов, с каноническим порядком намерений и со
/// ссылками путей действий и надгробий связей на предшествующие намерения.
final class _Sections {
  _Sections(GraphRecordCounts counts)
    : _remaining = [
        for (final section in _Section.values) section.countIn(counts),
      ];

  /// Сколько записей осталось в каждой секции, по номеру секции.
  final List<int> _remaining;
  var _current = 0;
  final _tagPositions = <TagPosition>{};
  Intention? _lastIntention;

  /// Намерения и надгробия намерений предшествующих строк: на них могут
  /// ссылаться путь действия и пара надгробия связи.
  final _knownIntentions = _KnownIntentions();

  bool get isComplete => _remaining.every((count) => count == 0);

  /// Учитывает [record], если запись следующая по порядку секций, место тега
  /// не встречалось раньше, намерение идёт строго после предыдущего по
  /// [compareIntentionsInFormatOrder], а путь действия и пара надгробия связи
  /// ссылаются только на уже встреченные намерения и надгробия намерений.
  bool accept(GraphEntityRecord record) {
    while (_current < _remaining.length && _remaining[_current] == 0) {
      _current++;
    }
    if (_current == _remaining.length ||
        _Section.of(record).index != _current) {
      return false;
    }
    if (record case TagRecord(:final tag)
        when !_tagPositions.add(tag.position)) {
      return false;
    }
    if (record case IntentionRecord(:final intention)) {
      if (_lastIntention case final last?
          when compareIntentionsInFormatOrder(last, intention) >= 0) {
        return false;
      }
      _lastIntention = intention;
      _knownIntentions.add(intention.id);
    }
    switch (record) {
      case DeletedIntentionRecord(:final id):
        _knownIntentions.add(id);
      case DeletedRelationPairRecord(
        :final sourceIntentionId,
        :final relatedIntentionId,
      ):
        if (!_knownIntentions.contains(sourceIntentionId) ||
            !_knownIntentions.contains(relatedIntentionId)) {
          return false;
        }
      case ActionRecord(:final path):
        if (!path.intentions.every(_knownIntentions.contains)) return false;
      default:
    }
    _remaining[_current]--;
    return true;
  }
}

/// Множество идентификаторов намерений по 16 байт на идентификатор: память
/// чтения и записи файла растёт с графом не больше, чем на сами
/// идентификаторы. Секции намерений и их надгробий предшествуют ссылкам на
/// них, поэтому все добавления идут до первой проверки. Она собирает порции
/// в один массив, освобождая каждую после копирования, и сортирует его на
/// месте для двоичного поиска.
final class _KnownIntentions {
  /// Идентификаторов в порции: память растёт порциями, а не удвоением.
  static const _chunkIds = 4096;

  /// Старшие и младшие 64 бита идентификаторов поочерёдно.
  List<Int64List?>? _chunks = [];
  var _length = 0;
  Int64List? _sorted;

  void add(IntentionId id) {
    final chunks = _chunks;
    if (chunks == null) {
      throw StateError('Намерение добавлено после проверки ссылок.');
    }
    final offset = _length % _chunkIds;
    if (offset == 0) chunks.add(Int64List(2 * _chunkIds));
    final (high, low) = _bits(id);
    chunks.last!
      ..[2 * offset] = high
      ..[2 * offset + 1] = low;
    _length++;
  }

  bool contains(IntentionId id) {
    final sorted = _sorted ??= _collect();
    final (high, low) = _bits(id);
    var start = 0, end = _length;
    while (start < end) {
      final middle = (start + end) >> 1;
      final order = _compare(sorted, middle, high, low);
      if (order == 0) return true;
      if (order < 0) {
        start = middle + 1;
      } else {
        end = middle;
      }
    }
    return false;
  }

  Int64List _collect() {
    final chunks = _chunks!;
    _chunks = null;
    final values = Int64List(2 * _length);
    for (var chunk = 0; chunk < chunks.length; chunk++) {
      final start = chunk * 2 * _chunkIds;
      values.setRange(
        start,
        math.min(start + 2 * _chunkIds, values.length),
        chunks[chunk]!,
      );
      chunks[chunk] = null;
    }
    // Пирамидальная сортировка не требует памяти сверх массива.
    for (var root = _length ~/ 2 - 1; root >= 0; root--) {
      _siftDown(values, root, _length);
    }
    for (var end = _length - 1; end > 0; end--) {
      _swap(values, 0, end);
      _siftDown(values, 0, end);
    }
    return values;
  }

  static void _siftDown(Int64List values, int root, int end) {
    while (true) {
      var largest = root;
      for (var child = 2 * root + 1; child <= 2 * root + 2; child++) {
        if (child < end &&
            _compare(
                  values,
                  largest,
                  values[2 * child],
                  values[2 * child + 1],
                ) <
                0) {
          largest = child;
        }
      }
      if (largest == root) return;
      _swap(values, root, largest);
      root = largest;
    }
  }

  static void _swap(Int64List values, int a, int b) {
    final high = values[2 * a], low = values[2 * a + 1];
    values
      ..[2 * a] = values[2 * b]
      ..[2 * a + 1] = values[2 * b + 1]
      ..[2 * b] = high
      ..[2 * b + 1] = low;
  }

  /// Порядок идентификатора с номером [index] относительно ([high], [low]).
  static int _compare(Int64List values, int index, int high, int low) {
    final byHigh = values[2 * index].compareTo(high);
    return byHigh != 0 ? byHigh : values[2 * index + 1].compareTo(low);
  }

  /// Биты канонической записи `xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx`;
  /// сдвиг в знаковый разряд сохраняет различие значений.
  static (int, int) _bits(IntentionId id) {
    final text = id.toCanonicalString();
    int hex(int start, int end) =>
        int.parse(text.substring(start, end), radix: 16);
    return (
      hex(0, 8) << 32 | hex(9, 13) << 16 | hex(14, 18),
      hex(19, 23) << 48 | hex(24, 36),
    );
  }
}

/// Секции в порядке файла: запись ссылается только на сущности
/// предшествующих строк.
enum _Section {
  tags,
  intentions,
  deletedIntentions,
  tagAssignments,
  longTermRelations,
  deletedRelationPairs,
  actions,
  dailyChoices;

  static _Section of(GraphEntityRecord record) => switch (record) {
    TagRecord() => tags,
    IntentionRecord() => intentions,
    DeletedIntentionRecord() => deletedIntentions,
    TagAssignmentRecord() => tagAssignments,
    LongTermRelationRecord() => longTermRelations,
    DeletedRelationPairRecord() => deletedRelationPairs,
    ActionRecord() => actions,
    DailyChoiceRecord() => dailyChoices,
  };

  int countIn(GraphRecordCounts counts) => switch (this) {
    tags => counts.tags,
    intentions => counts.intentions,
    deletedIntentions => counts.deletedIntentions,
    tagAssignments => counts.tagAssignments,
    longTermRelations => counts.longTermRelations,
    deletedRelationPairs => counts.deletedRelationPairs,
    actions => counts.actions,
    dailyChoices => counts.dailyChoices,
  };
}
