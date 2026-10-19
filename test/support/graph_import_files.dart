import 'dart:convert';
import 'dart:io';

/// Строки эталонного файла формата версии 1 без сжатия: заголовок, затем
/// записи двух тегов, четырёх намерений, трёх назначений тегов, трёх
/// долговременных связей и двух дневных выборов. Записи — канонические
/// строки формата в порядке файла.
List<String> referenceGraphFileLines() =>
    File('test/graph_format/golden/graph_format_v1.jsonl').readAsLinesSync();

/// Байты файла экспорта со строками [lines]: gzip поверх JSON Lines.
List<int> graphExportFileOf(List<String> lines) =>
    gzip.encode(utf8.encode([for (final line in lines) '$line\n'].join()));

/// Строки [lines], в которых объект JSON строки [index] изменён [edit].
List<String> withEditedLine(
  List<String> lines,
  int index,
  void Function(Map<String, Object?> json) edit,
) {
  final json = jsonDecode(lines[index]) as Map<String, Object?>;
  edit(json);
  return [...lines.take(index), jsonEncode(json), ...lines.skip(index + 1)];
}

/// Начало фотографии JPEG: файл не сжат gzip.
List<int> photoFile() => [
  0xff, 0xd8, 0xff, 0xe0, 0x00, 0x10, 0x4a, 0x46, 0x49, 0x46, 0x00, 0x01, //
  for (var index = 0; index < 512; index++) index % 251,
];

/// Файл экспорта более новой версии формата, чем поддерживает приложение.
List<int> newerFormatVersionFile() => graphExportFileOf([
  '{"format":"doable-graph","version":2,'
      '"writtenAt":"2030-01-01T00:00:00.000000Z"}',
]);

/// Эталонный файл экспорта, сжатые байты которого обрезаны посередине, как
/// у файла, запись которого прервалась. Заголовок файла исправен.
List<int> truncatedGraphExportFile() {
  final bytes = graphExportFileOf(referenceGraphFileLines());
  return bytes.sublist(0, bytes.length ~/ 2);
}
