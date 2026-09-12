import 'dart:io';

const approvedAndroidPackage = 'software.doable.doable';
const approvedAndroidPermission =
    '$approvedAndroidPackage.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION';

final class PackagedAndroidPrivacyEvidence {
  const PackagedAndroidPrivacyEvidence({
    required this.permissions,
    required this.manifest,
    required this.resources,
  });

  final String permissions;
  final String manifest;
  final String resources;

  PackagedAndroidPrivacyEvidence copyWith({
    String? permissions,
    String? manifest,
    String? resources,
  }) => PackagedAndroidPrivacyEvidence(
    permissions: permissions ?? this.permissions,
    manifest: manifest ?? this.manifest,
    resources: resources ?? this.resources,
  );
}

final class PackagedAndroidPrivacyViolation implements Exception {
  const PackagedAndroidPrivacyViolation(this.message);

  final String message;

  @override
  String toString() => message;
}

void verifyPackagedAndroidPrivacyManifest(
  PackagedAndroidPrivacyEvidence evidence,
) {
  final permissionDump = _parsePermissionDump(evidence.permissions);

  if (permissionDump.packageName != approvedAndroidPackage) {
    throw const PackagedAndroidPrivacyViolation(
      'Packaged manifest относится к неожиданному Android package',
    );
  }
  _requireExactPermission(
    permissionDump.declaredPermissions,
    evidenceName: 'деклараций permission',
  );
  _requireExactPermission(
    permissionDump.requestedPermissions,
    evidenceName: 'запрашиваемых permissions',
  );

  final permissionBlocks = _directAttributeBlocks(
    evidence.manifest,
    elementName: 'permission',
  ).where(_declaresApprovedPermission).toList(growable: false);
  if (permissionBlocks.length != 1 ||
      !_hasNumericAttribute(
        permissionBlocks.single,
        name: 'protectionLevel',
        value: '0x00000002',
      )) {
    throw const PackagedAndroidPrivacyViolation(
      'Packaged manifest не объявляет утверждённое permission как signature',
    );
  }

  final applicationBlocks = _directAttributeBlocks(
    evidence.manifest,
    elementName: 'application',
  );
  if (applicationBlocks.length != 1) {
    throw const PackagedAndroidPrivacyViolation(
      'Packaged manifest не содержит единственный application element',
    );
  }
  final application = applicationBlocks.single;
  if (!_hasNumericAttribute(application, name: 'allowBackup', value: 'true')) {
    throw const PackagedAndroidPrivacyViolation(
      'Packaged manifest не включает утверждённые backup rules',
    );
  }

  _requireXmlReference(
    application,
    resources: evidence.resources,
    attributeName: 'fullBackupContent',
    resourceName: 'backup_rules',
  );
  _requireXmlReference(
    application,
    resources: evidence.resources,
    attributeName: 'dataExtractionRules',
    resourceName: 'data_extraction_rules',
  );
}

Future<void> main(List<String> arguments) async {
  if (arguments.length != 2) {
    stderr.writeln(
      'Использование: dart run tool/check_android_privacy_manifest.dart '
      '<aapt2> <release-apk>',
    );
    exitCode = 2;
    return;
  }

  final aapt2 = arguments[0];
  final apk = arguments[1];
  if (!File(aapt2).existsSync()) {
    stderr.writeln('Не найден executable aapt2: $aapt2');
    exitCode = 1;
    return;
  }
  if (!File(apk).existsSync()) {
    stderr.writeln('Не найден release APK: $apk');
    exitCode = 1;
    return;
  }

  try {
    final dumps = await Future.wait(<Future<String>>[
      _runAapt2(aapt2, <String>['dump', 'permissions', apk]),
      _runAapt2(aapt2, <String>[
        'dump',
        'xmltree',
        apk,
        '--file',
        'AndroidManifest.xml',
      ]),
      _runAapt2(aapt2, <String>['dump', 'resources', apk]),
    ]);
    verifyPackagedAndroidPrivacyManifest(
      PackagedAndroidPrivacyEvidence(
        permissions: dumps[0],
        manifest: dumps[1],
        resources: dumps[2],
      ),
    );
  } on PackagedAndroidPrivacyViolation catch (error) {
    stderr.writeln('Проверка Android privacy manifest не пройдена: $error');
    exitCode = 1;
    return;
  } on ProcessException catch (error) {
    stderr.writeln('Не удалось запустить aapt2: ${error.message}');
    exitCode = 1;
    return;
  }

  stdout.writeln('Packaged Android privacy manifest соответствует политике');
}

Future<String> _runAapt2(String executable, List<String> arguments) async {
  final result = await Process.run(executable, arguments);
  if (result.exitCode != 0) {
    throw PackagedAndroidPrivacyViolation(
      'aapt2 завершился с кодом ${result.exitCode}',
    );
  }
  if (result.stdout case final String output) {
    return output;
  }
  throw const PackagedAndroidPrivacyViolation(
    'aapt2 вернул evidence неожиданного типа',
  );
}

_PermissionDump _parsePermissionDump(String source) {
  final lines = source
      .split(RegExp(r'\r?\n'))
      .where((line) => line.isNotEmpty)
      .toList(growable: false);
  if (lines.isEmpty) {
    throw const PackagedAndroidPrivacyViolation(
      'Permission evidence отсутствует',
    );
  }

  String? packageName;
  final declaredPermissions = <String>[];
  final requestedPermissions = <String>[];
  final packagePattern = RegExp(r'^package: ([A-Za-z0-9_.]+)$');
  final declarationPattern = RegExp(r'^permission: ([A-Za-z0-9_.]+)$');
  final requestPattern = RegExp(
    r"^(?:uses-permission|uses-permission-sdk-23): name='([A-Za-z0-9_.]+)'$",
  );

  for (final line in lines) {
    if (packagePattern.firstMatch(line) case final match?) {
      if (packageName != null) {
        throw const PackagedAndroidPrivacyViolation(
          'Permission evidence содержит повторный package',
        );
      }
      packageName = match.group(1)!;
      continue;
    }
    if (declarationPattern.firstMatch(line) case final match?) {
      declaredPermissions.add(match.group(1)!);
      continue;
    }
    if (requestPattern.firstMatch(line) case final match?) {
      requestedPermissions.add(match.group(1)!);
      continue;
    }
    throw PackagedAndroidPrivacyViolation(
      'Permission evidence имеет неожиданный формат: $line',
    );
  }

  if (packageName == null) {
    throw const PackagedAndroidPrivacyViolation(
      'Permission evidence не содержит package',
    );
  }
  return _PermissionDump(
    packageName: packageName,
    declaredPermissions: declaredPermissions,
    requestedPermissions: requestedPermissions,
  );
}

void _requireExactPermission(
  List<String> permissions, {
  required String evidenceName,
}) {
  if (permissions.length != 1 ||
      permissions.single != approvedAndroidPermission) {
    throw PackagedAndroidPrivacyViolation(
      'Нарушен exact allowlist $evidenceName: ${permissions.join(', ')}',
    );
  }
}

List<List<String>> _directAttributeBlocks(
  String source, {
  required String elementName,
}) {
  final lines = source.split(RegExp(r'\r?\n'));
  final elementPattern = RegExp(
    '^([ ]*)E: ${RegExp.escape(elementName)}(?: \\(line=[0-9]+\\))?[ ]*\$',
  );
  final anyElementPattern = RegExp(r'^([ ]*)E: ');
  final blocks = <List<String>>[];

  for (var index = 0; index < lines.length; index += 1) {
    final elementMatch = elementPattern.firstMatch(lines[index]);
    if (elementMatch == null) {
      continue;
    }
    final indentation = elementMatch.group(1)!.length;
    final attributes = <String>[];
    for (
      var childIndex = index + 1;
      childIndex < lines.length;
      childIndex += 1
    ) {
      final child = lines[childIndex];
      final nextElement = anyElementPattern.firstMatch(child);
      if (nextElement != null) {
        if (nextElement.group(1)!.length <= indentation) {
          break;
        }
        break;
      }
      if (child.trimLeft().startsWith('A: ')) {
        attributes.add(child.trimLeft());
      } else if (child.trim().isNotEmpty) {
        throw PackagedAndroidPrivacyViolation(
          'Manifest evidence имеет неожиданный формат: $child',
        );
      }
    }
    blocks.add(attributes);
  }
  return blocks;
}

bool _declaresApprovedPermission(List<String> attributes) => attributes.any(
  (attribute) => RegExp(
    ':name\\([^)]*\\)="${RegExp.escape(approvedAndroidPermission)}" '
    '\\(Raw: "${RegExp.escape(approvedAndroidPermission)}"\\)\$',
  ).hasMatch(attribute),
);

bool _hasNumericAttribute(
  List<String> attributes, {
  required String name,
  required String value,
}) => attributes.any(
  (attribute) =>
      RegExp(':${RegExp.escape(name)}\\([^)]*\\)=${RegExp.escape(value)}\$')
          .hasMatch(attribute),
);

void _requireXmlReference(
  List<String> applicationAttributes, {
  required String resources,
  required String attributeName,
  required String resourceName,
}) {
  final referencePattern = RegExp(
    ':${RegExp.escape(attributeName)}\\([^)]*\\)=@(0x[0-9a-fA-F]+)\$',
  );
  final references = <String>[
    for (final attribute in applicationAttributes)
      if (referencePattern.firstMatch(attribute) case final match?)
        match.group(1)!,
  ];
  if (references.length != 1) {
    throw PackagedAndroidPrivacyViolation(
      'Packaged manifest не содержит единственную ссылку $attributeName',
    );
  }

  final resourcePattern = RegExp(
    '^\\s*resource ${RegExp.escape(references.single)} '
    'xml/${RegExp.escape(resourceName)}\\s*\$',
    multiLine: true,
  );
  if (!resourcePattern.hasMatch(resources)) {
    throw PackagedAndroidPrivacyViolation(
      'Ссылка $attributeName не указывает на @xml/$resourceName',
    );
  }
}

final class _PermissionDump {
  const _PermissionDump({
    required this.packageName,
    required this.declaredPermissions,
    required this.requestedPermissions,
  });

  final String packageName;
  final List<String> declaredPermissions;
  final List<String> requestedPermissions;
}
