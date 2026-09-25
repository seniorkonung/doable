import 'dart:typed_data';

import 'package:doable/src/data/local/sqlite_connection_setup.dart';
import 'package:doable/src/data/local/sqlite_tag_functions.dart';
import 'package:doable/src/tag/domain/tag_name.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

void main() {
  late sqlite.Database database;

  setUp(() {
    database = sqlite.sqlite3.openInMemory();
    configureDoableSqliteConnection(database);
  });
  tearDown(() => database.close());

  test('функции принимают канонический декодированный TEXT', () {
    for (final name in ['Дом', 'Для  дома', 'Straße', 'e\u0301']) {
      final row = database.select(
        'SELECT $tagNameValidFunctionName(?) AS valid, '
        '$tagNameKeyFunctionName(?) AS name_key',
        [name, name],
      ).single;
      expect(row['valid'], 1);
      expect(row['name_key'], TagName.fromStored(name).matchingKey);
    }
  });

  test(
    'для других типов и недопустимого декодированного TEXT результат безопасен',
    () {
      for (final value in <Object?>[
        null,
        1,
        1.5,
        Uint8List.fromList([0x41]),
        '',
        ' \n\t ',
        ' Дом',
        'Дом ',
        'До\u0000м',
        List.filled(256, '👩🏽‍💻').join(),
      ]) {
        final row = database.select(
          'SELECT $tagNameValidFunctionName(?) AS valid, '
          '$tagNameKeyFunctionName(?) AS name_key',
          [value, value],
        ).single;
        expect(row['valid'], 0, reason: '$value');
        expect(row['name_key'], isNull, reason: '$value');
      }
    },
  );

  test('ключ закрепляет Unicode folding без нормализации', () {
    String key(String name) =>
        database.select('SELECT $tagNameKeyFunctionName(?) AS value', [
              name,
            ]).single['value']
            as String;

    expect(key('Straße'), 'strasse');
    expect(key('STRASSE'), 'strasse');
    expect(key('Все'), 'все');
    expect(key('Всё'), 'всё');
    expect(key('é'), 'é');
    expect(key('e\u0301'), 'e\u0301');
    expect(key('İ'), 'i\u0307');
  });

  test('ошибка декодирования TEXT прерывает SQL без сохранения строки', () {
    database.execute('''
      CREATE TABLE tag_names (
        name TEXT NOT NULL CHECK ($tagNameValidFunctionName(name) = 1),
        name_key TEXT GENERATED ALWAYS AS ($tagNameKeyFunctionName(name)) STORED NOT NULL
      )
    ''');

    expect(
      () => database.execute(
        "INSERT INTO tag_names(name) VALUES (CAST(x'80' AS TEXT))",
      ),
      throwsA(isA<sqlite.SqliteException>()),
    );
    expect(database.select('SELECT * FROM tag_names'), isEmpty);
  });

  test('схема отдельно отвергает исходный TEXT с начальным U+FEFF', () {
    database.execute('''
      CREATE TABLE tag_names (
        name TEXT NOT NULL CHECK (
          typeof(name) = 'text'
          AND substr(name, 1, 1) <> char(65279)
          AND $tagNameValidFunctionName(name) = 1
        ),
        name_key TEXT GENERATED ALWAYS AS ($tagNameKeyFunctionName(name)) STORED NOT NULL
      )
    ''');
    database.execute("INSERT INTO tag_names(name) VALUES ('Дом')");

    expect(
      () => database.execute(
        "INSERT INTO tag_names(name) VALUES (char(65279) || 'Быт')",
      ),
      throwsA(isA<sqlite.SqliteException>()),
    );
    expect(database.select('SELECT name, name_key FROM tag_names').single, {
      'name': 'Дом',
      'name_key': 'дом',
    });
  });

  test('v1 закрепляет набор символов, удаляемых Dart trim', () {
    const expectedTrimmed = [
      0x0009,
      0x000a,
      0x000b,
      0x000c,
      0x000d,
      0x0020,
      0x0085,
      0x00a0,
      0x1680,
      0x2000,
      0x2001,
      0x2002,
      0x2003,
      0x2004,
      0x2005,
      0x2006,
      0x2007,
      0x2008,
      0x2009,
      0x200a,
      0x2028,
      0x2029,
      0x202f,
      0x205f,
      0x3000,
      0xfeff,
    ];
    final actualTrimmed = <int>[];
    for (var point = 1; point <= 0x10ffff; point++) {
      if (point >= 0xd800 && point <= 0xdfff) continue;
      final character = String.fromCharCode(point);
      if ('${character}X$character'.trim() == 'X') {
        actualTrimmed.add(point);
      }
    }
    expect(actualTrimmed, expectedTrimmed);

    for (final point in expectedTrimmed) {
      final character = String.fromCharCode(point);
      expect(TagName.fromInput('${character}Дом$character').value, 'Дом');
      if (point == 0xfeff) continue;
      final row = database.select(
        'SELECT $tagNameValidFunctionName(?) AS valid, '
        '$tagNameKeyFunctionName(?) AS name_key',
        ['${character}Дом', '${character}Дом'],
      ).single;
      expect(row['valid'], 0, reason: 'U+${point.toRadixString(16)}');
      expect(row['name_key'], isNull);
    }
  });

  test('v1 закрепляет сегментацию составных графем на границе длины', () {
    for (final cluster in [
      'e\u0301',
      '👩🏽‍💻',
      '🏳️‍🌈',
      '🇷🇺',
      '👨‍👩‍👧‍👦',
      '1️⃣',
      '\u1100\u1161\u11a8',
      'कि',
    ]) {
      final allowed = List.filled(255, cluster).join();
      final rejected = List.filled(256, cluster).join();
      final row = database.select(
        'SELECT $tagNameValidFunctionName(?) AS allowed, '
        '$tagNameValidFunctionName(?) AS rejected',
        [allowed, rejected],
      ).single;
      expect(row['allowed'], 1, reason: cluster);
      expect(row['rejected'], 0, reason: cluster);
    }
  });
}
