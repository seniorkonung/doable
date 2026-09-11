// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'intention_command_coordinator.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(IntentionCommandCoordinator)
final intentionCommandCoordinatorProvider =
    IntentionCommandCoordinatorFamily._();

final class IntentionCommandCoordinatorProvider
    extends $NotifierProvider<IntentionCommandCoordinator, void> {
  IntentionCommandCoordinatorProvider._({
    required IntentionCommandCoordinatorFamily super.from,
    required IntentionRepository super.argument,
  }) : super(
         retry: null,
         name: r'intentionCommandCoordinatorProvider',
         isAutoDispose: false,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$intentionCommandCoordinatorHash();

  @override
  String toString() {
    return r'intentionCommandCoordinatorProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  IntentionCommandCoordinator create() => IntentionCommandCoordinator();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(void value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<void>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is IntentionCommandCoordinatorProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$intentionCommandCoordinatorHash() =>
    r'a389b97017faefe9e8e856b3f10585eb0595458d';

final class IntentionCommandCoordinatorFamily extends $Family
    with
        $ClassFamilyOverride<
          IntentionCommandCoordinator,
          void,
          void,
          void,
          IntentionRepository
        > {
  IntentionCommandCoordinatorFamily._()
    : super(
        retry: null,
        name: r'intentionCommandCoordinatorProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: false,
      );

  IntentionCommandCoordinatorProvider call(IntentionRepository repository) =>
      IntentionCommandCoordinatorProvider._(argument: repository, from: this);

  @override
  String toString() => r'intentionCommandCoordinatorProvider';
}

abstract class _$IntentionCommandCoordinator extends $Notifier<void> {
  late final _$args = ref.$arg as IntentionRepository;
  IntentionRepository get repository => _$args;

  void build(IntentionRepository repository);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<void, void>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<void, void>,
              void,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}
