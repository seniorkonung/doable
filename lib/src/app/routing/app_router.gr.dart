// dart format width=80
// GENERATED CODE - DO NOT MODIFY BY HAND

// **************************************************************************
// AutoRouterGenerator
// **************************************************************************

// ignore_for_file: type=lint
// coverage:ignore-file

// ignore_for_file: no_leading_underscores_for_library_prefixes

import 'package:auto_route/auto_route.dart' as _i3;
import 'package:doable/src/intention/presentation/catalog/intention_catalog_page.dart'
    as _i1;
import 'package:doable/src/intention/presentation/editor/intention_editor_page.dart'
    as _i2;

/// generated route for
/// [_i1.IntentionCatalogPage]
class IntentionCatalogRoute extends _i3.PageRouteInfo<void> {
  const IntentionCatalogRoute({List<_i3.PageRouteInfo>? children})
    : super(IntentionCatalogRoute.name, initialChildren: children);

  static const String name = 'IntentionCatalogRoute';

  static _i3.PageInfo page = _i3.PageInfo(
    name,
    builder: (data) {
      return const _i1.IntentionCatalogPage();
    },
  );
}

/// generated route for
/// [_i2.IntentionEditorPage]
class IntentionEditorRoute extends _i3.PageRouteInfo<void> {
  const IntentionEditorRoute({List<_i3.PageRouteInfo>? children})
    : super(IntentionEditorRoute.name, initialChildren: children);

  static const String name = 'IntentionEditorRoute';

  static _i3.PageInfo page = _i3.PageInfo(
    name,
    builder: (data) {
      return const _i2.IntentionEditorPage();
    },
  );
}
