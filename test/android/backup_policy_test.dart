import 'dart:io';

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

      expect(_excludesAppFlutter(cloudBackup), isTrue);
      expect(_excludesAppFlutter(deviceTransfer), isTrue);
      expect(_excludesLegacyDatabaseDomain(cloudBackup), isFalse);
      expect(_excludesLegacyDatabaseDomain(deviceTransfer), isFalse);
    },
  );

  test('Android 11 и ниже исключает app_flutter из full backup', () {
    final rules = File(
      androidMain.resolve('res/xml/backup_rules.xml').toFilePath(),
    ).readAsStringSync();

    final fullBackup = _elementBody(rules, 'full-backup-content');

    expect(_excludesAppFlutter(fullBackup), isTrue);
    expect(_excludesLegacyDatabaseDomain(fullBackup), isFalse);
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

bool _excludesAppFlutter(String elementBody) =>
    _hasExclusion(elementBody, domain: 'root', path: 'app_flutter/');

bool _excludesLegacyDatabaseDomain(String elementBody) =>
    _hasExclusion(elementBody, domain: 'database', path: '.');

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
