// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'personal_graph_repository_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(personalGraphRepository)
final personalGraphRepositoryProvider = PersonalGraphRepositoryProvider._();

final class PersonalGraphRepositoryProvider
    extends
        $FunctionalProvider<
          GraphCommandRepository,
          GraphCommandRepository,
          GraphCommandRepository
        >
    with $Provider<GraphCommandRepository> {
  PersonalGraphRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'personalGraphRepositoryProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$personalGraphRepositoryHash();

  @$internal
  @override
  $ProviderElement<GraphCommandRepository> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  GraphCommandRepository create(Ref ref) {
    return personalGraphRepository(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(GraphCommandRepository value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<GraphCommandRepository>(value),
    );
  }
}

String _$personalGraphRepositoryHash() =>
    r'7bb29d8bab8332df294e975f9fb3ae1f83df5f75';
