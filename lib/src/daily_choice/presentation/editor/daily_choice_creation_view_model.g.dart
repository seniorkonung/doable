// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'daily_choice_creation_view_model.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Собирает явную команду создания и сохраняет её принятие и результат в общей
/// сессии потока. Координатор выполняет запись независимо от жизни формы.

@ProviderFor(DailyChoiceCreationViewModel)
final dailyChoiceCreationViewModelProvider =
    DailyChoiceCreationViewModelFamily._();

/// Собирает явную команду создания и сохраняет её принятие и результат в общей
/// сессии потока. Координатор выполняет запись независимо от жизни формы.
final class DailyChoiceCreationViewModelProvider
    extends
        $NotifierProvider<
          DailyChoiceCreationViewModel,
          DailyChoiceCreationState
        > {
  /// Собирает явную команду создания и сохраняет её принятие и результат в общей
  /// сессии потока. Координатор выполняет запись независимо от жизни формы.
  DailyChoiceCreationViewModelProvider._({
    required DailyChoiceCreationViewModelFamily super.from,
    required (DailyChoiceCreationFlowSession, ConfirmedChoicePath, CalendarDate)
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
    r'd12f27631b40a2d43d4c8882eefd3a34ea4f4dda';

/// Собирает явную команду создания и сохраняет её принятие и результат в общей
/// сессии потока. Координатор выполняет запись независимо от жизни формы.

final class DailyChoiceCreationViewModelFamily extends $Family
    with
        $ClassFamilyOverride<
          DailyChoiceCreationViewModel,
          DailyChoiceCreationState,
          DailyChoiceCreationState,
          DailyChoiceCreationState,
          (DailyChoiceCreationFlowSession, ConfirmedChoicePath, CalendarDate)
        > {
  DailyChoiceCreationViewModelFamily._()
    : super(
        retry: null,
        name: r'dailyChoiceCreationViewModelProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Собирает явную команду создания и сохраняет её принятие и результат в общей
  /// сессии потока. Координатор выполняет запись независимо от жизни формы.

  DailyChoiceCreationViewModelProvider call(
    DailyChoiceCreationFlowSession session,
    ConfirmedChoicePath path,
    CalendarDate date,
  ) => DailyChoiceCreationViewModelProvider._(
    argument: (session, path, date),
    from: this,
  );

  @override
  String toString() => r'dailyChoiceCreationViewModelProvider';
}

/// Собирает явную команду создания и сохраняет её принятие и результат в общей
/// сессии потока. Координатор выполняет запись независимо от жизни формы.

abstract class _$DailyChoiceCreationViewModel
    extends $Notifier<DailyChoiceCreationState> {
  late final _$args =
      ref.$arg
          as (
            DailyChoiceCreationFlowSession,
            ConfirmedChoicePath,
            CalendarDate,
          );
  DailyChoiceCreationFlowSession get session => _$args.$1;
  ConfirmedChoicePath get path => _$args.$2;
  CalendarDate get date => _$args.$3;

  DailyChoiceCreationState build(
    DailyChoiceCreationFlowSession session,
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
