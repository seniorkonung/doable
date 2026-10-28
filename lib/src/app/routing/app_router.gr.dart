// dart format width=80
// GENERATED CODE - DO NOT MODIFY BY HAND

// **************************************************************************
// AutoRouterGenerator
// **************************************************************************

// ignore_for_file: type=lint
// coverage:ignore-file

// ignore_for_file: no_leading_underscores_for_library_prefixes

import 'package:auto_route/auto_route.dart' as _i20;
import 'package:collection/collection.dart' as _i29;
import 'package:doable/src/app/home/home_page.dart' as _i10;
import 'package:doable/src/app/navigation/app_shell_page.dart' as _i1;
import 'package:doable/src/app/settings/settings_page.dart' as _i19;
import 'package:doable/src/daily_choice/application/choice_path_draft.dart'
    as _i22;
import 'package:doable/src/daily_choice/application/confirmed_choice_path.dart'
    as _i27;
import 'package:doable/src/daily_choice/application/daily_choice_details.dart'
    as _i31;
import 'package:doable/src/daily_choice/domain/calendar_date.dart' as _i28;
import 'package:doable/src/daily_choice/domain/daily_choice_id.dart' as _i30;
import 'package:doable/src/daily_choice/presentation/action_picker/daily_choice_action_picker_page.dart'
    as _i3;
import 'package:doable/src/daily_choice/presentation/catalog/daily_choice_catalog_page.dart'
    as _i4;
import 'package:doable/src/daily_choice/presentation/catalog/daily_choice_date_catalog_page.dart'
    as _i6;
import 'package:doable/src/daily_choice/presentation/daily_choice_creation_flow_session.dart'
    as _i26;
import 'package:doable/src/daily_choice/presentation/daily_choice_picker_context.dart'
    as _i24;
import 'package:doable/src/daily_choice/presentation/details/daily_choice_details_page.dart'
    as _i7;
import 'package:doable/src/daily_choice/presentation/editor/daily_choice_creation_page.dart'
    as _i5;
import 'package:doable/src/daily_choice/presentation/editor/daily_choice_edit_page.dart'
    as _i8;
import 'package:doable/src/daily_choice/presentation/path/choice_path_page.dart'
    as _i2;
import 'package:doable/src/daily_choice/presentation/source_picker/daily_choice_source_picker_page.dart'
    as _i9;
import 'package:doable/src/intention/domain/intention_id.dart' as _i21;
import 'package:doable/src/intention/presentation/catalog/intention_catalog_page.dart'
    as _i11;
import 'package:doable/src/intention/presentation/details/intention_details_page.dart'
    as _i12;
import 'package:doable/src/intention/presentation/details/intention_page_target.dart'
    as _i13;
import 'package:doable/src/intention/presentation/edit/intention_edit_page.dart'
    as _i14;
import 'package:doable/src/intention/presentation/editor/intention_editor_page.dart'
    as _i15;
import 'package:doable/src/long_term_relation/domain/long_term_relation_id.dart'
    as _i33;
import 'package:doable/src/long_term_relation/presentation/details/relation_details_page.dart'
    as _i16;
import 'package:doable/src/long_term_relation/presentation/editor/relation_editor_page.dart'
    as _i17;
import 'package:doable/src/long_term_relation/presentation/editor/relation_editor_state.dart'
    as _i34;
import 'package:doable/src/long_term_relation/presentation/participant_picker/relation_participant_choice.dart'
    as _i35;
import 'package:doable/src/long_term_relation/presentation/participant_picker/relation_participant_picker_page.dart'
    as _i18;
import 'package:flutter/foundation.dart' as _i32;
import 'package:flutter/material.dart' as _i23;
import 'package:flutter/widgets.dart' as _i25;

/// generated route for
/// [_i1.AppShellPage]
class AppShellRoute extends _i20.PageRouteInfo<void> {
  const AppShellRoute({List<_i20.PageRouteInfo>? children})
    : super(AppShellRoute.name, initialChildren: children);

  static const String name = 'AppShellRoute';

  static _i20.PageInfo page = _i20.PageInfo(
    name,
    builder: (data) {
      return const _i1.AppShellPage();
    },
  );
}

/// generated route for
/// [_i2.ChoicePathPage]
class ChoicePathRoute extends _i20.PageRouteInfo<ChoicePathRouteArgs> {
  ChoicePathRoute({
    required _i21.IntentionId sourceIntentionId,
    required _i22.ChoicePathDraftDirection direction,
    _i23.Key? key,
    List<_i20.PageRouteInfo>? children,
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

  static _i20.PageInfo page = _i20.PageInfo(
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

  final _i21.IntentionId sourceIntentionId;

  final _i22.ChoicePathDraftDirection direction;

  final _i23.Key? key;

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
    extends _i20.PageRouteInfo<DailyChoiceActionPickerRouteArgs> {
  DailyChoiceActionPickerRoute({
    required _i24.DailyChoicePickerContext pickerContext,
    _i25.Key? key,
    List<_i20.PageRouteInfo>? children,
  }) : super(
         DailyChoiceActionPickerRoute.name,
         args: DailyChoiceActionPickerRouteArgs(
           pickerContext: pickerContext,
           key: key,
         ),
         initialChildren: children,
       );

  static const String name = 'DailyChoiceActionPickerRoute';

  static _i20.PageInfo page = _i20.PageInfo(
    name,
    builder: (data) {
      final args = data.argsAs<DailyChoiceActionPickerRouteArgs>();
      return _i3.DailyChoiceActionPickerPage(
        pickerContext: args.pickerContext,
        key: args.key,
      );
    },
  );
}

class DailyChoiceActionPickerRouteArgs {
  const DailyChoiceActionPickerRouteArgs({
    required this.pickerContext,
    this.key,
  });

  final _i24.DailyChoicePickerContext pickerContext;

  final _i25.Key? key;

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
/// [_i4.DailyChoiceCatalogPage]
class DailyChoiceCatalogRoute extends _i20.PageRouteInfo<void> {
  const DailyChoiceCatalogRoute({List<_i20.PageRouteInfo>? children})
    : super(DailyChoiceCatalogRoute.name, initialChildren: children);

  static const String name = 'DailyChoiceCatalogRoute';

  static _i20.PageInfo page = _i20.PageInfo(
    name,
    builder: (data) {
      return const _i4.DailyChoiceCatalogPage();
    },
  );
}

/// generated route for
/// [_i5.DailyChoiceCreationPage]
class DailyChoiceCreationRoute
    extends _i20.PageRouteInfo<DailyChoiceCreationRouteArgs> {
  DailyChoiceCreationRoute({
    required _i26.DailyChoiceCreationFlowSession session,
    required _i27.ConfirmedChoicePath path,
    required List<_i5.DailyChoiceCreationStep> steps,
    required _i28.CalendarDate initialDate,
    _i22.ChoicePathDraftDirection direction =
        _i22.ChoicePathDraftDirection.topDown,
    _i23.Key? key,
    List<_i20.PageRouteInfo>? children,
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

  static _i20.PageInfo page = _i20.PageInfo(
    name,
    builder: (data) {
      final args = data.argsAs<DailyChoiceCreationRouteArgs>();
      return _i5.DailyChoiceCreationPage(
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
    this.direction = _i22.ChoicePathDraftDirection.topDown,
    this.key,
  });

  final _i26.DailyChoiceCreationFlowSession session;

  final _i27.ConfirmedChoicePath path;

  final List<_i5.DailyChoiceCreationStep> steps;

  final _i28.CalendarDate initialDate;

  final _i22.ChoicePathDraftDirection direction;

  final _i23.Key? key;

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
        const _i29.ListEquality<_i5.DailyChoiceCreationStep>().equals(
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
      const _i29.ListEquality<_i5.DailyChoiceCreationStep>().hash(steps) ^
      initialDate.hashCode ^
      direction.hashCode ^
      key.hashCode;
}

/// generated route for
/// [_i6.DailyChoiceDateCatalogPage]
class DailyChoiceDateCatalogRoute
    extends _i20.PageRouteInfo<DailyChoiceDateCatalogRouteArgs> {
  DailyChoiceDateCatalogRoute({
    required _i28.CalendarDate date,
    _i23.Key? key,
    List<_i20.PageRouteInfo>? children,
  }) : super(
         DailyChoiceDateCatalogRoute.name,
         args: DailyChoiceDateCatalogRouteArgs(date: date, key: key),
         initialChildren: children,
       );

  static const String name = 'DailyChoiceDateCatalogRoute';

  static _i20.PageInfo page = _i20.PageInfo(
    name,
    builder: (data) {
      final args = data.argsAs<DailyChoiceDateCatalogRouteArgs>();
      return _i6.DailyChoiceDateCatalogPage(date: args.date, key: args.key);
    },
  );
}

class DailyChoiceDateCatalogRouteArgs {
  const DailyChoiceDateCatalogRouteArgs({required this.date, this.key});

  final _i28.CalendarDate date;

  final _i23.Key? key;

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
/// [_i7.DailyChoiceDetailsPage]
class DailyChoiceDetailsRoute
    extends _i20.PageRouteInfo<DailyChoiceDetailsRouteArgs> {
  DailyChoiceDetailsRoute({
    required _i30.DailyChoiceId choiceId,
    _i23.Key? key,
    List<_i20.PageRouteInfo>? children,
  }) : super(
         DailyChoiceDetailsRoute.name,
         args: DailyChoiceDetailsRouteArgs(choiceId: choiceId, key: key),
         initialChildren: children,
       );

  static const String name = 'DailyChoiceDetailsRoute';

  static _i20.PageInfo page = _i20.PageInfo(
    name,
    builder: (data) {
      final args = data.argsAs<DailyChoiceDetailsRouteArgs>();
      return _i7.DailyChoiceDetailsPage(choiceId: args.choiceId, key: args.key);
    },
  );
}

class DailyChoiceDetailsRouteArgs {
  const DailyChoiceDetailsRouteArgs({required this.choiceId, this.key});

  final _i30.DailyChoiceId choiceId;

  final _i23.Key? key;

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
/// [_i8.DailyChoiceEditPage]
class DailyChoiceEditRoute
    extends _i20.PageRouteInfo<DailyChoiceEditRouteArgs> {
  DailyChoiceEditRoute({
    required _i31.DailyChoiceDetails details,
    _i23.Key? key,
    List<_i20.PageRouteInfo>? children,
  }) : super(
         DailyChoiceEditRoute.name,
         args: DailyChoiceEditRouteArgs(details: details, key: key),
         initialChildren: children,
       );

  static const String name = 'DailyChoiceEditRoute';

  static _i20.PageInfo page = _i20.PageInfo(
    name,
    builder: (data) {
      final args = data.argsAs<DailyChoiceEditRouteArgs>();
      return _i8.DailyChoiceEditPage(details: args.details, key: args.key);
    },
  );
}

class DailyChoiceEditRouteArgs {
  const DailyChoiceEditRouteArgs({required this.details, this.key});

  final _i31.DailyChoiceDetails details;

  final _i23.Key? key;

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
/// [_i9.DailyChoiceSourcePickerPage]
class DailyChoiceSourcePickerRoute
    extends _i20.PageRouteInfo<DailyChoiceSourcePickerRouteArgs> {
  DailyChoiceSourcePickerRoute({
    required _i24.DailyChoicePickerContext pickerContext,
    _i25.Key? key,
    List<_i20.PageRouteInfo>? children,
  }) : super(
         DailyChoiceSourcePickerRoute.name,
         args: DailyChoiceSourcePickerRouteArgs(
           pickerContext: pickerContext,
           key: key,
         ),
         initialChildren: children,
       );

  static const String name = 'DailyChoiceSourcePickerRoute';

  static _i20.PageInfo page = _i20.PageInfo(
    name,
    builder: (data) {
      final args = data.argsAs<DailyChoiceSourcePickerRouteArgs>();
      return _i9.DailyChoiceSourcePickerPage(
        pickerContext: args.pickerContext,
        key: args.key,
      );
    },
  );
}

class DailyChoiceSourcePickerRouteArgs {
  const DailyChoiceSourcePickerRouteArgs({
    required this.pickerContext,
    this.key,
  });

  final _i24.DailyChoicePickerContext pickerContext;

  final _i25.Key? key;

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
/// [_i10.HomePage]
class HomeRoute extends _i20.PageRouteInfo<void> {
  const HomeRoute({List<_i20.PageRouteInfo>? children})
    : super(HomeRoute.name, initialChildren: children);

  static const String name = 'HomeRoute';

  static _i20.PageInfo page = _i20.PageInfo(
    name,
    builder: (data) {
      return const _i10.HomePage();
    },
  );
}

/// generated route for
/// [_i11.IntentionCatalogPage]
class IntentionCatalogRoute extends _i20.PageRouteInfo<void> {
  const IntentionCatalogRoute({List<_i20.PageRouteInfo>? children})
    : super(IntentionCatalogRoute.name, initialChildren: children);

  static const String name = 'IntentionCatalogRoute';

  static _i20.PageInfo page = _i20.PageInfo(
    name,
    builder: (data) {
      return const _i11.IntentionCatalogPage();
    },
  );
}

/// generated route for
/// [_i12.IntentionDetailsPage]
class IntentionDetailsRoute
    extends _i20.PageRouteInfo<IntentionDetailsRouteArgs> {
  IntentionDetailsRoute({
    required _i21.IntentionId intentionId,
    _i13.IntentionPageTarget target = const _i13.OverviewTarget(),
    _i32.Key? key,
    List<_i20.PageRouteInfo>? children,
  }) : super(
         IntentionDetailsRoute.name,
         args: IntentionDetailsRouteArgs(
           intentionId: intentionId,
           target: target,
           key: key,
         ),
         initialChildren: children,
       );

  static const String name = 'IntentionDetailsRoute';

  static _i20.PageInfo page = _i20.PageInfo(
    name,
    builder: (data) {
      final args = data.argsAs<IntentionDetailsRouteArgs>();
      return _i12.IntentionDetailsPage(
        intentionId: args.intentionId,
        target: args.target,
        key: args.key,
      );
    },
  );
}

class IntentionDetailsRouteArgs {
  const IntentionDetailsRouteArgs({
    required this.intentionId,
    this.target = const _i13.OverviewTarget(),
    this.key,
  });

  final _i21.IntentionId intentionId;

  final _i13.IntentionPageTarget target;

  final _i32.Key? key;

  @override
  String toString() {
    return 'IntentionDetailsRouteArgs{intentionId: $intentionId, target: $target, key: $key}';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! IntentionDetailsRouteArgs) return false;
    return intentionId == other.intentionId &&
        target == other.target &&
        key == other.key;
  }

  @override
  int get hashCode => intentionId.hashCode ^ target.hashCode ^ key.hashCode;
}

/// generated route for
/// [_i14.IntentionEditPage]
class IntentionEditRoute extends _i20.PageRouteInfo<IntentionEditRouteArgs> {
  IntentionEditRoute({
    required _i21.IntentionId intentionId,
    _i14.IntentionEditFocus focus = _i14.IntentionEditFocus.title,
    _i23.Key? key,
    List<_i20.PageRouteInfo>? children,
  }) : super(
         IntentionEditRoute.name,
         args: IntentionEditRouteArgs(
           intentionId: intentionId,
           focus: focus,
           key: key,
         ),
         initialChildren: children,
       );

  static const String name = 'IntentionEditRoute';

  static _i20.PageInfo page = _i20.PageInfo(
    name,
    builder: (data) {
      final args = data.argsAs<IntentionEditRouteArgs>();
      return _i14.IntentionEditPage(
        intentionId: args.intentionId,
        focus: args.focus,
        key: args.key,
      );
    },
  );
}

class IntentionEditRouteArgs {
  const IntentionEditRouteArgs({
    required this.intentionId,
    this.focus = _i14.IntentionEditFocus.title,
    this.key,
  });

  final _i21.IntentionId intentionId;

  final _i14.IntentionEditFocus focus;

  final _i23.Key? key;

  @override
  String toString() {
    return 'IntentionEditRouteArgs{intentionId: $intentionId, focus: $focus, key: $key}';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! IntentionEditRouteArgs) return false;
    return intentionId == other.intentionId &&
        focus == other.focus &&
        key == other.key;
  }

  @override
  int get hashCode => intentionId.hashCode ^ focus.hashCode ^ key.hashCode;
}

/// generated route for
/// [_i15.IntentionEditorPage]
class IntentionEditorRoute extends _i20.PageRouteInfo<void> {
  const IntentionEditorRoute({List<_i20.PageRouteInfo>? children})
    : super(IntentionEditorRoute.name, initialChildren: children);

  static const String name = 'IntentionEditorRoute';

  static _i20.PageInfo page = _i20.PageInfo(
    name,
    builder: (data) {
      return const _i15.IntentionEditorPage();
    },
  );
}

/// generated route for
/// [_i16.RelationDetailsPage]
class RelationDetailsRoute
    extends _i20.PageRouteInfo<RelationDetailsRouteArgs> {
  RelationDetailsRoute({
    required _i33.LongTermRelationId relationId,
    _i23.Key? key,
    List<_i20.PageRouteInfo>? children,
  }) : super(
         RelationDetailsRoute.name,
         args: RelationDetailsRouteArgs(relationId: relationId, key: key),
         initialChildren: children,
       );

  static const String name = 'RelationDetailsRoute';

  static _i20.PageInfo page = _i20.PageInfo(
    name,
    builder: (data) {
      final args = data.argsAs<RelationDetailsRouteArgs>();
      return _i16.RelationDetailsPage(
        relationId: args.relationId,
        key: args.key,
      );
    },
  );
}

class RelationDetailsRouteArgs {
  const RelationDetailsRouteArgs({required this.relationId, this.key});

  final _i33.LongTermRelationId relationId;

  final _i23.Key? key;

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
/// [_i17.RelationEditorPage]
class RelationEditorRoute extends _i20.PageRouteInfo<RelationEditorRouteArgs> {
  RelationEditorRoute({
    required _i34.RelationEditorContext editorContext,
    _i23.Key? key,
    List<_i20.PageRouteInfo>? children,
  }) : super(
         RelationEditorRoute.name,
         args: RelationEditorRouteArgs(editorContext: editorContext, key: key),
         initialChildren: children,
       );

  static const String name = 'RelationEditorRoute';

  static _i20.PageInfo page = _i20.PageInfo(
    name,
    builder: (data) {
      final args = data.argsAs<RelationEditorRouteArgs>();
      return _i17.RelationEditorPage(
        editorContext: args.editorContext,
        key: args.key,
      );
    },
  );
}

class RelationEditorRouteArgs {
  const RelationEditorRouteArgs({required this.editorContext, this.key});

  final _i34.RelationEditorContext editorContext;

  final _i23.Key? key;

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
/// [_i18.RelationParticipantPickerPage]
class RelationParticipantPickerRoute
    extends _i20.PageRouteInfo<RelationParticipantPickerRouteArgs> {
  RelationParticipantPickerRoute({
    required _i35.RelationParticipantChoice choice,
    _i25.Key? key,
    List<_i20.PageRouteInfo>? children,
  }) : super(
         RelationParticipantPickerRoute.name,
         args: RelationParticipantPickerRouteArgs(choice: choice, key: key),
         initialChildren: children,
       );

  static const String name = 'RelationParticipantPickerRoute';

  static _i20.PageInfo page = _i20.PageInfo(
    name,
    builder: (data) {
      final args = data.argsAs<RelationParticipantPickerRouteArgs>();
      return _i18.RelationParticipantPickerPage(
        choice: args.choice,
        key: args.key,
      );
    },
  );
}

class RelationParticipantPickerRouteArgs {
  const RelationParticipantPickerRouteArgs({required this.choice, this.key});

  final _i35.RelationParticipantChoice choice;

  final _i25.Key? key;

  @override
  String toString() {
    return 'RelationParticipantPickerRouteArgs{choice: $choice, key: $key}';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! RelationParticipantPickerRouteArgs) return false;
    return choice == other.choice && key == other.key;
  }

  @override
  int get hashCode => choice.hashCode ^ key.hashCode;
}

/// generated route for
/// [_i19.SettingsPage]
class SettingsRoute extends _i20.PageRouteInfo<void> {
  const SettingsRoute({List<_i20.PageRouteInfo>? children})
    : super(SettingsRoute.name, initialChildren: children);

  static const String name = 'SettingsRoute';

  static _i20.PageInfo page = _i20.PageInfo(
    name,
    builder: (data) {
      return const _i19.SettingsPage();
    },
  );
}
