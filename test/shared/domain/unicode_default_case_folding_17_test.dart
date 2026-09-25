import 'dart:convert';
import 'dart:io';

import 'package:doable/src/shared/domain/unicode_default_case_folding_17.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('закреплённый Unicode Default Case Folding 17.0.0', () {
    test('повторяет все отображения C и F из закреплённой фикстуры', () async {
      final bytes = await File('test/fixtures/unicode/CaseFolding-17.0.0.txt')
          .readAsBytes();
      expect(
        sha256.convert(bytes).toString(),
        'ff8d8fefbf123574205085d6714c36149eb946d717a0c585c27f0f4ef58c4183',
      );
      final lines = const LineSplitter().convert(utf8.decode(bytes));
      var mappingCount = 0;

      for (final line in lines) {
        if (line.isEmpty || line.startsWith('#')) continue;

        final fields = line.split(';');
        final status = fields[1].trim();
        if (status != 'C' && status != 'F') continue;

        final codePoint = int.parse(fields[0].trim(), radix: 16);
        final expected = String.fromCharCodes(
          fields[2]
              .trim()
              .split(RegExp(r'\s+'))
              .map((value) => int.parse(value, radix: 16)),
        );

        expect(
          UnicodeDefaultCaseFolding17.fold(String.fromCharCode(codePoint)),
          expected,
          reason: 'U+${codePoint.toRadixString(16).toUpperCase()}',
        );
        mappingCount++;
      }

      expect(mappingCount, 1585);
    });

    test('раскрывает многосимвольные соответствия без Turkic tailoring', () {
      expect(UnicodeDefaultCaseFolding17.version, '17.0.0');
      expect(UnicodeDefaultCaseFolding17.fold('Straße'), 'strasse');
      expect(UnicodeDefaultCaseFolding17.fold('ẞ'), 'ss');
      expect(UnicodeDefaultCaseFolding17.fold('Iİı'), 'ii\u0307ı');
    });

    test('оставляет неизменяемые символы и не нормализует Unicode', () {
      expect(
        UnicodeDefaultCaseFolding17.fold('😀 123 \u0301'),
        '😀 123 \u0301',
      );
      expect(UnicodeDefaultCaseFolding17.fold('é'), 'é');
      expect(UnicodeDefaultCaseFolding17.fold('e\u0301'), 'e\u0301');
    });
  });
}
