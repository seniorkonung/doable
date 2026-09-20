// dart format width=80
// GENERATED CODE - DO NOT MODIFY BY HAND

// **************************************************************************
// AutoRouterGenerator
// **************************************************************************

// ignore_for_file: type=lint
// coverage:ignore-file

// ignore_for_file: no_leading_underscores_for_library_prefixes

import 'package:auto_route/auto_route.dart' as _i7;
import 'package:doable/src/intention/domain/intention_id.dart' as _i8;
import 'package:doable/src/intention/presentation/catalog/intention_catalog_page.dart'
    as _i1;
import 'package:doable/src/intention/presentation/details/intention_details_page.dart'
    as _i2;
import 'package:doable/src/intention/presentation/editor/intention_editor_page.dart'
    as _i3;
import 'package:doable/src/long_term_relation/domain/long_term_relation_id.dart'
    as _i10;
import 'package:doable/src/long_term_relation/presentation/details/relation_details_page.dart'
    as _i4;
import 'package:doable/src/long_term_relation/presentation/editor/relation_editor_page.dart'
    as _i5;
import 'package:doable/src/long_term_relation/presentation/editor/relation_editor_state.dart'
    as _i11;
import 'package:doable/src/long_term_relation/presentation/participant_picker/relation_participant_picker_page.dart'
    as _i6;
import 'package:flutter/material.dart' as _i9;

/// generated route for
/// [_i1.IntentionCatalogPage]
class IntentionCatalogRoute extends _i7.PageRouteInfo<void> {
  const IntentionCatalogRoute({List<_i7.PageRouteInfo>? children})
    : super(IntentionCatalogRoute.name, initialChildren: children);

  static const String name = 'IntentionCatalogRoute';

  static _i7.PageInfo page = _i7.PageInfo(
    name,
    builder: (data) {
      return const _i1.IntentionCatalogPage();
    },
  );
}

/// generated route for
/// [_i2.IntentionDetailsPage]
class IntentionDetailsRoute
    extends _i7.PageRouteInfo<IntentionDetailsRouteArgs> {
  IntentionDetailsRoute({
    required _i8.IntentionId intentionId,
    _i9.Key? key,
    List<_i7.PageRouteInfo>? children,
  }) : super(
         IntentionDetailsRoute.name,
         args: IntentionDetailsRouteArgs(intentionId: intentionId, key: key),
         initialChildren: children,
       );

  static const String name = 'IntentionDetailsRoute';

  static _i7.PageInfo page = _i7.PageInfo(
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

  final _i8.IntentionId intentionId;

  final _i9.Key? key;

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
class IntentionEditorRoute extends _i7.PageRouteInfo<void> {
  const IntentionEditorRoute({List<_i7.PageRouteInfo>? children})
    : super(IntentionEditorRoute.name, initialChildren: children);

  static const String name = 'IntentionEditorRoute';

  static _i7.PageInfo page = _i7.PageInfo(
    name,
    builder: (data) {
      return const _i3.IntentionEditorPage();
    },
  );
}

/// generated route for
/// [_i4.RelationDetailsPage]
class RelationDetailsRoute extends _i7.PageRouteInfo<RelationDetailsRouteArgs> {
  RelationDetailsRoute({
    required _i10.LongTermRelationId relationId,
    _i9.Key? key,
    List<_i7.PageRouteInfo>? children,
  }) : super(
         RelationDetailsRoute.name,
         args: RelationDetailsRouteArgs(relationId: relationId, key: key),
         initialChildren: children,
       );

  static const String name = 'RelationDetailsRoute';

  static _i7.PageInfo page = _i7.PageInfo(
    name,
    builder: (data) {
      final args = data.argsAs<RelationDetailsRouteArgs>();
      return _i4.RelationDetailsPage(
        relationId: args.relationId,
        key: args.key,
      );
    },
  );
}

class RelationDetailsRouteArgs {
  const RelationDetailsRouteArgs({required this.relationId, this.key});

  final _i10.LongTermRelationId relationId;

  final _i9.Key? key;

  @override
  String toString() {
    return 'RelationDetailsRouteArgs{relationId: $relationId, key: $key}';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! RelationDetailsRouteArgs) return false;
    return relationId == other.relationId && key == other.key;
  }

  @override
  int get hashCode => relationId.hashCode ^ key.hashCode;
}

/// generated route for
/// [_i5.RelationEditorPage]
class RelationEditorRoute extends _i7.PageRouteInfo<RelationEditorRouteArgs> {
  RelationEditorRoute({
    required _i11.RelationCreationContext creationContext,
    _i9.Key? key,
    List<_i7.PageRouteInfo>? children,
  }) : super(
         RelationEditorRoute.name,
         args: RelationEditorRouteArgs(
           creationContext: creationContext,
           key: key,
         ),
         initialChildren: children,
       );

  static const String name = 'RelationEditorRoute';

  static _i7.PageInfo page = _i7.PageInfo(
    name,
    builder: (data) {
      final args = data.argsAs<RelationEditorRouteArgs>();
      return _i5.RelationEditorPage(
        creationContext: args.creationContext,
        key: args.key,
      );
    },
  );
}

class RelationEditorRouteArgs {
  const RelationEditorRouteArgs({required this.creationContext, this.key});

  final _i11.RelationCreationContext creationContext;

  final _i9.Key? key;

  @override
  String toString() {
    return 'RelationEditorRouteArgs{creationContext: $creationContext, key: $key}';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! RelationEditorRouteArgs) return false;
    return creationContext == other.creationContext && key == other.key;
  }

  @override
  int get hashCode => creationContext.hashCode ^ key.hashCode;
}

/// generated route for
/// [_i6.RelationParticipantPickerPage]
class RelationParticipantPickerRoute
    extends _i7.PageRouteInfo<RelationParticipantPickerRouteArgs> {
  RelationParticipantPickerRoute({
    required _i8.IntentionId excludedIntentionId,
    _i9.Key? key,
    List<_i7.PageRouteInfo>? children,
  }) : super(
         RelationParticipantPickerRoute.name,
         args: RelationParticipantPickerRouteArgs(
           excludedIntentionId: excludedIntentionId,
           key: key,
         ),
         initialChildren: children,
       );

  static const String name = 'RelationParticipantPickerRoute';

  static _i7.PageInfo page = _i7.PageInfo(
    name,
    builder: (data) {
      final args = data.argsAs<RelationParticipantPickerRouteArgs>();
      return _i6.RelationParticipantPickerPage(
        excludedIntentionId: args.excludedIntentionId,
        key: args.key,
      );
    },
  );
}

class RelationParticipantPickerRouteArgs {
  const RelationParticipantPickerRouteArgs({
    required this.excludedIntentionId,
    this.key,
  });

  final _i8.IntentionId excludedIntentionId;

  final _i9.Key? key;

  @override
  String toString() {
    return 'RelationParticipantPickerRouteArgs{excludedIntentionId: $excludedIntentionId, key: $key}';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! RelationParticipantPickerRouteArgs) return false;
    return excludedIntentionId == other.excludedIntentionId && key == other.key;
  }

  @override
  int get hashCode => excludedIntentionId.hashCode ^ key.hashCode;
}
