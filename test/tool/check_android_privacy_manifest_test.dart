import 'package:flutter_test/flutter_test.dart';

import '../../tool/check_android_privacy_manifest.dart';

void main() {
  group('проверка packaged Android privacy manifest', () {
    test('принимает точный утверждённый набор и backup references', () {
      expect(
        () => verifyPackagedAndroidPrivacyManifest(_approvedEvidence),
        returnsNormally,
      );
    });

    for (final permission in <String>[
      'android.permission.INTERNET',
      'android.permission.READ_EXTERNAL_STORAGE',
      'android.permission.WRITE_EXTERNAL_STORAGE',
      'android.permission.MANAGE_EXTERNAL_STORAGE',
      'android.permission.READ_MEDIA_IMAGES',
      'android.permission.READ_MEDIA_VIDEO',
      'android.permission.READ_MEDIA_AUDIO',
      'android.permission.READ_MEDIA_VISUAL_USER_SELECTED',
      'android.permission.ACCESS_MEDIA_LOCATION',
      'com.example.permission.THIRD_PARTY',
      'android.permission.UNKNOWN_TO_CURRENT_SDK',
    ]) {
      test('отклоняет дополнительное разрешение $permission', () {
        expect(
          () => verifyPackagedAndroidPrivacyManifest(
            _approvedEvidence.copyWith(
              permissions: _permissionDump(
                requestedPermissions: <String>[
                  approvedAndroidPermission,
                  permission,
                ],
              ),
            ),
          ),
          _throwsPrivacyViolation,
        );
      });
    }

    test('отклоняет смешанный dump с uses-permission-sdk-23', () {
      expect(
        () => verifyPackagedAndroidPrivacyManifest(
          _approvedEvidence.copyWith(
            permissions:
                '''
package: software.doable.doable
permission: $approvedAndroidPermission
uses-permission: name='$approvedAndroidPermission'
uses-permission-sdk-23: name='android.permission.ACCESS_MEDIA_LOCATION'
''',
          ),
        ),
        _throwsPrivacyViolation,
      );
    });

    test('отклоняет замену утверждённого разрешения', () {
      expect(
        () => verifyPackagedAndroidPrivacyManifest(
          _approvedEvidence.copyWith(
            permissions: _permissionDump(
              requestedPermissions: const <String>[
                'android.permission.INTERNET',
              ],
            ),
          ),
        ),
        _throwsPrivacyViolation,
      );
    });

    test('отклоняет пустой permission evidence', () {
      expect(
        () => verifyPackagedAndroidPrivacyManifest(
          _approvedEvidence.copyWith(permissions: ''),
        ),
        _throwsPrivacyViolation,
      );
    });

    test('отклоняет permission evidence неожиданного формата', () {
      expect(
        () => verifyPackagedAndroidPrivacyManifest(
          _approvedEvidence.copyWith(
            permissions:
                '''
package: software.doable.doable
permission: $approvedAndroidPermission
uses-permission: name=$approvedAndroidPermission
''',
          ),
        ),
        _throwsPrivacyViolation,
      );
    });

    test('отклоняет отсутствие декларации package permission', () {
      expect(
        () => verifyPackagedAndroidPrivacyManifest(
          _approvedEvidence.copyWith(
            manifest: _approvedManifest.replaceFirst(
              '''      E: permission (line=25)
        A: http://schemas.android.com/apk/res/android:name(0x01010003)="$approvedAndroidPermission" (Raw: "$approvedAndroidPermission")
        A: http://schemas.android.com/apk/res/android:protectionLevel(0x01010009)=0x00000002
''',
              '',
            ),
          ),
        ),
        _throwsPrivacyViolation,
      );
    });

    test('отклоняет package permission без signature protection level', () {
      expect(
        () => verifyPackagedAndroidPrivacyManifest(
          _approvedEvidence.copyWith(
            manifest: _approvedManifest.replaceFirst(
              'protectionLevel(0x01010009)=0x00000002',
              'protectionLevel(0x01010009)=0x00000000',
            ),
          ),
        ),
        _throwsPrivacyViolation,
      );
    });

    test('отклоняет выключенный allowBackup', () {
      expect(
        () => verifyPackagedAndroidPrivacyManifest(
          _approvedEvidence.copyWith(
            manifest: _approvedManifest.replaceFirst(
              'allowBackup(0x01010280)=true',
              'allowBackup(0x01010280)=false',
            ),
          ),
        ),
        _throwsPrivacyViolation,
      );
    });

    test('отклоняет отсутствие fullBackupContent reference', () {
      expect(
        () => verifyPackagedAndroidPrivacyManifest(
          _approvedEvidence.copyWith(
            manifest: _approvedManifest.replaceFirst(
              '        A: http://schemas.android.com/apk/res/android:fullBackupContent(0x010104eb)=@0x7f0e0000\n',
              '',
            ),
          ),
        ),
        _throwsPrivacyViolation,
      );
    });

    test('отклоняет неверный dataExtractionRules resource', () {
      expect(
        () => verifyPackagedAndroidPrivacyManifest(
          _approvedEvidence.copyWith(
            resources: _approvedResources.replaceFirst(
              'resource 0x7f0e0001 xml/data_extraction_rules',
              'resource 0x7f0e0001 xml/other_rules',
            ),
          ),
        ),
        _throwsPrivacyViolation,
      );
    });
  });
}

final _throwsPrivacyViolation = throwsA(isA<PackagedAndroidPrivacyViolation>());

final _approvedEvidence = PackagedAndroidPrivacyEvidence(
  permissions: _permissionDump(
    requestedPermissions: const <String>[approvedAndroidPermission],
  ),
  manifest: _approvedManifest,
  resources: _approvedResources,
);

String _permissionDump({required List<String> requestedPermissions}) =>
    '''
package: software.doable.doable
permission: $approvedAndroidPermission
${requestedPermissions.map((permission) => "uses-permission: name='$permission'").join('\n')}
''';

const _approvedManifest =
    '''
N: android=http://schemas.android.com/apk/res/android (line=2)
  E: manifest (line=2)
    A: package="software.doable.doable" (Raw: "software.doable.doable")
      E: permission (line=25)
        A: http://schemas.android.com/apk/res/android:name(0x01010003)="$approvedAndroidPermission" (Raw: "$approvedAndroidPermission")
        A: http://schemas.android.com/apk/res/android:protectionLevel(0x01010009)=0x00000002
      E: uses-permission (line=29)
        A: http://schemas.android.com/apk/res/android:name(0x01010003)="$approvedAndroidPermission" (Raw: "$approvedAndroidPermission")
      E: application (line=31)
        A: http://schemas.android.com/apk/res/android:allowBackup(0x01010280)=true
        A: http://schemas.android.com/apk/res/android:fullBackupContent(0x010104eb)=@0x7f0e0000
        A: http://schemas.android.com/apk/res/android:dataExtractionRules(0x0101063e)=@0x7f0e0001
''';

const _approvedResources = '''
Package name=software.doable.doable id=7f
  type xml id=0e entryCount=2
    resource 0x7f0e0000 xml/backup_rules
    resource 0x7f0e0001 xml/data_extraction_rules
''';
