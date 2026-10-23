// dart format width=80
// GENERATED CODE - DO NOT MODIFY BY HAND

// **************************************************************************
// AutoRouterGenerator
// **************************************************************************

// ignore_for_file: type=lint
// coverage:ignore-file

// ignore_for_file: no_leading_underscores_for_library_prefixes

import 'package:auto_route/auto_route.dart' as _i23;
import 'package:collection/collection.dart' as _i30;
import 'package:doable/src/app/home/home_page.dart' as _i11;
import 'package:doable/src/app/navigation/app_shell_page.dart' as _i1;
import 'package:doable/src/app/settings/settings_page.dart' as _i18;
import 'package:doable/src/daily_choice/application/choice_path_draft.dart'
    as _i25;
import 'package:doable/src/daily_choice/application/confirmed_choice_path.dart'
    as _i28;
import 'package:doable/src/daily_choice/application/daily_choice_details.dart'
    as _i32;
import 'package:doable/src/daily_choice/domain/calendar_date.dart' as _i29;
import 'package:doable/src/daily_choice/domain/daily_choice_id.dart' as _i31;
import 'package:doable/src/daily_choice/presentation/action_picker/daily_choice_action_picker_page.dart'
    as _i3;
import 'package:doable/src/daily_choice/presentation/catalog/daily_choice_catalog_page.dart'
    as _i5;
import 'package:doable/src/daily_choice/presentation/catalog/daily_choice_date_catalog_page.dart'
    as _i7;
import 'package:doable/src/daily_choice/presentation/daily_choice_creation_flow_session.dart'
    as _i27;
import 'package:doable/src/daily_choice/presentation/daily_choice_picker_context.dart'
    as _i4;
import 'package:doable/src/daily_choice/presentation/details/daily_choice_details_page.dart'
    as _i8;
import 'package:doable/src/daily_choice/presentation/editor/daily_choice_creation_page.dart'
    as _i6;
import 'package:doable/src/daily_choice/presentation/editor/daily_choice_edit_page.dart'
    as _i9;
import 'package:doable/src/daily_choice/presentation/path/choice_path_page.dart'
    as _i2;
import 'package:doable/src/daily_choice/presentation/source_picker/daily_choice_source_picker_page.dart'
    as _i10;
import 'package:doable/src/intention/domain/intention_id.dart' as _i24;
import 'package:doable/src/intention/presentation/catalog/intention_catalog_page.dart'
    as _i12;
import 'package:doable/src/intention/presentation/catalog/intention_catalog_purpose.dart'
    as _i36;
import 'package:doable/src/intention/presentation/details/intention_details_page.dart'
    as _i13;
import 'package:doable/src/intention/presentation/editor/intention_editor_page.dart'
    as _i14;
import 'package:doable/src/long_term_relation/domain/long_term_relation_id.dart'
    as _i34;
import 'package:doable/src/long_term_relation/presentation/details/relation_details_page.dart'
    as _i15;
import 'package:doable/src/long_term_relation/presentation/editor/relation_editor_page.dart'
    as _i16;
import 'package:doable/src/long_term_relation/presentation/editor/relation_editor_state.dart'
    as _i35;
import 'package:doable/src/long_term_relation/presentation/participant_picker/relation_participant_picker_page.dart'
    as _i17;
import 'package:doable/src/statistics/application/intention_statistics_target.dart'
    as _i33;
import 'package:doable/src/tag/domain/tag_id.dart' as _i38;
import 'package:doable/src/tag/presentation/catalog/tag_catalog_page.dart'
    as _i19;
import 'package:doable/src/tag/presentation/catalog/tag_selection_context.dart'
    as _i20;
import 'package:doable/src/tag/presentation/editor/tag_editor_page.dart'
    as _i21;
import 'package:doable/src/tag/presentation/editor/tag_editor_state.dart'
    as _i37;
import 'package:doable/src/tag/presentation/navigation/tag_navigation_page.dart'
    as _i22;
import 'package:flutter/material.dart' as _i26;

/// generated route for
/// [_i1.AppShellPage]
class AppShellRoute extends _i23.PageRouteInfo<void> {
  const AppShellRoute({List<_i23.PageRouteInfo>? children})
    : super(AppShellRoute.name, initialChildren: children);

  static const String name = 'AppShellRoute';

  static _i23.PageInfo page = _i23.PageInfo(
    name,
    builder: (data) {
      return const _i1.AppShellPage();
    },
  );
}

/// generated route for
/// [_i2.ChoicePathPage]
class ChoicePathRoute extends _i23.PageRouteInfo<ChoicePathRouteArgs> {
  ChoicePathRoute({
    required _i24.IntentionId sourceIntentionId,
    required _i25.ChoicePathDraftDirection direction,
    _i26.Key? key,
    List<_i23.PageRouteInfo>? children,
  }) : super(
         ChoicePathRoute.name,
         args: ChoicePathRouteArgs(
           sourceIntentionId: sourceIntentionId,
           direction: direction,
           key: key,
         ),
         initialChildren: children,
       );

  static const String name = 'ChoicePathRoute';

  static _i23.PageInfo page = _i23.PageInfo(
    name,
    builder: (data) {
      final args = data.argsAs<ChoicePathRouteArgs>();
      return _i2.ChoicePathPage(
        sourceIntentionId: args.sourceIntentionId,
        direction: args.direction,
        key: args.key,
      );
    },
  );
}

class ChoicePathRouteArgs {
  const ChoicePathRouteArgs({
    required this.sourceIntentionId,
    required this.direction,
    this.key,
  });

  final _i24.IntentionId sourceIntentionId;

  final _i25.ChoicePathDraftDirection direction;

  final _i26.Key? key;

  @override
  String toString() {
    return 'ChoicePathRouteArgs{sourceIntentionId: $sourceIntentionId, direction: $direction, key: $key}';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! ChoicePathRouteArgs) return false;
    return sourceIntentionId == other.sourceIntentionId &&
        direction == other.direction &&
        key == other.key;
  }

  @override
  int get hashCode =>
      sourceIntentionId.hashCode ^ direction.hashCode ^ key.hashCode;
}

/// generated route for
/// [_i3.DailyChoiceActionPickerPage]
class DailyChoiceActionPickerRoute
    extends _i23.PageRouteInfo<DailyChoiceActionPickerRouteArgs> {
  DailyChoiceActionPickerRoute({
    _i4.DailyChoicePickerContext pickerContext =
        const _i4.AuxiliaryDailyChoicePickerContext(),
    _i26.Key? key,
    List<_i23.PageRouteInfo>? children,
  }) : super(
         DailyChoiceActionPickerRoute.name,
         args: DailyChoiceActionPickerRouteArgs(
           pickerContext: pickerContext,
           key: key,
         ),
         initialChildren: children,
       );

  static const String name = 'DailyChoiceActionPickerRoute';

  static _i23.PageInfo page = _i23.PageInfo(
    name,
    builder: (data) {
      final args = data.argsAs<DailyChoiceActionPickerRouteArgs>(
        orElse: () => const DailyChoiceActionPickerRouteArgs(),
      );
      return _i3.DailyChoiceActionPickerPage(
        pickerContext: args.pickerContext,
        key: args.key,
      );
    },
  );
}

class DailyChoiceActionPickerRouteArgs {
  const DailyChoiceActionPickerRouteArgs({
    this.pickerContext = const _i4.AuxiliaryDailyChoicePickerContext(),
    this.key,
  });

  final _i4.DailyChoicePickerContext pickerContext;

  final _i26.Key? key;

  @override
  String toString() {
    return 'DailyChoiceActionPickerRouteArgs{pickerContext: $pickerContext, key: $key}';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! DailyChoiceActionPickerRouteArgs) return false;
    return pickerContext == other.pickerContext && key == other.key;
  }

  @override
  int get hashCode => pickerContext.hashCode ^ key.hashCode;
}

/// generated route for
/// [_i5.DailyChoiceCatalogPage]
class DailyChoiceCatalogRoute extends _i23.PageRouteInfo<void> {
  const DailyChoiceCatalogRoute({List<_i23.PageRouteInfo>? children})
    : super(DailyChoiceCatalogRoute.name, initialChildren: children);

  static const String name = 'DailyChoiceCatalogRoute';

  static _i23.PageInfo page = _i23.PageInfo(
    name,
    builder: (data) {
      return const _i5.DailyChoiceCatalogPage();
    },
  );
}

/// generated route for
/// [_i6.DailyChoiceCreationPage]
class DailyChoiceCreationRoute
    extends _i23.PageRouteInfo<DailyChoiceCreationRouteArgs> {
  DailyChoiceCreationRoute({
    required _i27.DailyChoiceCreationFlowSession session,
    required _i28.ConfirmedChoicePath path,
    required List<_i6.DailyChoiceCreationStep> steps,
    required _i29.CalendarDate initialDate,
    _i25.ChoicePathDraftDirection direction =
        _i25.ChoicePathDraftDirection.topDown,
    _i26.Key? key,
    List<_i23.PageRouteInfo>? children,
  }) : super(
         DailyChoiceCreationRoute.name,
         args: DailyChoiceCreationRouteArgs(
           session: session,
           path: path,
           steps: steps,
           initialDate: initialDate,
           direction: direction,
           key: key,
         ),
         initialChildren: children,
       );

  static const String name = 'DailyChoiceCreationRoute';

  static _i23.PageInfo page = _i23.PageInfo(
    name,
    builder: (data) {
      final args = data.argsAs<DailyChoiceCreationRouteArgs>();
      return _i6.DailyChoiceCreationPage(
        session: args.session,
        path: args.path,
        steps: args.steps,
        initialDate: args.initialDate,
        direction: args.direction,
        key: args.key,
      );
    },
  );
}

class DailyChoiceCreationRouteArgs {
  const DailyChoiceCreationRouteArgs({
    required this.session,
    required this.path,
    required this.steps,
    required this.initialDate,
    this.direction = _i25.ChoicePathDraftDirection.topDown,
    this.key,
  });

  final _i27.DailyChoiceCreationFlowSession session;

  final _i28.ConfirmedChoicePath path;

  final List<_i6.DailyChoiceCreationStep> steps;

  final _i29.CalendarDate initialDate;

  final _i25.ChoicePathDraftDirection direction;

  final _i26.Key? key;

  @override
  String toString() {
    return 'DailyChoiceCreationRouteArgs{session: $session, path: $path, steps: $steps, initialDate: $initialDate, direction: $direction, key: $key}';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! DailyChoiceCreationRouteArgs) return false;
    return session == other.session &&
        path == other.path &&
        const _i30.ListEquality<_i6.DailyChoiceCreationStep>().equals(
          steps,
          other.steps,
        ) &&
        initialDate == other.initialDate &&
        direction == other.direction &&
        key == other.key;
  }

  @override
  int get hashCode =>
      session.hashCode ^
      path.hashCode ^
      const _i30.ListEquality<_i6.DailyChoiceCreationStep>().hash(steps) ^
      initialDate.hashCode ^
      direction.hashCode ^
      key.hashCode;
}

/// generated route for
/// [_i7.DailyChoiceDateCatalogPage]
class DailyChoiceDateCatalogRoute
    extends _i23.PageRouteInfo<DailyChoiceDateCatalogRouteArgs> {
  DailyChoiceDateCatalogRoute({
    required _i29.CalendarDate date,
    _i26.Key? key,
    List<_i23.PageRouteInfo>? children,
  }) : super(
         DailyChoiceDateCatalogRoute.name,
         args: DailyChoiceDateCatalogRouteArgs(date: date, key: key),
         initialChildren: children,
       );

  static const String name = 'DailyChoiceDateCatalogRoute';

  static _i23.PageInfo page = _i23.PageInfo(
    name,
    builder: (data) {
      final args = data.argsAs<DailyChoiceDateCatalogRouteArgs>();
      return _i7.DailyChoiceDateCatalogPage(date: args.date, key: args.key);
    },
  );
}

class DailyChoiceDateCatalogRouteArgs {
  const DailyChoiceDateCatalogRouteArgs({required this.date, this.key});

  final _i29.CalendarDate date;

  final _i26.Key? key;

  @override
  String toString() {
    return 'DailyChoiceDateCatalogRouteArgs{date: $date, key: $key}';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! DailyChoiceDateCatalogRouteArgs) return false;
    return date == other.date && key == other.key;
  }

  @override
  int get hashCode => date.hashCode ^ key.hashCode;
}

/// generated route for
/// [_i8.DailyChoiceDetailsPage]
class DailyChoiceDetailsRoute
    extends _i23.PageRouteInfo<DailyChoiceDetailsRouteArgs> {
  DailyChoiceDetailsRoute({
    required _i31.DailyChoiceId choiceId,
    _i26.Key? key,
    List<_i23.PageRouteInfo>? children,
  }) : super(
         DailyChoiceDetailsRoute.name,
         args: DailyChoiceDetailsRouteArgs(choiceId: choiceId, key: key),
         initialChildren: children,
       );

  static const String name = 'DailyChoiceDetailsRoute';

  static _i23.PageInfo page = _i23.PageInfo(
    name,
    builder: (data) {
      final args = data.argsAs<DailyChoiceDetailsRouteArgs>();
      return _i8.DailyChoiceDetailsPage(choiceId: args.choiceId, key: args.key);
    },
  );
}

class DailyChoiceDetailsRouteArgs {
  const DailyChoiceDetailsRouteArgs({required this.choiceId, this.key});

  final _i31.DailyChoiceId choiceId;

  final _i26.Key? key;

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
/// [_i9.DailyChoiceEditPage]
class DailyChoiceEditRoute
    extends _i23.PageRouteInfo<DailyChoiceEditRouteArgs> {
  DailyChoiceEditRoute({
    required _i32.DailyChoiceDetails details,
    _i26.Key? key,
    List<_i23.PageRouteInfo>? children,
  }) : super(
         DailyChoiceEditRoute.name,
         args: DailyChoiceEditRouteArgs(details: details, key: key),
         initialChildren: children,
       );

  static const String name = 'DailyChoiceEditRoute';

  static _i23.PageInfo page = _i23.PageInfo(
    name,
    builder: (data) {
      final args = data.argsAs<DailyChoiceEditRouteArgs>();
      return _i9.DailyChoiceEditPage(details: args.details, key: args.key);
    },
  );
}

class DailyChoiceEditRouteArgs {
  const DailyChoiceEditRouteArgs({required this.details, this.key});

  final _i32.DailyChoiceDetails details;

  final _i26.Key? key;

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
/// [_i10.DailyChoiceSourcePickerPage]
class DailyChoiceSourcePickerRoute
    extends _i23.PageRouteInfo<DailyChoiceSourcePickerRouteArgs> {
  DailyChoiceSourcePickerRoute({
    _i4.DailyChoicePickerContext pickerContext =
        const _i4.AuxiliaryDailyChoicePickerContext(),
    _i26.Key? key,
    List<_i23.PageRouteInfo>? children,
  }) : super(
         DailyChoiceSourcePickerRoute.name,
         args: DailyChoiceSourcePickerRouteArgs(
           pickerContext: pickerContext,
           key: key,
         ),
         initialChildren: children,
       );

  static const String name = 'DailyChoiceSourcePickerRoute';

  static _i23.PageInfo page = _i23.PageInfo(
    name,
    builder: (data) {
      final args = data.argsAs<DailyChoiceSourcePickerRouteArgs>(
        orElse: () => const DailyChoiceSourcePickerRouteArgs(),
      );
      return _i10.DailyChoiceSourcePickerPage(
        pickerContext: args.pickerContext,
        key: args.key,
      );
    },
  );
}

class DailyChoiceSourcePickerRouteArgs {
  const DailyChoiceSourcePickerRouteArgs({
    this.pickerContext = const _i4.AuxiliaryDailyChoicePickerContext(),
    this.key,
  });

  final _i4.DailyChoicePickerContext pickerContext;

  final _i26.Key? key;

  @override
  String toString() {
    return 'DailyChoiceSourcePickerRouteArgs{pickerContext: $pickerContext, key: $key}';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! DailyChoiceSourcePickerRouteArgs) return false;
    return pickerContext == other.pickerContext && key == other.key;
  }

  @override
  int get hashCode => pickerContext.hashCode ^ key.hashCode;
}

/// generated route for
/// [_i11.HomePage]
class HomeRoute extends _i23.PageRouteInfo<void> {
  const HomeRoute({List<_i23.PageRouteInfo>? children})
    : super(HomeRoute.name, initialChildren: children);

  static const String name = 'HomeRoute';

  static _i23.PageInfo page = _i23.PageInfo(
    name,
    builder: (data) {
      return const _i11.HomePage();
    },
  );
}

/// generated route for
/// [_i12.IntentionCatalogPage]
class IntentionCatalogRoute extends _i23.PageRouteInfo<void> {
  const IntentionCatalogRoute({List<_i23.PageRouteInfo>? children})
    : super(IntentionCatalogRoute.name, initialChildren: children);

  static const String name = 'IntentionCatalogRoute';

  static _i23.PageInfo page = _i23.PageInfo(
    name,
    builder: (data) {
      return const _i12.IntentionCatalogPage();
    },
  );
}

/// generated route for
/// [_i13.IntentionDetailsPage]
class IntentionDetailsRoute
    extends _i23.PageRouteInfo<IntentionDetailsRouteArgs> {
  IntentionDetailsRoute({
    required _i24.IntentionId intentionId,
    _i33.IntentionStatisticsTarget? statisticsTarget,
    _i26.Key? key,
    List<_i23.PageRouteInfo>? children,
  }) : super(
         IntentionDetailsRoute.name,
         args: IntentionDetailsRouteArgs(
           intentionId: intentionId,
           statisticsTarget: statisticsTarget,
           key: key,
         ),
         initialChildren: children,
       );

  static const String name = 'IntentionDetailsRoute';

  static _i23.PageInfo page = _i23.PageInfo(
    name,
    builder: (data) {
      final args = data.argsAs<IntentionDetailsRouteArgs>();
      return _i13.IntentionDetailsPage(
        intentionId: args.intentionId,
        statisticsTarget: args.statisticsTarget,
        key: args.key,
      );
    },
  );
}

class IntentionDetailsRouteArgs {
  const IntentionDetailsRouteArgs({
    required this.intentionId,
    this.statisticsTarget,
    this.key,
  });

  final _i24.IntentionId intentionId;

  final _i33.IntentionStatisticsTarget? statisticsTarget;

  final _i26.Key? key;

  @override
  String toString() {
    return 'IntentionDetailsRouteArgs{intentionId: $intentionId, statisticsTarget: $statisticsTarget, key: $key}';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! IntentionDetailsRouteArgs) return false;
    return intentionId == other.intentionId &&
        statisticsTarget == other.statisticsTarget &&
        key == other.key;
  }

  @override
  int get hashCode =>
      intentionId.hashCode ^ statisticsTarget.hashCode ^ key.hashCode;
}

/// generated route for
/// [_i14.IntentionEditorPage]
class IntentionEditorRoute extends _i23.PageRouteInfo<void> {
  const IntentionEditorRoute({List<_i23.PageRouteInfo>? children})
    : super(IntentionEditorRoute.name, initialChildren: children);

  static const String name = 'IntentionEditorRoute';

  static _i23.PageInfo page = _i23.PageInfo(
    name,
    builder: (data) {
      return const _i14.IntentionEditorPage();
    },
  );
}

/// generated route for
/// [_i15.RelationDetailsPage]
class RelationDetailsRoute
    extends _i23.PageRouteInfo<RelationDetailsRouteArgs> {
  RelationDetailsRoute({
    required _i34.LongTermRelationId relationId,
    _i26.Key? key,
    List<_i23.PageRouteInfo>? children,
  }) : super(
         RelationDetailsRoute.name,
         args: RelationDetailsRouteArgs(relationId: relationId, key: key),
         initialChildren: children,
       );

  static const String name = 'RelationDetailsRoute';

  static _i23.PageInfo page = _i23.PageInfo(
    name,
    builder: (data) {
      final args = data.argsAs<RelationDetailsRouteArgs>();
      return _i15.RelationDetailsPage(
        relationId: args.relationId,
        key: args.key,
      );
    },
  );
}

class RelationDetailsRouteArgs {
  const RelationDetailsRouteArgs({required this.relationId, this.key});

  final _i34.LongTermRelationId relationId;

  final _i26.Key? key;

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
/// [_i16.RelationEditorPage]
class RelationEditorRoute extends _i23.PageRouteInfo<RelationEditorRouteArgs> {
  RelationEditorRoute({
    required _i35.RelationEditorContext editorContext,
    _i26.Key? key,
    List<_i23.PageRouteInfo>? children,
  }) : super(
         RelationEditorRoute.name,
         args: RelationEditorRouteArgs(editorContext: editorContext, key: key),
         initialChildren: children,
       );

  static const String name = 'RelationEditorRoute';

  static _i23.PageInfo page = _i23.PageInfo(
    name,
    builder: (data) {
      final args = data.argsAs<RelationEditorRouteArgs>();
      return _i16.RelationEditorPage(
        editorContext: args.editorContext,
        key: args.key,
      );
    },
  );
}

class RelationEditorRouteArgs {
  const RelationEditorRouteArgs({required this.editorContext, this.key});

  final _i35.RelationEditorContext editorContext;

  final _i26.Key? key;

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
/// [_i17.RelationParticipantPickerPage]
class RelationParticipantPickerRoute
    extends _i23.PageRouteInfo<RelationParticipantPickerRouteArgs> {
  RelationParticipantPickerRoute({
    required _i36.RelationParticipantSelectionContext selectionContext,
    _i24.IntentionId? excludedIntentionId,
    _i26.Key? key,
    List<_i23.PageRouteInfo>? children,
  }) : super(
         RelationParticipantPickerRoute.name,
         args: RelationParticipantPickerRouteArgs(
           selectionContext: selectionContext,
           excludedIntentionId: excludedIntentionId,
           key: key,
         ),
         initialChildren: children,
       );

  static const String name = 'RelationParticipantPickerRoute';

  static _i23.PageInfo page = _i23.PageInfo(
    name,
    builder: (data) {
      final args = data.argsAs<RelationParticipantPickerRouteArgs>();
      return _i17.RelationParticipantPickerPage(
        selectionContext: args.selectionContext,
        excludedIntentionId: args.excludedIntentionId,
        key: args.key,
      );
    },
  );
}

class RelationParticipantPickerRouteArgs {
  const RelationParticipantPickerRouteArgs({
    required this.selectionContext,
    this.excludedIntentionId,
    this.key,
  });

  final _i36.RelationParticipantSelectionContext selectionContext;

  final _i24.IntentionId? excludedIntentionId;

  final _i26.Key? key;

  @override
  String toString() {
    return 'RelationParticipantPickerRouteArgs{selectionContext: $selectionContext, excludedIntentionId: $excludedIntentionId, key: $key}';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! RelationParticipantPickerRouteArgs) return false;
    return selectionContext == other.selectionContext &&
        excludedIntentionId == other.excludedIntentionId &&
        key == other.key;
  }

  @override
  int get hashCode =>
      selectionContext.hashCode ^ excludedIntentionId.hashCode ^ key.hashCode;
}

/// generated route for
/// [_i18.SettingsPage]
class SettingsRoute extends _i23.PageRouteInfo<void> {
  const SettingsRoute({List<_i23.PageRouteInfo>? children})
    : super(SettingsRoute.name, initialChildren: children);

  static const String name = 'SettingsRoute';

  static _i23.PageInfo page = _i23.PageInfo(
    name,
    builder: (data) {
      return const _i18.SettingsPage();
    },
  );
}

/// generated route for
/// [_i19.TagCatalogPage]
class TagCatalogRoute extends _i23.PageRouteInfo<TagCatalogRouteArgs> {
  TagCatalogRoute({
    _i20.TagSelectionContext selectionContext = const _i20.TagBrowseContext(),
    _i26.Key? key,
    List<_i23.PageRouteInfo>? children,
  }) : super(
         TagCatalogRoute.name,
         args: TagCatalogRouteArgs(
           selectionContext: selectionContext,
           key: key,
         ),
         initialChildren: children,
       );

  static const String name = 'TagCatalogRoute';

  static _i23.PageInfo page = _i23.PageInfo(
    name,
    builder: (data) {
      final args = data.argsAs<TagCatalogRouteArgs>(
        orElse: () => const TagCatalogRouteArgs(),
      );
      return _i19.TagCatalogPage(
        selectionContext: args.selectionContext,
        key: args.key,
      );
    },
  );
}

class TagCatalogRouteArgs {
  const TagCatalogRouteArgs({
    this.selectionContext = const _i20.TagBrowseContext(),
    this.key,
  });

  final _i20.TagSelectionContext selectionContext;

  final _i26.Key? key;

  @override
  String toString() {
    return 'TagCatalogRouteArgs{selectionContext: $selectionContext, key: $key}';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! TagCatalogRouteArgs) return false;
    return selectionContext == other.selectionContext && key == other.key;
  }

  @override
  int get hashCode => selectionContext.hashCode ^ key.hashCode;
}

/// generated route for
/// [_i21.TagEditorPage]
class TagEditorRoute extends _i23.PageRouteInfo<TagEditorRouteArgs> {
  TagEditorRoute({
    required _i37.TagEditorContext editorContext,
    _i26.Key? key,
    List<_i23.PageRouteInfo>? children,
  }) : super(
         TagEditorRoute.name,
         args: TagEditorRouteArgs(editorContext: editorContext, key: key),
         initialChildren: children,
       );

  static const String name = 'TagEditorRoute';

  static _i23.PageInfo page = _i23.PageInfo(
    name,
    builder: (data) {
      final args = data.argsAs<TagEditorRouteArgs>();
      return _i21.TagEditorPage(
        editorContext: args.editorContext,
        key: args.key,
      );
    },
  );
}

class TagEditorRouteArgs {
  const TagEditorRouteArgs({required this.editorContext, this.key});

  final _i37.TagEditorContext editorContext;

  final _i26.Key? key;

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
/// [_i22.TagNavigationPage]
class TagNavigationRoute extends _i23.PageRouteInfo<TagNavigationRouteArgs> {
  TagNavigationRoute({
    required _i38.TagId tagId,
    _i26.Key? key,
    List<_i23.PageRouteInfo>? children,
  }) : super(
         TagNavigationRoute.name,
         args: TagNavigationRouteArgs(tagId: tagId, key: key),
         initialChildren: children,
       );

  static const String name = 'TagNavigationRoute';

  static _i23.PageInfo page = _i23.PageInfo(
    name,
    builder: (data) {
      final args = data.argsAs<TagNavigationRouteArgs>();
      return _i23.WrappedRoute(
        child: _i22.TagNavigationPage(tagId: args.tagId, key: args.key),
      );
    },
  );
}

class TagNavigationRouteArgs {
  const TagNavigationRouteArgs({required this.tagId, this.key});

  final _i38.TagId tagId;

  final _i26.Key? key;

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
