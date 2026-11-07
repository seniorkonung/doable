// dart format width=80
// GENERATED CODE - DO NOT MODIFY BY HAND

// **************************************************************************
// AutoRouterGenerator
// **************************************************************************

// ignore_for_file: type=lint
// coverage:ignore-file

// ignore_for_file: no_leading_underscores_for_library_prefixes

import 'package:auto_route/auto_route.dart' as _i15;
import 'package:doable/src/action/domain/action_path.dart' as _i20;
import 'package:doable/src/action/domain/action_priority.dart' as _i21;
import 'package:doable/src/action/presentation/day/action_day_date_page.dart'
    as _i1;
import 'package:doable/src/action/presentation/day/action_day_root_page.dart'
    as _i2;
import 'package:doable/src/action/presentation/path/path_page.dart' as _i11;
import 'package:doable/src/action/presentation/path_start/path_start_picker_page.dart'
    as _i12;
import 'package:doable/src/app/home/home_page.dart' as _i4;
import 'package:doable/src/app/navigation/app_shell_page.dart' as _i3;
import 'package:doable/src/app/settings/settings_page.dart' as _i14;
import 'package:doable/src/intention/domain/intention_id.dart' as _i18;
import 'package:doable/src/intention/presentation/catalog/intention_catalog_page.dart'
    as _i5;
import 'package:doable/src/intention/presentation/details/intention_details_page.dart'
    as _i6;
import 'package:doable/src/intention/presentation/details/intention_page_target.dart'
    as _i7;
import 'package:doable/src/intention/presentation/edit/intention_edit_page.dart'
    as _i8;
import 'package:doable/src/intention/presentation/editor/intention_creation_launch.dart'
    as _i10;
import 'package:doable/src/intention/presentation/editor/intention_editor_page.dart'
    as _i9;
import 'package:doable/src/long_term_relation/application/intention_relation_group.dart'
    as _i23;
import 'package:doable/src/long_term_relation/presentation/batch_picker/relation_batch_picker_page.dart'
    as _i13;
import 'package:doable/src/shared/domain/calendar_date.dart' as _i16;
import 'package:flutter/foundation.dart' as _i19;
import 'package:flutter/material.dart' as _i17;
import 'package:flutter/widgets.dart' as _i22;

/// generated route for
/// [_i1.ActionDayDatePage]
class ActionDayDateRoute extends _i15.PageRouteInfo<ActionDayDateRouteArgs> {
  ActionDayDateRoute({
    required _i16.CalendarDate date,
    _i17.Key? key,
    List<_i15.PageRouteInfo>? children,
  }) : super(
         ActionDayDateRoute.name,
         args: ActionDayDateRouteArgs(date: date, key: key),
         initialChildren: children,
       );

  static const String name = 'ActionDayDateRoute';

  static _i15.PageInfo page = _i15.PageInfo(
    name,
    builder: (data) {
      final args = data.argsAs<ActionDayDateRouteArgs>();
      return _i1.ActionDayDatePage(date: args.date, key: args.key);
    },
  );
}

class ActionDayDateRouteArgs {
  const ActionDayDateRouteArgs({required this.date, this.key});

  final _i16.CalendarDate date;

  final _i17.Key? key;

  @override
  String toString() {
    return 'ActionDayDateRouteArgs{date: $date, key: $key}';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! ActionDayDateRouteArgs) return false;
    return date == other.date && key == other.key;
  }

  @override
  int get hashCode => date.hashCode ^ key.hashCode;
}

/// generated route for
/// [_i2.ActionDayRootPage]
class ActionDayRootRoute extends _i15.PageRouteInfo<void> {
  const ActionDayRootRoute({List<_i15.PageRouteInfo>? children})
    : super(ActionDayRootRoute.name, initialChildren: children);

  static const String name = 'ActionDayRootRoute';

  static _i15.PageInfo page = _i15.PageInfo(
    name,
    builder: (data) {
      return const _i2.ActionDayRootPage();
    },
  );
}

/// generated route for
/// [_i3.AppShellPage]
class AppShellRoute extends _i15.PageRouteInfo<void> {
  const AppShellRoute({List<_i15.PageRouteInfo>? children})
    : super(AppShellRoute.name, initialChildren: children);

  static const String name = 'AppShellRoute';

  static _i15.PageInfo page = _i15.PageInfo(
    name,
    builder: (data) {
      return const _i3.AppShellPage();
    },
  );
}

/// generated route for
/// [_i4.HomePage]
class HomeRoute extends _i15.PageRouteInfo<void> {
  const HomeRoute({List<_i15.PageRouteInfo>? children})
    : super(HomeRoute.name, initialChildren: children);

  static const String name = 'HomeRoute';

  static _i15.PageInfo page = _i15.PageInfo(
    name,
    builder: (data) {
      return const _i4.HomePage();
    },
  );
}

/// generated route for
/// [_i5.IntentionCatalogPage]
class IntentionCatalogRoute extends _i15.PageRouteInfo<void> {
  const IntentionCatalogRoute({List<_i15.PageRouteInfo>? children})
    : super(IntentionCatalogRoute.name, initialChildren: children);

  static const String name = 'IntentionCatalogRoute';

  static _i15.PageInfo page = _i15.PageInfo(
    name,
    builder: (data) {
      return const _i5.IntentionCatalogPage();
    },
  );
}

/// generated route for
/// [_i6.IntentionDetailsPage]
class IntentionDetailsRoute
    extends _i15.PageRouteInfo<IntentionDetailsRouteArgs> {
  IntentionDetailsRoute({
    required _i18.IntentionId intentionId,
    _i7.IntentionPageTarget target = const _i7.OverviewTarget(),
    _i19.Key? key,
    List<_i15.PageRouteInfo>? children,
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

  static _i15.PageInfo page = _i15.PageInfo(
    name,
    builder: (data) {
      final args = data.argsAs<IntentionDetailsRouteArgs>();
      return _i6.IntentionDetailsPage(
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
    this.target = const _i7.OverviewTarget(),
    this.key,
  });

  final _i18.IntentionId intentionId;

  final _i7.IntentionPageTarget target;

  final _i19.Key? key;

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
/// [_i8.IntentionEditPage]
class IntentionEditRoute extends _i15.PageRouteInfo<IntentionEditRouteArgs> {
  IntentionEditRoute({
    required _i18.IntentionId intentionId,
    _i8.IntentionEditFocus focus = _i8.IntentionEditFocus.title,
    _i17.Key? key,
    List<_i15.PageRouteInfo>? children,
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

  static _i15.PageInfo page = _i15.PageInfo(
    name,
    builder: (data) {
      final args = data.argsAs<IntentionEditRouteArgs>();
      return _i8.IntentionEditPage(
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
    this.focus = _i8.IntentionEditFocus.title,
    this.key,
  });

  final _i18.IntentionId intentionId;

  final _i8.IntentionEditFocus focus;

  final _i17.Key? key;

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
/// [_i9.IntentionEditorPage]
class IntentionEditorRoute
    extends _i15.PageRouteInfo<IntentionEditorRouteArgs> {
  IntentionEditorRoute({
    _i17.Key? key,
    _i10.IntentionCreationLaunch launch =
        const _i10.IntentionCreationStandalone(),
    List<_i15.PageRouteInfo>? children,
  }) : super(
         IntentionEditorRoute.name,
         args: IntentionEditorRouteArgs(key: key, launch: launch),
         initialChildren: children,
       );

  static const String name = 'IntentionEditorRoute';

  static _i15.PageInfo page = _i15.PageInfo(
    name,
    builder: (data) {
      final args = data.argsAs<IntentionEditorRouteArgs>(
        orElse: () => const IntentionEditorRouteArgs(),
      );
      return _i9.IntentionEditorPage(key: args.key, launch: args.launch);
    },
  );
}

class IntentionEditorRouteArgs {
  const IntentionEditorRouteArgs({
    this.key,
    this.launch = const _i10.IntentionCreationStandalone(),
  });

  final _i17.Key? key;

  final _i10.IntentionCreationLaunch launch;

  @override
  String toString() {
    return 'IntentionEditorRouteArgs{key: $key, launch: $launch}';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! IntentionEditorRouteArgs) return false;
    return key == other.key && launch == other.launch;
  }

  @override
  int get hashCode => key.hashCode ^ launch.hashCode;
}

/// generated route for
/// [_i11.PathPage]
class PathRoute extends _i15.PageRouteInfo<PathRouteArgs> {
  PathRoute({
    required _i12.PathStartFlow flow,
    required _i20.ActionPath? originalPath,
    required String actionTitle,
    required _i21.ActionPriority actionPriority,
    _i17.Key? key,
    List<_i15.PageRouteInfo>? children,
  }) : super(
         PathRoute.name,
         args: PathRouteArgs(
           flow: flow,
           originalPath: originalPath,
           actionTitle: actionTitle,
           actionPriority: actionPriority,
           key: key,
         ),
         initialChildren: children,
       );

  static const String name = 'PathRoute';

  static _i15.PageInfo page = _i15.PageInfo(
    name,
    builder: (data) {
      final args = data.argsAs<PathRouteArgs>();
      return _i11.PathPage(
        flow: args.flow,
        originalPath: args.originalPath,
        actionTitle: args.actionTitle,
        actionPriority: args.actionPriority,
        key: args.key,
      );
    },
  );
}

class PathRouteArgs {
  const PathRouteArgs({
    required this.flow,
    required this.originalPath,
    required this.actionTitle,
    required this.actionPriority,
    this.key,
  });

  final _i12.PathStartFlow flow;

  final _i20.ActionPath? originalPath;

  final String actionTitle;

  final _i21.ActionPriority actionPriority;

  final _i17.Key? key;

  @override
  String toString() {
    return 'PathRouteArgs{flow: $flow, originalPath: $originalPath, actionTitle: $actionTitle, actionPriority: $actionPriority, key: $key}';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! PathRouteArgs) return false;
    return flow == other.flow &&
        originalPath == other.originalPath &&
        actionTitle == other.actionTitle &&
        actionPriority == other.actionPriority &&
        key == other.key;
  }

  @override
  int get hashCode =>
      flow.hashCode ^
      originalPath.hashCode ^
      actionTitle.hashCode ^
      actionPriority.hashCode ^
      key.hashCode;
}

/// generated route for
/// [_i12.PathStartPickerPage]
class PathStartPickerRoute
    extends _i15.PageRouteInfo<PathStartPickerRouteArgs> {
  PathStartPickerRoute({
    required _i12.PathStartFlow flow,
    _i18.IntentionId? currentRoot,
    _i22.Key? key,
    List<_i15.PageRouteInfo>? children,
  }) : super(
         PathStartPickerRoute.name,
         args: PathStartPickerRouteArgs(
           flow: flow,
           currentRoot: currentRoot,
           key: key,
         ),
         initialChildren: children,
       );

  static const String name = 'PathStartPickerRoute';

  static _i15.PageInfo page = _i15.PageInfo(
    name,
    builder: (data) {
      final args = data.argsAs<PathStartPickerRouteArgs>();
      return _i12.PathStartPickerPage(
        flow: args.flow,
        currentRoot: args.currentRoot,
        key: args.key,
      );
    },
  );
}

class PathStartPickerRouteArgs {
  const PathStartPickerRouteArgs({
    required this.flow,
    this.currentRoot,
    this.key,
  });

  final _i12.PathStartFlow flow;

  final _i18.IntentionId? currentRoot;

  final _i22.Key? key;

  @override
  String toString() {
    return 'PathStartPickerRouteArgs{flow: $flow, currentRoot: $currentRoot, key: $key}';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! PathStartPickerRouteArgs) return false;
    return flow == other.flow &&
        currentRoot == other.currentRoot &&
        key == other.key;
  }

  @override
  int get hashCode => flow.hashCode ^ currentRoot.hashCode ^ key.hashCode;
}

/// generated route for
/// [_i13.RelationBatchPickerPage]
class RelationBatchPickerRoute
    extends _i15.PageRouteInfo<RelationBatchPickerRouteArgs> {
  RelationBatchPickerRoute({
    required _i18.IntentionId pageIntentionId,
    required String pageTitle,
    required _i23.IntentionRelationGroup group,
    _i22.Key? key,
    List<_i15.PageRouteInfo>? children,
  }) : super(
         RelationBatchPickerRoute.name,
         args: RelationBatchPickerRouteArgs(
           pageIntentionId: pageIntentionId,
           pageTitle: pageTitle,
           group: group,
           key: key,
         ),
         initialChildren: children,
       );

  static const String name = 'RelationBatchPickerRoute';

  static _i15.PageInfo page = _i15.PageInfo(
    name,
    builder: (data) {
      final args = data.argsAs<RelationBatchPickerRouteArgs>();
      return _i13.RelationBatchPickerPage(
        pageIntentionId: args.pageIntentionId,
        pageTitle: args.pageTitle,
        group: args.group,
        key: args.key,
      );
    },
  );
}

class RelationBatchPickerRouteArgs {
  const RelationBatchPickerRouteArgs({
    required this.pageIntentionId,
    required this.pageTitle,
    required this.group,
    this.key,
  });

  final _i18.IntentionId pageIntentionId;

  final String pageTitle;

  final _i23.IntentionRelationGroup group;

  final _i22.Key? key;

  @override
  String toString() {
    return 'RelationBatchPickerRouteArgs{pageIntentionId: $pageIntentionId, pageTitle: $pageTitle, group: $group, key: $key}';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! RelationBatchPickerRouteArgs) return false;
    return pageIntentionId == other.pageIntentionId &&
        pageTitle == other.pageTitle &&
        group == other.group &&
        key == other.key;
  }

  @override
  int get hashCode =>
      pageIntentionId.hashCode ^
      pageTitle.hashCode ^
      group.hashCode ^
      key.hashCode;
}

/// generated route for
/// [_i14.SettingsPage]
class SettingsRoute extends _i15.PageRouteInfo<void> {
  const SettingsRoute({List<_i15.PageRouteInfo>? children})
    : super(SettingsRoute.name, initialChildren: children);

  static const String name = 'SettingsRoute';

  static _i15.PageInfo page = _i15.PageInfo(
    name,
    builder: (data) {
      return const _i14.SettingsPage();
    },
  );
}
