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
          PersonalGraphRepository,
          PersonalGraphRepository,
          PersonalGraphRepository
        >
    with $Provider<PersonalGraphRepository> {
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
  $ProviderElement<PersonalGraphRepository> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  PersonalGraphRepository create(Ref ref) {
    return personalGraphRepository(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(PersonalGraphRepository value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<PersonalGraphRepository>(value),
    );
  }
}

String _$personalGraphRepositoryHash() =>
    r'bc4a53af9de4d7177edf6b03bf233c8a99ac0959';
