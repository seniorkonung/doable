// dart format width=80
// GENERATED CODE - DO NOT MODIFY BY HAND

// **************************************************************************
// AutoRouterGenerator
// **************************************************************************

// ignore_for_file: type=lint
// coverage:ignore-file

// ignore_for_file: no_leading_underscores_for_library_prefixes

import 'package:auto_route/auto_route.dart' as _i9;
import 'package:doable/src/daily_choice/domain/daily_choice_id.dart' as _i12;
import 'package:doable/src/daily_choice/presentation/details/daily_choice_details_page.dart'
    as _i2;
import 'package:doable/src/daily_choice/presentation/path/choice_path_page.dart'
    as _i1;
import 'package:doable/src/intention/domain/intention_id.dart' as _i10;
import 'package:doable/src/intention/presentation/catalog/intention_catalog_page.dart'
    as _i3;
import 'package:doable/src/intention/presentation/catalog/intention_catalog_purpose.dart'
    as _i15;
import 'package:doable/src/intention/presentation/details/intention_details_page.dart'
    as _i4;
import 'package:doable/src/intention/presentation/editor/intention_editor_page.dart'
    as _i5;
import 'package:doable/src/long_term_relation/domain/long_term_relation_id.dart'
    as _i13;
import 'package:doable/src/long_term_relation/presentation/details/relation_details_page.dart'
    as _i6;
import 'package:doable/src/long_term_relation/presentation/editor/relation_editor_page.dart'
    as _i7;
import 'package:doable/src/long_term_relation/presentation/editor/relation_editor_state.dart'
    as _i14;
import 'package:doable/src/long_term_relation/presentation/participant_picker/relation_participant_picker_page.dart'
    as _i8;
import 'package:flutter/material.dart' as _i11;

/// generated route for
/// [_i1.ChoicePathPage]
class ChoicePathRoute extends _i9.PageRouteInfo<ChoicePathRouteArgs> {
  ChoicePathRoute({
    required _i10.IntentionId sourceIntentionId,
    _i11.Key? key,
    List<_i9.PageRouteInfo>? children,
  }) : super(
         ChoicePathRoute.name,
         args: ChoicePathRouteArgs(
           sourceIntentionId: sourceIntentionId,
           key: key,
         ),
         initialChildren: children,
       );

  static const String name = 'ChoicePathRoute';

  static _i9.PageInfo page = _i9.PageInfo(
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

  final _i10.IntentionId sourceIntentionId;

  final _i11.Key? key;

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
/// [_i2.DailyChoiceDetailsPage]
class DailyChoiceDetailsRoute
    extends _i9.PageRouteInfo<DailyChoiceDetailsRouteArgs> {
  DailyChoiceDetailsRoute({
    required _i12.DailyChoiceId choiceId,
    _i11.Key? key,
    List<_i9.PageRouteInfo>? children,
  }) : super(
         DailyChoiceDetailsRoute.name,
         args: DailyChoiceDetailsRouteArgs(choiceId: choiceId, key: key),
         initialChildren: children,
       );

  static const String name = 'DailyChoiceDetailsRoute';

  static _i9.PageInfo page = _i9.PageInfo(
    name,
    builder: (data) {
      final args = data.argsAs<DailyChoiceDetailsRouteArgs>();
      return _i2.DailyChoiceDetailsPage(choiceId: args.choiceId, key: args.key);
    },
  );
}

class DailyChoiceDetailsRouteArgs {
  const DailyChoiceDetailsRouteArgs({required this.choiceId, this.key});

  final _i12.DailyChoiceId choiceId;

  final _i11.Key? key;

  @override
  String toString() {
    return 'DailyChoiceDetailsRouteArgs{choiceId: $choiceId, key: $key}';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! DailyChoiceDetailsRouteArgs) return false;
    return choiceId == other.choiceId && key == other.key;
  }

  @override
  int get hashCode => choiceId.hashCode ^ key.hashCode;
}

/// generated route for
/// [_i3.IntentionCatalogPage]
class IntentionCatalogRoute extends _i9.PageRouteInfo<void> {
  const IntentionCatalogRoute({List<_i9.PageRouteInfo>? children})
    : super(IntentionCatalogRoute.name, initialChildren: children);

  static const String name = 'IntentionCatalogRoute';

  static _i9.PageInfo page = _i9.PageInfo(
    name,
    builder: (data) {
      return const _i3.IntentionCatalogPage();
    },
  );
}

/// generated route for
/// [_i4.IntentionDetailsPage]
class IntentionDetailsRoute
    extends _i9.PageRouteInfo<IntentionDetailsRouteArgs> {
  IntentionDetailsRoute({
    required _i10.IntentionId intentionId,
    _i11.Key? key,
    List<_i9.PageRouteInfo>? children,
  }) : super(
         IntentionDetailsRoute.name,
         args: IntentionDetailsRouteArgs(intentionId: intentionId, key: key),
         initialChildren: children,
       );

  static const String name = 'IntentionDetailsRoute';

  static _i9.PageInfo page = _i9.PageInfo(
    name,
    builder: (data) {
      final args = data.argsAs<IntentionDetailsRouteArgs>();
      return _i4.IntentionDetailsPage(
        intentionId: args.intentionId,
        key: args.key,
      );
    },
  );
}

class IntentionDetailsRouteArgs {
  const IntentionDetailsRouteArgs({required this.intentionId, this.key});

  final _i10.IntentionId intentionId;

  final _i11.Key? key;

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
/// [_i5.IntentionEditorPage]
class IntentionEditorRoute extends _i9.PageRouteInfo<void> {
  const IntentionEditorRoute({List<_i9.PageRouteInfo>? children})
    : super(IntentionEditorRoute.name, initialChildren: children);

  static const String name = 'IntentionEditorRoute';

  static _i9.PageInfo page = _i9.PageInfo(
    name,
    builder: (data) {
      return const _i5.IntentionEditorPage();
    },
  );
}

/// generated route for
/// [_i6.RelationDetailsPage]
class RelationDetailsRoute extends _i9.PageRouteInfo<RelationDetailsRouteArgs> {
  RelationDetailsRoute({
    required _i13.LongTermRelationId relationId,
    _i11.Key? key,
    List<_i9.PageRouteInfo>? children,
  }) : super(
         RelationDetailsRoute.name,
         args: RelationDetailsRouteArgs(relationId: relationId, key: key),
         initialChildren: children,
       );

  static const String name = 'RelationDetailsRoute';

  static _i9.PageInfo page = _i9.PageInfo(
    name,
    builder: (data) {
      final args = data.argsAs<RelationDetailsRouteArgs>();
      return _i6.RelationDetailsPage(
        relationId: args.relationId,
        key: args.key,
      );
    },
  );
}

class RelationDetailsRouteArgs {
  const RelationDetailsRouteArgs({required this.relationId, this.key});

  final _i13.LongTermRelationId relationId;

  final _i11.Key? key;

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
/// [_i7.RelationEditorPage]
class RelationEditorRoute extends _i9.PageRouteInfo<RelationEditorRouteArgs> {
  RelationEditorRoute({
    required _i14.RelationEditorContext editorContext,
    _i11.Key? key,
    List<_i9.PageRouteInfo>? children,
  }) : super(
         RelationEditorRoute.name,
         args: RelationEditorRouteArgs(editorContext: editorContext, key: key),
         initialChildren: children,
       );

  static const String name = 'RelationEditorRoute';

  static _i9.PageInfo page = _i9.PageInfo(
    name,
    builder: (data) {
      final args = data.argsAs<RelationEditorRouteArgs>();
      return _i7.RelationEditorPage(
        editorContext: args.editorContext,
        key: args.key,
      );
    },
  );
}

class RelationEditorRouteArgs {
  const RelationEditorRouteArgs({required this.editorContext, this.key});

  final _i14.RelationEditorContext editorContext;

  final _i11.Key? key;

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
/// [_i8.RelationParticipantPickerPage]
class RelationParticipantPickerRoute
    extends _i9.PageRouteInfo<RelationParticipantPickerRouteArgs> {
  RelationParticipantPickerRoute({
    required _i10.IntentionId excludedIntentionId,
    required _i15.RelationParticipantSelectionContext selectionContext,
    _i11.Key? key,
    List<_i9.PageRouteInfo>? children,
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

  static _i9.PageInfo page = _i9.PageInfo(
    name,
    builder: (data) {
      final args = data.argsAs<RelationParticipantPickerRouteArgs>();
      return _i8.RelationParticipantPickerPage(
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

  final _i10.IntentionId excludedIntentionId;

  final _i15.RelationParticipantSelectionContext selectionContext;

  final _i11.Key? key;

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
