// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'daily_choice_local_date_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Источник локального сегодня каталога; по умолчанию — часы устройства.
///
/// Зависимостью владеет композиция приложения: `AppRuntime` предоставляет
/// контейнеру переданный при создании источник или [readDeviceLocalDate].
/// Проверки подставляют управляемую дату через `AppRuntime` или переопределение
/// провайдера до первого открытия каталога.

@ProviderFor(dailyChoiceLocalDateSource)
final dailyChoiceLocalDateSourceProvider =
    DailyChoiceLocalDateSourceProvider._();

/// Источник локального сегодня каталога; по умолчанию — часы устройства.
///
/// Зависимостью владеет композиция приложения: `AppRuntime` предоставляет
/// контейнеру переданный при создании источник или [readDeviceLocalDate].
/// Проверки подставляют управляемую дату через `AppRuntime` или переопределение
/// провайдера до первого открытия каталога.

final class DailyChoiceLocalDateSourceProvider
    extends
        $FunctionalProvider<
          DailyChoiceLocalDateSource,
          DailyChoiceLocalDateSource,
          DailyChoiceLocalDateSource
        >
    with $Provider<DailyChoiceLocalDateSource> {
  /// Источник локального сегодня каталога; по умолчанию — часы устройства.
  ///
  /// Зависимостью владеет композиция приложения: `AppRuntime` предоставляет
  /// контейнеру переданный при создании источник или [readDeviceLocalDate].
  /// Проверки подставляют управляемую дату через `AppRuntime` или переопределение
  /// провайдера до первого открытия каталога.
  DailyChoiceLocalDateSourceProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'dailyChoiceLocalDateSourceProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$dailyChoiceLocalDateSourceHash();

  @$internal
  @override
  $ProviderElement<DailyChoiceLocalDateSource> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  DailyChoiceLocalDateSource create(Ref ref) {
    return dailyChoiceLocalDateSource(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(DailyChoiceLocalDateSource value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<DailyChoiceLocalDateSource>(value),
    );
  }
}

String _$dailyChoiceLocalDateSourceHash() =>
    r'68323202a346df7e4ebd7c42998de14d58cfaf5c';
