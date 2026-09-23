// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'daily_choice_creation_view_model.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Собирает одну явную команду создания и оставляет её coordinator после ухода
/// формы. Второе подтверждение той же формы не создаёт самостоятельный выбор.

@ProviderFor(DailyChoiceCreationViewModel)
final dailyChoiceCreationViewModelProvider =
    DailyChoiceCreationViewModelFamily._();

/// Собирает одну явную команду создания и оставляет её coordinator после ухода
/// формы. Второе подтверждение той же формы не создаёт самостоятельный выбор.
final class DailyChoiceCreationViewModelProvider
    extends
        $NotifierProvider<
          DailyChoiceCreationViewModel,
          DailyChoiceCreationState
        > {
  /// Собирает одну явную команду создания и оставляет её coordinator после ухода
  /// формы. Второе подтверждение той же формы не создаёт самостоятельный выбор.
  DailyChoiceCreationViewModelProvider._({
    required DailyChoiceCreationViewModelFamily super.from,
    required (DailyChoiceCreationFormKey, ConfirmedChoicePath, CalendarDate)
    super.argument,
  }) : super(
         retry: null,
         name: r'dailyChoiceCreationViewModelProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$dailyChoiceCreationViewModelHash();

  @override
  String toString() {
    return r'dailyChoiceCreationViewModelProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  DailyChoiceCreationViewModel create() => DailyChoiceCreationViewModel();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(DailyChoiceCreationState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<DailyChoiceCreationState>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is DailyChoiceCreationViewModelProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$dailyChoiceCreationViewModelHash() =>
    r'47f89ec2f727d53d04eb12c4351af1f1e2192169';

/// Собирает одну явную команду создания и оставляет её coordinator после ухода
/// формы. Второе подтверждение той же формы не создаёт самостоятельный выбор.

final class DailyChoiceCreationViewModelFamily extends $Family
    with
        $ClassFamilyOverride<
          DailyChoiceCreationViewModel,
          DailyChoiceCreationState,
          DailyChoiceCreationState,
          DailyChoiceCreationState,
          (DailyChoiceCreationFormKey, ConfirmedChoicePath, CalendarDate)
        > {
  DailyChoiceCreationViewModelFamily._()
    : super(
        retry: null,
        name: r'dailyChoiceCreationViewModelProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Собирает одну явную команду создания и оставляет её coordinator после ухода
  /// формы. Второе подтверждение той же формы не создаёт самостоятельный выбор.

  DailyChoiceCreationViewModelProvider call(
    DailyChoiceCreationFormKey formKey,
    ConfirmedChoicePath path,
    CalendarDate date,
  ) => DailyChoiceCreationViewModelProvider._(
    argument: (formKey, path, date),
    from: this,
  );

  @override
  String toString() => r'dailyChoiceCreationViewModelProvider';
}

/// Собирает одну явную команду создания и оставляет её coordinator после ухода
/// формы. Второе подтверждение той же формы не создаёт самостоятельный выбор.

abstract class _$DailyChoiceCreationViewModel
    extends $Notifier<DailyChoiceCreationState> {
  late final _$args =
      ref.$arg
          as (DailyChoiceCreationFormKey, ConfirmedChoicePath, CalendarDate);
  DailyChoiceCreationFormKey get formKey => _$args.$1;
  ConfirmedChoicePath get path => _$args.$2;
  CalendarDate get date => _$args.$3;

  DailyChoiceCreationState build(
    DailyChoiceCreationFormKey formKey,
    ConfirmedChoicePath path,
    CalendarDate date,
  );
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref as $Ref<DailyChoiceCreationState, DailyChoiceCreationState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<DailyChoiceCreationState, DailyChoiceCreationState>,
              DailyChoiceCreationState,
              Object?,
              Object?
            >;
    return element.handleCreate(
      ref,
      () => build(_$args.$1, _$args.$2, _$args.$3),
    );
  }
}
