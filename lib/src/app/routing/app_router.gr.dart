// dart format width=80
// GENERATED CODE - DO NOT MODIFY BY HAND

// **************************************************************************
// AutoRouterGenerator
// **************************************************************************

// ignore_for_file: type=lint
// coverage:ignore-file

// ignore_for_file: no_leading_underscores_for_library_prefixes

import 'package:auto_route/auto_route.dart' as _i8;
import 'package:doable/src/daily_choice/presentation/path/choice_path_page.dart'
    as _i1;
import 'package:doable/src/intention/domain/intention_id.dart' as _i9;
import 'package:doable/src/intention/presentation/catalog/intention_catalog_page.dart'
    as _i2;
import 'package:doable/src/intention/presentation/catalog/intention_catalog_purpose.dart'
    as _i13;
import 'package:doable/src/intention/presentation/details/intention_details_page.dart'
    as _i3;
import 'package:doable/src/intention/presentation/editor/intention_editor_page.dart'
    as _i4;
import 'package:doable/src/long_term_relation/domain/long_term_relation_id.dart'
    as _i11;
import 'package:doable/src/long_term_relation/presentation/details/relation_details_page.dart'
    as _i5;
import 'package:doable/src/long_term_relation/presentation/editor/relation_editor_page.dart'
    as _i6;
import 'package:doable/src/long_term_relation/presentation/editor/relation_editor_state.dart'
    as _i12;
import 'package:doable/src/long_term_relation/presentation/participant_picker/relation_participant_picker_page.dart'
    as _i7;
import 'package:flutter/material.dart' as _i10;

/// generated route for
/// [_i1.ChoicePathPage]
class ChoicePathRoute extends _i8.PageRouteInfo<ChoicePathRouteArgs> {
  ChoicePathRoute({
    required _i9.IntentionId sourceIntentionId,
    _i10.Key? key,
    List<_i8.PageRouteInfo>? children,
  }) : super(
         ChoicePathRoute.name,
         args: ChoicePathRouteArgs(
           sourceIntentionId: sourceIntentionId,
           key: key,
         ),
         initialChildren: children,
       );

  static const String name = 'ChoicePathRoute';

  static _i8.PageInfo page = _i8.PageInfo(
    name,
    builder: (data) {
      final args = data.argsAs<ChoicePathRouteArgs>();
      return _i1.ChoicePathPage(
        sourceIntentionId: args.sourceIntentionId,
        key: args.key,
      );
    },
  );
}

class ChoicePathRouteArgs {
  const ChoicePathRouteArgs({required this.sourceIntentionId, this.key});

  final _i9.IntentionId sourceIntentionId;

  final _i10.Key? key;

  @override
  String toString() {
    return 'ChoicePathRouteArgs{sourceIntentionId: $sourceIntentionId, key: $key}';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! ChoicePathRouteArgs) return false;
    return sourceIntentionId == other.sourceIntentionId && key == other.key;
  }

  @override
  int get hashCode => sourceIntentionId.hashCode ^ key.hashCode;
}

/// generated route for
/// [_i2.IntentionCatalogPage]
class IntentionCatalogRoute extends _i8.PageRouteInfo<void> {
  const IntentionCatalogRoute({List<_i8.PageRouteInfo>? children})
    : super(IntentionCatalogRoute.name, initialChildren: children);

  static const String name = 'IntentionCatalogRoute';

  static _i8.PageInfo page = _i8.PageInfo(
    name,
    builder: (data) {
      return const _i2.IntentionCatalogPage();
    },
  );
}

/// generated route for
/// [_i3.IntentionDetailsPage]
class IntentionDetailsRoute
    extends _i8.PageRouteInfo<IntentionDetailsRouteArgs> {
  IntentionDetailsRoute({
    required _i9.IntentionId intentionId,
    _i10.Key? key,
    List<_i8.PageRouteInfo>? children,
  }) : super(
         IntentionDetailsRoute.name,
         args: IntentionDetailsRouteArgs(intentionId: intentionId, key: key),
         initialChildren: children,
       );

  static const String name = 'IntentionDetailsRoute';

  static _i8.PageInfo page = _i8.PageInfo(
    name,
    builder: (data) {
      final args = data.argsAs<IntentionDetailsRouteArgs>();
      return _i3.IntentionDetailsPage(
        intentionId: args.intentionId,
        key: args.key,
      );
    },
  );
}

class IntentionDetailsRouteArgs {
  const IntentionDetailsRouteArgs({required this.intentionId, this.key});

  final _i9.IntentionId intentionId;

  final _i10.Key? key;

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
/// [_i4.IntentionEditorPage]
class IntentionEditorRoute extends _i8.PageRouteInfo<void> {
  const IntentionEditorRoute({List<_i8.PageRouteInfo>? children})
    : super(IntentionEditorRoute.name, initialChildren: children);

  static const String name = 'IntentionEditorRoute';

  static _i8.PageInfo page = _i8.PageInfo(
    name,
    builder: (data) {
      return const _i4.IntentionEditorPage();
    },
  );
}

/// generated route for
/// [_i5.RelationDetailsPage]
class RelationDetailsRoute extends _i8.PageRouteInfo<RelationDetailsRouteArgs> {
  RelationDetailsRoute({
    required _i11.LongTermRelationId relationId,
    _i10.Key? key,
    List<_i8.PageRouteInfo>? children,
  }) : super(
         RelationDetailsRoute.name,
         args: RelationDetailsRouteArgs(relationId: relationId, key: key),
         initialChildren: children,
       );

  static const String name = 'RelationDetailsRoute';

  static _i8.PageInfo page = _i8.PageInfo(
    name,
    builder: (data) {
      final args = data.argsAs<RelationDetailsRouteArgs>();
      return _i5.RelationDetailsPage(
        relationId: args.relationId,
        key: args.key,
      );
    },
  );
}

class RelationDetailsRouteArgs {
  const RelationDetailsRouteArgs({required this.relationId, this.key});

  final _i11.LongTermRelationId relationId;

  final _i10.Key? key;

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
/// [_i6.RelationEditorPage]
class RelationEditorRoute extends _i8.PageRouteInfo<RelationEditorRouteArgs> {
  RelationEditorRoute({
    required _i12.RelationEditorContext editorContext,
    _i10.Key? key,
    List<_i8.PageRouteInfo>? children,
  }) : super(
         RelationEditorRoute.name,
         args: RelationEditorRouteArgs(editorContext: editorContext, key: key),
         initialChildren: children,
       );

  static const String name = 'RelationEditorRoute';

  static _i8.PageInfo page = _i8.PageInfo(
    name,
    builder: (data) {
      final args = data.argsAs<RelationEditorRouteArgs>();
      return _i6.RelationEditorPage(
        editorContext: args.editorContext,
        key: args.key,
      );
    },
  );
}

class RelationEditorRouteArgs {
  const RelationEditorRouteArgs({required this.editorContext, this.key});

  final _i12.RelationEditorContext editorContext;

  final _i10.Key? key;

  @override
  String toString() {
    return 'RelationEditorRouteArgs{editorContext: $editorContext, key: $key}';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! RelationEditorRouteArgs) return false;
    return editorContext == other.editorContext && key == other.key;
  }

  @override
  int get hashCode => editorContext.hashCode ^ key.hashCode;
}

/// generated route for
/// [_i7.RelationParticipantPickerPage]
class RelationParticipantPickerRoute
    extends _i8.PageRouteInfo<RelationParticipantPickerRouteArgs> {
  RelationParticipantPickerRoute({
    required _i9.IntentionId excludedIntentionId,
    required _i13.RelationParticipantSelectionContext selectionContext,
    _i10.Key? key,
    List<_i8.PageRouteInfo>? children,
  }) : super(
         RelationParticipantPickerRoute.name,
         args: RelationParticipantPickerRouteArgs(
           excludedIntentionId: excludedIntentionId,
           selectionContext: selectionContext,
           key: key,
         ),
         initialChildren: children,
       );

  static const String name = 'RelationParticipantPickerRoute';

  static _i8.PageInfo page = _i8.PageInfo(
    name,
    builder: (data) {
      final args = data.argsAs<RelationParticipantPickerRouteArgs>();
      return _i7.RelationParticipantPickerPage(
        excludedIntentionId: args.excludedIntentionId,
        selectionContext: args.selectionContext,
        key: args.key,
      );
    },
  );
}

class RelationParticipantPickerRouteArgs {
  const RelationParticipantPickerRouteArgs({
    required this.excludedIntentionId,
    required this.selectionContext,
    this.key,
  });

  final _i9.IntentionId excludedIntentionId;

  final _i13.RelationParticipantSelectionContext selectionContext;

  final _i10.Key? key;

  @override
  String toString() {
    return 'RelationParticipantPickerRouteArgs{excludedIntentionId: $excludedIntentionId, selectionContext: $selectionContext, key: $key}';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! RelationParticipantPickerRouteArgs) return false;
    return excludedIntentionId == other.excludedIntentionId &&
        selectionContext == other.selectionContext &&
        key == other.key;
  }

  @override
  int get hashCode =>
      excludedIntentionId.hashCode ^ selectionContext.hashCode ^ key.hashCode;
}
