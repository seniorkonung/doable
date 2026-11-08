// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'local_date_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Источник местного сегодня; по умолчанию — часы устройства.
///
/// Зависимостью владеет композиция приложения: `AppRuntime` предоставляет
/// контейнеру переданный при создании источник или [readDeviceLocalDay].
/// Проверки подставляют управляемые часы через `AppRuntime` или
/// переопределение провайдера до первого чтения часов.

@ProviderFor(localDateSource)
final localDateSourceProvider = LocalDateSourceProvider._();

/// Источник местного сегодня; по умолчанию — часы устройства.
///
/// Зависимостью владеет композиция приложения: `AppRuntime` предоставляет
/// контейнеру переданный при создании источник или [readDeviceLocalDay].
/// Проверки подставляют управляемые часы через `AppRuntime` или
/// переопределение провайдера до первого чтения часов.

final class LocalDateSourceProvider
    extends
        $FunctionalProvider<LocalDateSource, LocalDateSource, LocalDateSource>
    with $Provider<LocalDateSource> {
  /// Источник местного сегодня; по умолчанию — часы устройства.
  ///
  /// Зависимостью владеет композиция приложения: `AppRuntime` предоставляет
  /// контейнеру переданный при создании источник или [readDeviceLocalDay].
  /// Проверки подставляют управляемые часы через `AppRuntime` или
  /// переопределение провайдера до первого чтения часов.
  LocalDateSourceProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'localDateSourceProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$localDateSourceHash();

  @$internal
  @override
  $ProviderElement<LocalDateSource> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  LocalDateSource create(Ref ref) {
    return localDateSource(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(LocalDateSource value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<LocalDateSource>(value),
    );
  }
}

String _$localDateSourceHash() => r'2c19e5f283dc8174ba1c2edddd359d571cd288e1';
