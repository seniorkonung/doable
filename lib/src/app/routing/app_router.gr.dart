// dart format width=80
// GENERATED CODE - DO NOT MODIFY BY HAND

// **************************************************************************
// AutoRouterGenerator
// **************************************************************************

// ignore_for_file: type=lint
// coverage:ignore-file

// ignore_for_file: no_leading_underscores_for_library_prefixes

import 'package:auto_route/auto_route.dart' as _i4;
import 'package:doable/src/intention/domain/intention_id.dart' as _i5;
import 'package:doable/src/intention/presentation/catalog/intention_catalog_page.dart'
    as _i1;
import 'package:doable/src/intention/presentation/details/intention_details_page.dart'
    as _i2;
import 'package:doable/src/intention/presentation/editor/intention_editor_page.dart'
    as _i3;
import 'package:flutter/material.dart' as _i6;

/// generated route for
/// [_i1.IntentionCatalogPage]
class IntentionCatalogRoute extends _i4.PageRouteInfo<void> {
  const IntentionCatalogRoute({List<_i4.PageRouteInfo>? children})
    : super(IntentionCatalogRoute.name, initialChildren: children);

  static const String name = 'IntentionCatalogRoute';

  static _i4.PageInfo page = _i4.PageInfo(
    name,
    builder: (data) {
      return const _i1.IntentionCatalogPage();
    },
  );
}

/// generated route for
/// [_i2.IntentionDetailsPage]
class IntentionDetailsRoute
    extends _i4.PageRouteInfo<IntentionDetailsRouteArgs> {
  IntentionDetailsRoute({
    required _i5.IntentionId intentionId,
    _i6.Key? key,
    List<_i4.PageRouteInfo>? children,
  }) : super(
         IntentionDetailsRoute.name,
         args: IntentionDetailsRouteArgs(intentionId: intentionId, key: key),
         initialChildren: children,
       );

  static const String name = 'IntentionDetailsRoute';

  static _i4.PageInfo page = _i4.PageInfo(
    name,
    builder: (data) {
      final args = data.argsAs<IntentionDetailsRouteArgs>();
      return _i2.IntentionDetailsPage(
        intentionId: args.intentionId,
        key: args.key,
      );
    },
  );
}

class IntentionDetailsRouteArgs {
  const IntentionDetailsRouteArgs({required this.intentionId, this.key});

  final _i5.IntentionId intentionId;

  final _i6.Key? key;

  @override
  String toString() {
    return 'IntentionDetailsRouteArgs{intentionId: $intentionId, key: $key}';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! IntentionDetailsRouteArgs) return false;
    return intentionId == other.intentionId && key == other.key;
  }

  @override
  int get hashCode => intentionId.hashCode ^ key.hashCode;
}

/// generated route for
/// [_i3.IntentionEditorPage]
class IntentionEditorRoute extends _i4.PageRouteInfo<void> {
  const IntentionEditorRoute({List<_i4.PageRouteInfo>? children})
    : super(IntentionEditorRoute.name, initialChildren: children);

  static const String name = 'IntentionEditorRoute';

  static _i4.PageInfo page = _i4.PageInfo(
    name,
    builder: (data) {
      return const _i3.IntentionEditorPage();
    },
  );
}
