import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final manifest = File('android/app/src/main/AndroidManifest.xml')
      .readAsStringSync()
      .replaceAll(RegExp(r'<!--[\s\S]*?-->'), '');
  final activities = <String, Map<String, String>>{
    for (final activity in RegExp(r'<activity\b([^>]*)>').allMatches(manifest))
      _attributes(activity.group(1)!)['android:name']!: _attributes(
        activity.group(1)!,
      ),
  };

  test('Только телефонная Activity ограничивает ориентацию и размер', () {
    expect(activities['.PhoneActivity'], isNotNull);
    expect(
      activities['.PhoneActivity']!['android:screenOrientation'],
      'portrait',
    );
    expect(
      activities['.PhoneActivity']!['android:resizeableActivity'],
      'false',
    );

    for (final name in ['.MainActivity', '.LargeDisplayActivity']) {
      expect(activities[name], isNotNull);
      expect(activities[name]!['android:screenOrientation'], 'unspecified');
      expect(activities[name]!['android:resizeableActivity'], 'true');
    }
  });

  test('Внешний запуск проходит через нативный выбор дисплея', () {
    expect(activities['.MainActivity']!['android:exported'], 'true');
    expect(
      activities['.MainActivity']!['android:theme'],
      '@android:style/Theme.NoDisplay',
    );
    for (final name in ['.PhoneActivity', '.LargeDisplayActivity']) {
      expect(activities[name]!['android:exported'], 'false');
      expect(
        activities[name]!['android:configChanges']!.split('|'),
        containsAll(['screenSize', 'smallestScreenSize', 'density']),
      );
    }
  });

  test(
    'Приложение сохраняет системную политику больших экранов Android 16',
    () {
      final manifests = Directory('android/app/src')
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('AndroidManifest.xml'));
      for (final file in manifests) {
        expect(
          file.readAsStringSync(),
          isNot(contains('PROPERTY_COMPAT_ALLOW_RESTRICTED_RESIZABILITY')),
        );
      }
    },
  );
}

Map<String, String> _attributes(String element) => {
  for (final attribute in RegExp(
    r'''([\w:-]+)\s*=\s*(?:"([^"]*)"|'([^']*)')''',
  ).allMatches(element))
    attribute.group(1)!: attribute.group(2) ?? attribute.group(3)!,
};
