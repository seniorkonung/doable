// dart format width=80
// GENERATED CODE - DO NOT MODIFY BY HAND

// **************************************************************************
// AutoRouterGenerator
// **************************************************************************

// ignore_for_file: type=lint
// coverage:ignore-file

// ignore_for_file: no_leading_underscores_for_library_prefixes

import 'package:auto_route/auto_route.dart' as _i17;
import 'package:collection/collection.dart' as _i26;
import 'package:doable/src/app/home/home_page.dart' as _i8;
import 'package:doable/src/app/navigation/app_shell_page.dart' as _i1;
import 'package:doable/src/app/settings/settings_page.dart' as _i16;
import 'package:doable/src/daily_choice/application/choice_path_draft.dart'
    as _i19;
import 'package:doable/src/daily_choice/application/confirmed_choice_path.dart'
    as _i24;
import 'package:doable/src/daily_choice/presentation/action_picker/daily_choice_action_picker_page.dart'
    as _i3;
import 'package:doable/src/daily_choice/presentation/catalog/daily_choice_catalog_page.dart'
    as _i4;
import 'package:doable/src/daily_choice/presentation/catalog/daily_choice_date_catalog_page.dart'
    as _i6;
import 'package:doable/src/daily_choice/presentation/daily_choice_creation_flow_session.dart'
    as _i23;
import 'package:doable/src/daily_choice/presentation/daily_choice_picker_launch.dart'
    as _i21;
import 'package:doable/src/daily_choice/presentation/editor/daily_choice_creation_page.dart'
    as _i5;
import 'package:doable/src/daily_choice/presentation/path/choice_path_page.dart'
    as _i2;
import 'package:doable/src/daily_choice/presentation/source_picker/daily_choice_source_picker_page.dart'
    as _i7;
import 'package:doable/src/intention/domain/intention_id.dart' as _i18;
import 'package:doable/src/intention/presentation/catalog/intention_catalog_page.dart'
    as _i9;
import 'package:doable/src/intention/presentation/details/intention_details_page.dart'
    as _i10;
import 'package:doable/src/intention/presentation/details/intention_page_target.dart'
    as _i11;
import 'package:doable/src/intention/presentation/edit/intention_edit_page.dart'
    as _i12;
import 'package:doable/src/intention/presentation/editor/intention_creation_launch.dart'
    as _i14;
import 'package:doable/src/intention/presentation/editor/intention_editor_page.dart'
    as _i13;
import 'package:doable/src/long_term_relation/application/intention_relation_group.dart'
    as _i28;
import 'package:doable/src/long_term_relation/presentation/batch_picker/relation_batch_picker_page.dart'
    as _i15;
import 'package:doable/src/shared/domain/calendar_date.dart' as _i25;
import 'package:flutter/foundation.dart' as _i27;
import 'package:flutter/material.dart' as _i20;
import 'package:flutter/widgets.dart' as _i22;

/// generated route for
/// [_i1.AppShellPage]
class AppShellRoute extends _i17.PageRouteInfo<void> {
  const AppShellRoute({List<_i17.PageRouteInfo>? children})
    : super(AppShellRoute.name, initialChildren: children);

  static const String name = 'AppShellRoute';

  static _i17.PageInfo page = _i17.PageInfo(
    name,
    builder: (data) {
      return const _i1.AppShellPage();
    },
  );
}

/// generated route for
/// [_i2.ChoicePathPage]
class ChoicePathRoute extends _i17.PageRouteInfo<ChoicePathRouteArgs> {
  ChoicePathRoute({
    required _i18.IntentionId sourceIntentionId,
    required _i19.ChoicePathDraftDirection direction,
    _i20.Key? key,
    List<_i17.PageRouteInfo>? children,
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

  static _i17.PageInfo page = _i17.PageInfo(
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

  final _i18.IntentionId sourceIntentionId;

  final _i19.ChoicePathDraftDirection direction;

  final _i20.Key? key;

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
    extends _i17.PageRouteInfo<DailyChoiceActionPickerRouteArgs> {
  DailyChoiceActionPickerRoute({
    required _i21.DailyChoicePickerLaunch launch,
    _i22.Key? key,
    List<_i17.PageRouteInfo>? children,
  }) : super(
         DailyChoiceActionPickerRoute.name,
         args: DailyChoiceActionPickerRouteArgs(launch: launch, key: key),
         initialChildren: children,
       );

  static const String name = 'DailyChoiceActionPickerRoute';

  static _i17.PageInfo page = _i17.PageInfo(
    name,
    builder: (data) {
      final args = data.argsAs<DailyChoiceActionPickerRouteArgs>();
      return _i3.DailyChoiceActionPickerPage(
        launch: args.launch,
        key: args.key,
      );
    },
  );
}

class DailyChoiceActionPickerRouteArgs {
  const DailyChoiceActionPickerRouteArgs({required this.launch, this.key});

  final _i21.DailyChoicePickerLaunch launch;

  final _i22.Key? key;

  @override
  String toString() {
    return 'DailyChoiceActionPickerRouteArgs{launch: $launch, key: $key}';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! DailyChoiceActionPickerRouteArgs) return false;
    return launch == other.launch && key == other.key;
  }

  @override
  int get hashCode => launch.hashCode ^ key.hashCode;
}

/// generated route for
/// [_i4.DailyChoiceCatalogPage]
class DailyChoiceCatalogRoute extends _i17.PageRouteInfo<void> {
  const DailyChoiceCatalogRoute({List<_i17.PageRouteInfo>? children})
    : super(DailyChoiceCatalogRoute.name, initialChildren: children);

  static const String name = 'DailyChoiceCatalogRoute';

  static _i17.PageInfo page = _i17.PageInfo(
    name,
    builder: (data) {
      return const _i4.DailyChoiceCatalogPage();
    },
  );
}

/// generated route for
/// [_i5.DailyChoiceCreationPage]
class DailyChoiceCreationRoute
    extends _i17.PageRouteInfo<DailyChoiceCreationRouteArgs> {
  DailyChoiceCreationRoute({
    required _i23.DailyChoiceCreationFlowSession session,
    required _i24.ConfirmedChoicePath path,
    required List<_i5.DailyChoiceCreationStep> steps,
    required _i25.CalendarDate initialDate,
    _i19.ChoicePathDraftDirection direction =
        _i19.ChoicePathDraftDirection.topDown,
    _i20.Key? key,
    List<_i17.PageRouteInfo>? children,
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

  static _i17.PageInfo page = _i17.PageInfo(
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
    this.direction = _i19.ChoicePathDraftDirection.topDown,
    this.key,
  });

  final _i23.DailyChoiceCreationFlowSession session;

  final _i24.ConfirmedChoicePath path;

  final List<_i5.DailyChoiceCreationStep> steps;

  final _i25.CalendarDate initialDate;

  final _i19.ChoicePathDraftDirection direction;

  final _i20.Key? key;

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
        const _i26.ListEquality<_i5.DailyChoiceCreationStep>().equals(
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
      const _i26.ListEquality<_i5.DailyChoiceCreationStep>().hash(steps) ^
      initialDate.hashCode ^
      direction.hashCode ^
      key.hashCode;
}

/// generated route for
/// [_i6.DailyChoiceDateCatalogPage]
class DailyChoiceDateCatalogRoute
    extends _i17.PageRouteInfo<DailyChoiceDateCatalogRouteArgs> {
  DailyChoiceDateCatalogRoute({
    required _i25.CalendarDate date,
    _i20.Key? key,
    List<_i17.PageRouteInfo>? children,
  }) : super(
         DailyChoiceDateCatalogRoute.name,
         args: DailyChoiceDateCatalogRouteArgs(date: date, key: key),
         initialChildren: children,
       );

  static const String name = 'DailyChoiceDateCatalogRoute';

  static _i17.PageInfo page = _i17.PageInfo(
    name,
    builder: (data) {
      final args = data.argsAs<DailyChoiceDateCatalogRouteArgs>();
      return _i6.DailyChoiceDateCatalogPage(date: args.date, key: args.key);
    },
  );
}

class DailyChoiceDateCatalogRouteArgs {
  const DailyChoiceDateCatalogRouteArgs({required this.date, this.key});

  final _i25.CalendarDate date;

  final _i20.Key? key;

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
/// [_i7.DailyChoiceSourcePickerPage]
class DailyChoiceSourcePickerRoute
    extends _i17.PageRouteInfo<DailyChoiceSourcePickerRouteArgs> {
  DailyChoiceSourcePickerRoute({
    required _i21.DailyChoicePickerLaunch launch,
    _i22.Key? key,
    List<_i17.PageRouteInfo>? children,
  }) : super(
         DailyChoiceSourcePickerRoute.name,
         args: DailyChoiceSourcePickerRouteArgs(launch: launch, key: key),
         initialChildren: children,
       );

  static const String name = 'DailyChoiceSourcePickerRoute';

  static _i17.PageInfo page = _i17.PageInfo(
    name,
    builder: (data) {
      final args = data.argsAs<DailyChoiceSourcePickerRouteArgs>();
      return _i7.DailyChoiceSourcePickerPage(
        launch: args.launch,
        key: args.key,
      );
    },
  );
}

class DailyChoiceSourcePickerRouteArgs {
  const DailyChoiceSourcePickerRouteArgs({required this.launch, this.key});

  final _i21.DailyChoicePickerLaunch launch;

  final _i22.Key? key;

  @override
  String toString() {
    return 'DailyChoiceSourcePickerRouteArgs{launch: $launch, key: $key}';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! DailyChoiceSourcePickerRouteArgs) return false;
    return launch == other.launch && key == other.key;
  }

  @override
  int get hashCode => launch.hashCode ^ key.hashCode;
}

/// generated route for
/// [_i8.HomePage]
class HomeRoute extends _i17.PageRouteInfo<void> {
  const HomeRoute({List<_i17.PageRouteInfo>? children})
    : super(HomeRoute.name, initialChildren: children);

  static const String name = 'HomeRoute';

  static _i17.PageInfo page = _i17.PageInfo(
    name,
    builder: (data) {
      return const _i8.HomePage();
    },
  );
}

/// generated route for
/// [_i9.IntentionCatalogPage]
class IntentionCatalogRoute extends _i17.PageRouteInfo<void> {
  const IntentionCatalogRoute({List<_i17.PageRouteInfo>? children})
    : super(IntentionCatalogRoute.name, initialChildren: children);

  static const String name = 'IntentionCatalogRoute';

  static _i17.PageInfo page = _i17.PageInfo(
    name,
    builder: (data) {
      return const _i9.IntentionCatalogPage();
    },
  );
}

/// generated route for
/// [_i10.IntentionDetailsPage]
class IntentionDetailsRoute
    extends _i17.PageRouteInfo<IntentionDetailsRouteArgs> {
  IntentionDetailsRoute({
    required _i18.IntentionId intentionId,
    _i11.IntentionPageTarget target = const _i11.OverviewTarget(),
    _i27.Key? key,
    List<_i17.PageRouteInfo>? children,
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

  static _i17.PageInfo page = _i17.PageInfo(
    name,
    builder: (data) {
      final args = data.argsAs<IntentionDetailsRouteArgs>();
      return _i10.IntentionDetailsPage(
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
    this.target = const _i11.OverviewTarget(),
    this.key,
  });

  final _i18.IntentionId intentionId;

  final _i11.IntentionPageTarget target;

  final _i27.Key? key;

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
/// [_i12.IntentionEditPage]
class IntentionEditRoute extends _i17.PageRouteInfo<IntentionEditRouteArgs> {
  IntentionEditRoute({
    required _i18.IntentionId intentionId,
    _i12.IntentionEditFocus focus = _i12.IntentionEditFocus.title,
    _i20.Key? key,
    List<_i17.PageRouteInfo>? children,
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

  static _i17.PageInfo page = _i17.PageInfo(
    name,
    builder: (data) {
      final args = data.argsAs<IntentionEditRouteArgs>();
      return _i12.IntentionEditPage(
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
    this.focus = _i12.IntentionEditFocus.title,
    this.key,
  });

  final _i18.IntentionId intentionId;

  final _i12.IntentionEditFocus focus;

  final _i20.Key? key;

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
/// [_i13.IntentionEditorPage]
class IntentionEditorRoute
    extends _i17.PageRouteInfo<IntentionEditorRouteArgs> {
  IntentionEditorRoute({
    _i20.Key? key,
    _i14.IntentionCreationLaunch launch =
        const _i14.IntentionCreationStandalone(),
    List<_i17.PageRouteInfo>? children,
  }) : super(
         IntentionEditorRoute.name,
         args: IntentionEditorRouteArgs(key: key, launch: launch),
         initialChildren: children,
       );

  static const String name = 'IntentionEditorRoute';

  static _i17.PageInfo page = _i17.PageInfo(
    name,
    builder: (data) {
      final args = data.argsAs<IntentionEditorRouteArgs>(
        orElse: () => const IntentionEditorRouteArgs(),
      );
      return _i13.IntentionEditorPage(key: args.key, launch: args.launch);
    },
  );
}

class IntentionEditorRouteArgs {
  const IntentionEditorRouteArgs({
    this.key,
    this.launch = const _i14.IntentionCreationStandalone(),
  });

  final _i20.Key? key;

  final _i14.IntentionCreationLaunch launch;

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
/// [_i15.RelationBatchPickerPage]
class RelationBatchPickerRoute
    extends _i17.PageRouteInfo<RelationBatchPickerRouteArgs> {
  RelationBatchPickerRoute({
    required _i18.IntentionId pageIntentionId,
    required String pageTitle,
    required _i28.IntentionRelationGroup group,
    _i22.Key? key,
    List<_i17.PageRouteInfo>? children,
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

  static _i17.PageInfo page = _i17.PageInfo(
    name,
    builder: (data) {
      final args = data.argsAs<RelationBatchPickerRouteArgs>();
      return _i15.RelationBatchPickerPage(
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

  final _i28.IntentionRelationGroup group;

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
/// [_i16.SettingsPage]
class SettingsRoute extends _i17.PageRouteInfo<void> {
  const SettingsRoute({List<_i17.PageRouteInfo>? children})
    : super(SettingsRoute.name, initialChildren: children);

  static const String name = 'SettingsRoute';

  static _i17.PageInfo page = _i17.PageInfo(
    name,
    builder: (data) {
      return const _i16.SettingsPage();
    },
  );
}
