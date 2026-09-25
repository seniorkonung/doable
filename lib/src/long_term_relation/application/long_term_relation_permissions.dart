enum LongTermRelationPermissionRestriction { referencedByDailyPath }

enum _PermissionState { unknown, unrestricted, referencedByDailyPath }

/// Разрешения относятся к подтверждённому снимку, а не к полю связи.
final class LongTermRelationPermissions {
  const LongTermRelationPermissions.unknown()
    : _state = _PermissionState.unknown;

  const LongTermRelationPermissions.unrestricted()
    : _state = _PermissionState.unrestricted;

  const LongTermRelationPermissions.referencedByDailyPath()
    : _state = _PermissionState.referencedByDailyPath;

  final _PermissionState _state;

  bool get isConfirmed => _state != _PermissionState.unknown;

  LongTermRelationPermissionRestriction? get restriction =>
      _state == _PermissionState.referencedByDailyPath
      ? LongTermRelationPermissionRestriction.referencedByDailyPath
      : null;

  bool get canDelete => _state == _PermissionState.unrestricted;

  bool get canChangeMeaning => _state == _PermissionState.unrestricted;

  bool get canEditDescriptionAndPriority => isConfirmed;

  bool get canChangeArchiveState => isConfirmed;
}
