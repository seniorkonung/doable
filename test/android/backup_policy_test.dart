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
    'Android 12 и новее исключает database domain из cloud backup и transfer',
    () {
      final rules = File(
        androidMain.resolve('res/xml/data_extraction_rules.xml').toFilePath(),
      ).readAsStringSync();

      expect(
        rules,
        contains('''<cloud-backup>
        <exclude domain="database" path="." />
    </cloud-backup>'''),
      );
      expect(
        rules,
        contains('''<device-transfer>
        <exclude domain="database" path="." />
    </device-transfer>'''),
      );
    },
  );

  test('Android 11 и ниже исключает database domain из full backup', () {
    final rules = File(
      androidMain.resolve('res/xml/backup_rules.xml').toFilePath(),
    ).readAsStringSync();

    expect(rules, contains('<full-backup-content>'));
    expect(rules, contains('<exclude domain="database" path="." />'));
  });
}
