import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Документ с байтами [bytes] вне каталогов приложения в новом временном
/// каталоге, который удаляется после теста.
File temporaryImportDocument(List<int> bytes) {
  final directory = Directory.systemTemp.createTempSync(
    'doable_import_document_',
  );
  addTearDown(() => directory.deleteSync(recursive: true));
  return File.fromUri(directory.uri.resolve('doable.jsonl.gz'))
    ..writeAsBytesSync(bytes);
}
