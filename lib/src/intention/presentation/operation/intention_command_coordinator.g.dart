// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'intention_command_coordinator.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(IntentionCommandCoordinator)
final intentionCommandCoordinatorProvider =
    IntentionCommandCoordinatorProvider._();

final class IntentionCommandCoordinatorProvider
    extends $NotifierProvider<IntentionCommandCoordinator, void> {
  IntentionCommandCoordinatorProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'intentionCommandCoordinatorProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$intentionCommandCoordinatorHash();

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
}

String _$intentionCommandCoordinatorHash() =>
    r'b9d9bf94e42c08de196ad811a3889461a17d680a';

abstract class _$IntentionCommandCoordinator extends $Notifier<void> {
  void build();
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
    return element.handleCreate(ref, build);
  }
}
