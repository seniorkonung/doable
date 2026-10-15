import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'MainActivity задаёт портретную ориентацию и запрещает разделение экрана',
    () {
      final manifest = File('android/app/src/main/AndroidManifest.xml')
          .readAsStringSync()
          .replaceAll(RegExp(r'<!--[\s\S]*?-->'), '');

      final mainActivityAttributes = RegExp(r'<activity\b([^>]*)>')
          .allMatches(manifest)
          .map(
            (activity) => <String, String>{
              for (final attribute in RegExp(
                r'''([\w:-]+)\s*=\s*(?:"([^"]*)"|'([^']*)')''',
              ).allMatches(activity.group(1)!))
                attribute.group(1)!: attribute.group(2) ?? attribute.group(3)!,
            },
          )
          .singleWhere(
            (attributes) => attributes['android:name'] == '.MainActivity',
          );

      expect(mainActivityAttributes['android:screenOrientation'], 'portrait');
      expect(mainActivityAttributes['android:resizeableActivity'], 'false');
    },
  );
}
