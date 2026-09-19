// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'graph_command_coordinator.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(GraphCommandCoordinator)
final graphCommandCoordinatorProvider = GraphCommandCoordinatorProvider._();

final class GraphCommandCoordinatorProvider
    extends $NotifierProvider<GraphCommandCoordinator, void> {
  GraphCommandCoordinatorProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'graphCommandCoordinatorProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$graphCommandCoordinatorHash();

  @$internal
  @override
  GraphCommandCoordinator create() => GraphCommandCoordinator();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(void value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<void>(value),
    );
  }
}

String _$graphCommandCoordinatorHash() =>
    r'5bfa6421d1f2b001deea51d4481ff4e7f87ba037';

abstract class _$GraphCommandCoordinator extends $Notifier<void> {
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
