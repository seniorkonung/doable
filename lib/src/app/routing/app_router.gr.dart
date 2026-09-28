// dart format width=80
// GENERATED CODE - DO NOT MODIFY BY HAND

// **************************************************************************
// AutoRouterGenerator
// **************************************************************************

// ignore_for_file: type=lint
// coverage:ignore-file

// ignore_for_file: no_leading_underscores_for_library_prefixes

import 'package:auto_route/auto_route.dart' as _i16;
import 'package:doable/src/daily_choice/application/daily_choice_details.dart'
    as _i20;
import 'package:doable/src/daily_choice/domain/daily_choice_id.dart' as _i19;
import 'package:doable/src/daily_choice/presentation/action_picker/daily_choice_action_picker_page.dart'
    as _i2;
import 'package:doable/src/daily_choice/presentation/catalog/daily_choice_catalog_page.dart'
    as _i3;
import 'package:doable/src/daily_choice/presentation/details/daily_choice_details_page.dart'
    as _i4;
import 'package:doable/src/daily_choice/presentation/editor/daily_choice_edit_page.dart'
    as _i5;
import 'package:doable/src/daily_choice/presentation/path/choice_path_page.dart'
    as _i1;
import 'package:doable/src/daily_choice/presentation/source_picker/daily_choice_source_picker_page.dart'
    as _i6;
import 'package:doable/src/intention/domain/intention_id.dart' as _i17;
import 'package:doable/src/intention/presentation/catalog/intention_catalog_page.dart'
    as _i7;
import 'package:doable/src/intention/presentation/catalog/intention_catalog_purpose.dart'
    as _i23;
import 'package:doable/src/intention/presentation/details/intention_details_page.dart'
    as _i8;
import 'package:doable/src/intention/presentation/editor/intention_editor_page.dart'
    as _i9;
import 'package:doable/src/long_term_relation/domain/long_term_relation_id.dart'
    as _i21;
import 'package:doable/src/long_term_relation/presentation/details/relation_details_page.dart'
    as _i10;
import 'package:doable/src/long_term_relation/presentation/editor/relation_editor_page.dart'
    as _i11;
import 'package:doable/src/long_term_relation/presentation/editor/relation_editor_state.dart'
    as _i22;
import 'package:doable/src/long_term_relation/presentation/participant_picker/relation_participant_picker_page.dart'
    as _i12;
import 'package:doable/src/tag/domain/tag_id.dart' as _i26;
import 'package:doable/src/tag/domain/tag_target.dart' as _i24;
import 'package:doable/src/tag/presentation/catalog/tag_catalog_page.dart'
    as _i13;
import 'package:doable/src/tag/presentation/editor/tag_editor_page.dart'
    as _i14;
import 'package:doable/src/tag/presentation/editor/tag_editor_state.dart'
    as _i25;
import 'package:doable/src/tag/presentation/navigation/tag_navigation_page.dart'
    as _i15;
import 'package:flutter/material.dart' as _i18;

/// generated route for
/// [_i1.ChoicePathPage]
class ChoicePathRoute extends _i16.PageRouteInfo<ChoicePathRouteArgs> {
  ChoicePathRoute({
    required _i17.IntentionId sourceIntentionId,
    _i18.Key? key,
    List<_i16.PageRouteInfo>? children,
  }) : super(
         ChoicePathRoute.name,
         args: ChoicePathRouteArgs(
           sourceIntentionId: sourceIntentionId,
           key: key,
         ),
         initialChildren: children,
       );

  static const String name = 'ChoicePathRoute';

  static _i16.PageInfo page = _i16.PageInfo(
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

  final _i17.IntentionId sourceIntentionId;

  final _i18.Key? key;

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
/// [_i2.DailyChoiceActionPickerPage]
class DailyChoiceActionPickerRoute extends _i16.PageRouteInfo<void> {
  const DailyChoiceActionPickerRoute({List<_i16.PageRouteInfo>? children})
    : super(DailyChoiceActionPickerRoute.name, initialChildren: children);

  static const String name = 'DailyChoiceActionPickerRoute';

  static _i16.PageInfo page = _i16.PageInfo(
    name,
    builder: (data) {
      return const _i2.DailyChoiceActionPickerPage();
    },
  );
}

/// generated route for
/// [_i3.DailyChoiceCatalogPage]
class DailyChoiceCatalogRoute extends _i16.PageRouteInfo<void> {
  const DailyChoiceCatalogRoute({List<_i16.PageRouteInfo>? children})
    : super(DailyChoiceCatalogRoute.name, initialChildren: children);

  static const String name = 'DailyChoiceCatalogRoute';

  static _i16.PageInfo page = _i16.PageInfo(
    name,
    builder: (data) {
      return const _i3.DailyChoiceCatalogPage();
    },
  );
}

/// generated route for
/// [_i4.DailyChoiceDetailsPage]
class DailyChoiceDetailsRoute
    extends _i16.PageRouteInfo<DailyChoiceDetailsRouteArgs> {
  DailyChoiceDetailsRoute({
    required _i19.DailyChoiceId choiceId,
    _i18.Key? key,
    List<_i16.PageRouteInfo>? children,
  }) : super(
         DailyChoiceDetailsRoute.name,
         args: DailyChoiceDetailsRouteArgs(choiceId: choiceId, key: key),
         initialChildren: children,
       );

  static const String name = 'DailyChoiceDetailsRoute';

  static _i16.PageInfo page = _i16.PageInfo(
    name,
    builder: (data) {
      final args = data.argsAs<DailyChoiceDetailsRouteArgs>();
      return _i4.DailyChoiceDetailsPage(choiceId: args.choiceId, key: args.key);
    },
  );
}

class DailyChoiceDetailsRouteArgs {
  const DailyChoiceDetailsRouteArgs({required this.choiceId, this.key});

  final _i19.DailyChoiceId choiceId;

  final _i18.Key? key;

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
/// [_i5.DailyChoiceEditPage]
class DailyChoiceEditRoute
    extends _i16.PageRouteInfo<DailyChoiceEditRouteArgs> {
  DailyChoiceEditRoute({
    required _i20.DailyChoiceDetails details,
    _i18.Key? key,
    List<_i16.PageRouteInfo>? children,
  }) : super(
         DailyChoiceEditRoute.name,
         args: DailyChoiceEditRouteArgs(details: details, key: key),
         initialChildren: children,
       );

  static const String name = 'DailyChoiceEditRoute';

  static _i16.PageInfo page = _i16.PageInfo(
    name,
    builder: (data) {
      final args = data.argsAs<DailyChoiceEditRouteArgs>();
      return _i5.DailyChoiceEditPage(details: args.details, key: args.key);
    },
  );
}

class DailyChoiceEditRouteArgs {
  const DailyChoiceEditRouteArgs({required this.details, this.key});

  final _i20.DailyChoiceDetails details;

  final _i18.Key? key;

  @override
  String toString() {
    return 'DailyChoiceEditRouteArgs{details: $details, key: $key}';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! DailyChoiceEditRouteArgs) return false;
    return details == other.details && key == other.key;
  }

  @override
  int get hashCode => details.hashCode ^ key.hashCode;
}

/// generated route for
/// [_i6.DailyChoiceSourcePickerPage]
class DailyChoiceSourcePickerRoute extends _i16.PageRouteInfo<void> {
  const DailyChoiceSourcePickerRoute({List<_i16.PageRouteInfo>? children})
    : super(DailyChoiceSourcePickerRoute.name, initialChildren: children);

  static const String name = 'DailyChoiceSourcePickerRoute';

  static _i16.PageInfo page = _i16.PageInfo(
    name,
    builder: (data) {
      return const _i6.DailyChoiceSourcePickerPage();
    },
  );
}

/// generated route for
/// [_i7.IntentionCatalogPage]
class IntentionCatalogRoute extends _i16.PageRouteInfo<void> {
  const IntentionCatalogRoute({List<_i16.PageRouteInfo>? children})
    : super(IntentionCatalogRoute.name, initialChildren: children);

  static const String name = 'IntentionCatalogRoute';

  static _i16.PageInfo page = _i16.PageInfo(
    name,
    builder: (data) {
      return const _i7.IntentionCatalogPage();
    },
  );
}

/// generated route for
/// [_i8.IntentionDetailsPage]
class IntentionDetailsRoute
    extends _i16.PageRouteInfo<IntentionDetailsRouteArgs> {
  IntentionDetailsRoute({
    required _i17.IntentionId intentionId,
    _i18.Key? key,
    List<_i16.PageRouteInfo>? children,
  }) : super(
         IntentionDetailsRoute.name,
         args: IntentionDetailsRouteArgs(intentionId: intentionId, key: key),
         initialChildren: children,
       );

  static const String name = 'IntentionDetailsRoute';

  static _i16.PageInfo page = _i16.PageInfo(
    name,
    builder: (data) {
      final args = data.argsAs<IntentionDetailsRouteArgs>();
      return _i8.IntentionDetailsPage(
        intentionId: args.intentionId,
        key: args.key,
      );
    },
  );
}

class IntentionDetailsRouteArgs {
  const IntentionDetailsRouteArgs({required this.intentionId, this.key});

  final _i17.IntentionId intentionId;

  final _i18.Key? key;

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
/// [_i9.IntentionEditorPage]
class IntentionEditorRoute extends _i16.PageRouteInfo<void> {
  const IntentionEditorRoute({List<_i16.PageRouteInfo>? children})
    : super(IntentionEditorRoute.name, initialChildren: children);

  static const String name = 'IntentionEditorRoute';

  static _i16.PageInfo page = _i16.PageInfo(
    name,
    builder: (data) {
      return const _i9.IntentionEditorPage();
    },
  );
}

/// generated route for
/// [_i10.RelationDetailsPage]
class RelationDetailsRoute
    extends _i16.PageRouteInfo<RelationDetailsRouteArgs> {
  RelationDetailsRoute({
    required _i21.LongTermRelationId relationId,
    _i18.Key? key,
    List<_i16.PageRouteInfo>? children,
  }) : super(
         RelationDetailsRoute.name,
         args: RelationDetailsRouteArgs(relationId: relationId, key: key),
         initialChildren: children,
       );

  static const String name = 'RelationDetailsRoute';

  static _i16.PageInfo page = _i16.PageInfo(
    name,
    builder: (data) {
      final args = data.argsAs<RelationDetailsRouteArgs>();
      return _i10.RelationDetailsPage(
        relationId: args.relationId,
        key: args.key,
      );
    },
  );
}

class RelationDetailsRouteArgs {
  const RelationDetailsRouteArgs({required this.relationId, this.key});

  final _i21.LongTermRelationId relationId;

  final _i18.Key? key;

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
/// [_i11.RelationEditorPage]
class RelationEditorRoute extends _i16.PageRouteInfo<RelationEditorRouteArgs> {
  RelationEditorRoute({
    required _i22.RelationEditorContext editorContext,
    _i18.Key? key,
    List<_i16.PageRouteInfo>? children,
  }) : super(
         RelationEditorRoute.name,
         args: RelationEditorRouteArgs(editorContext: editorContext, key: key),
         initialChildren: children,
       );

  static const String name = 'RelationEditorRoute';

  static _i16.PageInfo page = _i16.PageInfo(
    name,
    builder: (data) {
      final args = data.argsAs<RelationEditorRouteArgs>();
      return _i11.RelationEditorPage(
        editorContext: args.editorContext,
        key: args.key,
      );
    },
  );
}

class RelationEditorRouteArgs {
  const RelationEditorRouteArgs({required this.editorContext, this.key});

  final _i22.RelationEditorContext editorContext;

  final _i18.Key? key;

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
/// [_i12.RelationParticipantPickerPage]
class RelationParticipantPickerRoute
    extends _i16.PageRouteInfo<RelationParticipantPickerRouteArgs> {
  RelationParticipantPickerRoute({
    required _i17.IntentionId excludedIntentionId,
    required _i23.RelationParticipantSelectionContext selectionContext,
    _i18.Key? key,
    List<_i16.PageRouteInfo>? children,
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

  static _i16.PageInfo page = _i16.PageInfo(
    name,
    builder: (data) {
      final args = data.argsAs<RelationParticipantPickerRouteArgs>();
      return _i12.RelationParticipantPickerPage(
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

  final _i17.IntentionId excludedIntentionId;

  final _i23.RelationParticipantSelectionContext selectionContext;

  final _i18.Key? key;

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

/// generated route for
/// [_i13.TagCatalogPage]
class TagCatalogRoute extends _i16.PageRouteInfo<TagCatalogRouteArgs> {
  TagCatalogRoute({
    _i24.TagTarget? target,
    _i18.Key? key,
    List<_i16.PageRouteInfo>? children,
  }) : super(
         TagCatalogRoute.name,
         args: TagCatalogRouteArgs(target: target, key: key),
         initialChildren: children,
       );

  static const String name = 'TagCatalogRoute';

  static _i16.PageInfo page = _i16.PageInfo(
    name,
    builder: (data) {
      final args = data.argsAs<TagCatalogRouteArgs>(
        orElse: () => const TagCatalogRouteArgs(),
      );
      return _i13.TagCatalogPage(target: args.target, key: args.key);
    },
  );
}

class TagCatalogRouteArgs {
  const TagCatalogRouteArgs({this.target, this.key});

  final _i24.TagTarget? target;

  final _i18.Key? key;

  @override
  String toString() {
    return 'TagCatalogRouteArgs{target: $target, key: $key}';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! TagCatalogRouteArgs) return false;
    return target == other.target && key == other.key;
  }

  @override
  int get hashCode => target.hashCode ^ key.hashCode;
}

/// generated route for
/// [_i14.TagEditorPage]
class TagEditorRoute extends _i16.PageRouteInfo<TagEditorRouteArgs> {
  TagEditorRoute({
    required _i25.TagEditorContext editorContext,
    _i18.Key? key,
    List<_i16.PageRouteInfo>? children,
  }) : super(
         TagEditorRoute.name,
         args: TagEditorRouteArgs(editorContext: editorContext, key: key),
         initialChildren: children,
       );

  static const String name = 'TagEditorRoute';

  static _i16.PageInfo page = _i16.PageInfo(
    name,
    builder: (data) {
      final args = data.argsAs<TagEditorRouteArgs>();
      return _i14.TagEditorPage(
        editorContext: args.editorContext,
        key: args.key,
      );
    },
  );
}

class TagEditorRouteArgs {
  const TagEditorRouteArgs({required this.editorContext, this.key});

  final _i25.TagEditorContext editorContext;

  final _i18.Key? key;

  @override
  String toString() {
    return 'TagEditorRouteArgs{editorContext: $editorContext, key: $key}';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! TagEditorRouteArgs) return false;
    return editorContext == other.editorContext && key == other.key;
  }

  @override
  int get hashCode => editorContext.hashCode ^ key.hashCode;
}

/// generated route for
/// [_i15.TagNavigationPage]
class TagNavigationRoute extends _i16.PageRouteInfo<TagNavigationRouteArgs> {
  TagNavigationRoute({
    required _i26.TagId tagId,
    _i18.Key? key,
    List<_i16.PageRouteInfo>? children,
  }) : super(
         TagNavigationRoute.name,
         args: TagNavigationRouteArgs(tagId: tagId, key: key),
         initialChildren: children,
       );

  static const String name = 'TagNavigationRoute';

  static _i16.PageInfo page = _i16.PageInfo(
    name,
    builder: (data) {
      final args = data.argsAs<TagNavigationRouteArgs>();
      return _i16.WrappedRoute(
        child: _i15.TagNavigationPage(tagId: args.tagId, key: args.key),
      );
    },
  );
}

class TagNavigationRouteArgs {
  const TagNavigationRouteArgs({required this.tagId, this.key});

  final _i26.TagId tagId;

  final _i18.Key? key;

  @override
  String toString() {
    return 'TagNavigationRouteArgs{tagId: $tagId, key: $key}';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! TagNavigationRouteArgs) return false;
    return tagId == other.tagId && key == other.key;
  }

  @override
  int get hashCode => tagId.hashCode ^ key.hashCode;
}
