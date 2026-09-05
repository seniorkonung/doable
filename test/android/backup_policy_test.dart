import 'dart:io';

import 'package:doable/src/data/local/app_database.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final androidMain = Directory.current.uri.resolve('android/app/src/main/');

  test(
    'Android manifest подключает оба набора правил без лишних разрешений',
    () {
      final manifest = File(
        androidMain.resolve('AndroidManifest.xml').toFilePath(),
      ).readAsStringSync();

      expect(
        manifest,
        contains('android:dataExtractionRules="@xml/data_extraction_rules"'),
      );
      expect(
        manifest,
        contains('android:fullBackupContent="@xml/backup_rules"'),
      );
      expect(manifest, contains('android:allowBackup="true"'));
      expect(manifest, isNot(contains('android:backupAgent=')));
      expect(manifest, isNot(contains('android.permission.INTERNET')));
      expect(
        manifest,
        isNot(contains('android.permission.READ_EXTERNAL_STORAGE')),
      );
      expect(
        manifest,
        isNot(contains('android.permission.WRITE_EXTERNAL_STORAGE')),
      );
    },
  );

  test(
    'Android 12 и новее исключает app_flutter из cloud backup и transfer',
    () {
      final rules = File(
        androidMain.resolve('res/xml/data_extraction_rules.xml').toFilePath(),
      ).readAsStringSync();

      final cloudBackup = _elementBody(rules, 'cloud-backup');
      final deviceTransfer = _elementBody(rules, 'device-transfer');

      expect(_satisfiesProductionContract(cloudBackup), isTrue);
      expect(_satisfiesProductionContract(deviceTransfer), isTrue);
    },
  );

  test('Android 11 и ниже исключает app_flutter из full backup', () {
    final rules = File(
      androidMain.resolve('res/xml/backup_rules.xml').toFilePath(),
    ).readAsStringSync();

    final fullBackup = _elementBody(rules, 'full-backup-content');

    expect(_satisfiesProductionContract(fullBackup), isTrue);
  });

  test('устаревший database domain не удовлетворяет production contract', () {
    expect(
      _satisfiesProductionContract('<exclude domain="database" path="." />'),
      isFalse,
    );
  });

  test('неполный путь не удовлетворяет production contract', () {
    expect(
      _satisfiesProductionContract(
        '<exclude domain="root" path="app_flutter" />',
      ),
      isFalse,
    );
  });

  test('другое имя connection не удовлетворяет production contract', () {
    expect(
      _satisfiesProductionContract(
        '<exclude domain="root" path="app_flutter/" />',
        connectionName: 'other',
      ),
      isFalse,
    );
  });
}

String _elementBody(String xml, String elementName) {
  final withoutComments = xml.replaceAll(RegExp(r'<!--[\s\S]*?-->'), '');
  final match = RegExp('<$elementName(?:\\s[^>]*)?>([\\s\\S]*?)</$elementName>')
      .firstMatch(withoutComments);

  if (match == null) {
    throw StateError('Элемент <$elementName> отсутствует');
  }
  return match.group(1)!;
}

bool _satisfiesProductionContract(
  String elementBody, {
  String connectionName = AndroidProductionDatabaseConnection.databaseName,
}) =>
    connectionName == AndroidProductionDatabaseConnection.databaseName &&
    _hasExclusion(elementBody, domain: 'root', path: 'app_flutter/');

bool _hasExclusion(
  String elementBody, {
  required String domain,
  required String path,
}) {
  final excludeElements = RegExp(r'<exclude\b([^>]*)/\s*>')
      .allMatches(elementBody);

  return excludeElements.any((element) {
    final attributes = <String, String>{
      for (final attribute in RegExp(
        r'''([\w:-]+)\s*=\s*(?:"([^"]*)"|'([^']*)')''',
      ).allMatches(element.group(1)!))
        attribute.group(1)!: attribute.group(2) ?? attribute.group(3)!,
    };

    return attributes['domain'] == domain && attributes['path'] == path;
  });
}
