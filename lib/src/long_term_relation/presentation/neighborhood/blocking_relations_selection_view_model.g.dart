// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'blocking_relations_selection_view_model.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Хранит незавершённый выбор отдельно от сменяющихся порций соседства.

@ProviderFor(BlockingRelationsSelectionViewModel)
final blockingRelationsSelectionViewModelProvider =
    BlockingRelationsSelectionViewModelFamily._();

/// Хранит незавершённый выбор отдельно от сменяющихся порций соседства.
final class BlockingRelationsSelectionViewModelProvider
    extends
        $NotifierProvider<
          BlockingRelationsSelectionViewModel,
          BlockingRelationsSelectionState
        > {
  /// Хранит незавершённый выбор отдельно от сменяющихся порций соседства.
  BlockingRelationsSelectionViewModelProvider._({
    required BlockingRelationsSelectionViewModelFamily super.from,
    required IntentionId super.argument,
  }) : super(
         retry: null,
         name: r'blockingRelationsSelectionViewModelProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() =>
      _$blockingRelationsSelectionViewModelHash();

  @override
  String toString() {
    return r'blockingRelationsSelectionViewModelProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  BlockingRelationsSelectionViewModel create() =>
      BlockingRelationsSelectionViewModel();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(BlockingRelationsSelectionState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<BlockingRelationsSelectionState>(
        value,
      ),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is BlockingRelationsSelectionViewModelProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$blockingRelationsSelectionViewModelHash() =>
    r'9927fbf737a24460da195ec31efe44ac429d519d';

/// Хранит незавершённый выбор отдельно от сменяющихся порций соседства.

final class BlockingRelationsSelectionViewModelFamily extends $Family
    with
        $ClassFamilyOverride<
          BlockingRelationsSelectionViewModel,
          BlockingRelationsSelectionState,
          BlockingRelationsSelectionState,
          BlockingRelationsSelectionState,
          IntentionId
        > {
  BlockingRelationsSelectionViewModelFamily._()
    : super(
        retry: null,
        name: r'blockingRelationsSelectionViewModelProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Хранит незавершённый выбор отдельно от сменяющихся порций соседства.

  BlockingRelationsSelectionViewModelProvider call(IntentionId intentionId) =>
      BlockingRelationsSelectionViewModelProvider._(
        argument: intentionId,
        from: this,
      );

  @override
  String toString() => r'blockingRelationsSelectionViewModelProvider';
}

/// Хранит незавершённый выбор отдельно от сменяющихся порций соседства.

abstract class _$BlockingRelationsSelectionViewModel
    extends $Notifier<BlockingRelationsSelectionState> {
  late final _$args = ref.$arg as IntentionId;
  IntentionId get intentionId => _$args;

  BlockingRelationsSelectionState build(IntentionId intentionId);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref
            as $Ref<
              BlockingRelationsSelectionState,
              BlockingRelationsSelectionState
            >;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<
                BlockingRelationsSelectionState,
                BlockingRelationsSelectionState
              >,
              BlockingRelationsSelectionState,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}
