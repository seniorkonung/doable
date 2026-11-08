// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'action_day_view_model.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Публикует согласованную пару и независимо подгружает её секции.

@ProviderFor(ActionDayViewModel)
final actionDayViewModelProvider = ActionDayViewModelFamily._();

/// Публикует согласованную пару и независимо подгружает её секции.
final class ActionDayViewModelProvider
    extends $NotifierProvider<ActionDayViewModel, ActionDayState> {
  /// Публикует согласованную пару и независимо подгружает её секции.
  ActionDayViewModelProvider._({
    required ActionDayViewModelFamily super.from,
    required ActionDayInstance super.argument,
  }) : super(
         retry: null,
         name: r'actionDayViewModelProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$actionDayViewModelHash();

  @override
  String toString() {
    return r'actionDayViewModelProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  ActionDayViewModel create() => ActionDayViewModel();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ActionDayState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ActionDayState>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is ActionDayViewModelProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$actionDayViewModelHash() =>
    r'42d9cbff0cff46962cfbf13a3763ac7f24ce9d88';

/// Публикует согласованную пару и независимо подгружает её секции.

final class ActionDayViewModelFamily extends $Family
    with
        $ClassFamilyOverride<
          ActionDayViewModel,
          ActionDayState,
          ActionDayState,
          ActionDayState,
          ActionDayInstance
        > {
  ActionDayViewModelFamily._()
    : super(
        retry: null,
        name: r'actionDayViewModelProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Публикует согласованную пару и независимо подгружает её секции.

  ActionDayViewModelProvider call(ActionDayInstance instance) =>
      ActionDayViewModelProvider._(argument: instance, from: this);

  @override
  String toString() => r'actionDayViewModelProvider';
}

/// Публикует согласованную пару и независимо подгружает её секции.

abstract class _$ActionDayViewModel extends $Notifier<ActionDayState> {
  late final _$args = ref.$arg as ActionDayInstance;
  ActionDayInstance get instance => _$args;

  ActionDayState build(ActionDayInstance instance);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<ActionDayState, ActionDayState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<ActionDayState, ActionDayState>,
              ActionDayState,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}
