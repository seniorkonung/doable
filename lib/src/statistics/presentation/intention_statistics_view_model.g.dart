// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'intention_statistics_view_model.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(IntentionStatisticsViewModel)
final intentionStatisticsViewModelProvider =
    IntentionStatisticsViewModelFamily._();

final class IntentionStatisticsViewModelProvider
    extends
        $NotifierProvider<
          IntentionStatisticsViewModel,
          IntentionStatisticsState
        > {
  IntentionStatisticsViewModelProvider._({
    required IntentionStatisticsViewModelFamily super.from,
    required (
      IntentionId,
      IntentionPageInstance, {
      IntentionStatisticsTarget? target,
    })
    super.argument,
  }) : super(
         retry: null,
         name: r'intentionStatisticsViewModelProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$intentionStatisticsViewModelHash();

  @override
  String toString() {
    return r'intentionStatisticsViewModelProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  IntentionStatisticsViewModel create() => IntentionStatisticsViewModel();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(IntentionStatisticsState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<IntentionStatisticsState>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is IntentionStatisticsViewModelProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$intentionStatisticsViewModelHash() =>
    r'a2e277935521d288a4e3dc444906929bcfacdfa7';

final class IntentionStatisticsViewModelFamily extends $Family
    with
        $ClassFamilyOverride<
          IntentionStatisticsViewModel,
          IntentionStatisticsState,
          IntentionStatisticsState,
          IntentionStatisticsState,
          (
            IntentionId,
            IntentionPageInstance, {
            IntentionStatisticsTarget? target,
          })
        > {
  IntentionStatisticsViewModelFamily._()
    : super(
        retry: null,
        name: r'intentionStatisticsViewModelProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  IntentionStatisticsViewModelProvider call(
    IntentionId intentionId,
    IntentionPageInstance pageInstance, {
    IntentionStatisticsTarget? target,
  }) => IntentionStatisticsViewModelProvider._(
    argument: (intentionId, pageInstance, target: target),
    from: this,
  );

  @override
  String toString() => r'intentionStatisticsViewModelProvider';
}

abstract class _$IntentionStatisticsViewModel
    extends $Notifier<IntentionStatisticsState> {
  late final _$args =
      ref.$arg
          as (
            IntentionId,
            IntentionPageInstance, {
            IntentionStatisticsTarget? target,
          });
  IntentionId get intentionId => _$args.$1;
  IntentionPageInstance get pageInstance => _$args.$2;
  IntentionStatisticsTarget? get target => _$args.target;

  IntentionStatisticsState build(
    IntentionId intentionId,
    IntentionPageInstance pageInstance, {
    IntentionStatisticsTarget? target,
  });
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref as $Ref<IntentionStatisticsState, IntentionStatisticsState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<IntentionStatisticsState, IntentionStatisticsState>,
              IntentionStatisticsState,
              Object?,
              Object?
            >;
    return element.handleCreate(
      ref,
      () => build(_$args.$1, _$args.$2, target: _$args.target),
    );
  }
}
