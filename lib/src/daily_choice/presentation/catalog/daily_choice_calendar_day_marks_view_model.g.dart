// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'daily_choice_calendar_day_marks_view_model.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Отметки периода, независимые от выбранного дня и выдачи каталога.
/// Страница удерживает провайдер с её начальной выбранной датой всё время
/// своей жизни и передаёт изменения просмотра через [setViewport].

@ProviderFor(DailyChoiceCalendarDayMarksViewModel)
final dailyChoiceCalendarDayMarksViewModelProvider =
    DailyChoiceCalendarDayMarksViewModelFamily._();

/// Отметки периода, независимые от выбранного дня и выдачи каталога.
/// Страница удерживает провайдер с её начальной выбранной датой всё время
/// своей жизни и передаёт изменения просмотра через [setViewport].
final class DailyChoiceCalendarDayMarksViewModelProvider
    extends
        $NotifierProvider<
          DailyChoiceCalendarDayMarksViewModel,
          DailyChoiceCalendarDayMarksState
        > {
  /// Отметки периода, независимые от выбранного дня и выдачи каталога.
  /// Страница удерживает провайдер с её начальной выбранной датой всё время
  /// своей жизни и передаёт изменения просмотра через [setViewport].
  DailyChoiceCalendarDayMarksViewModelProvider._({
    required DailyChoiceCalendarDayMarksViewModelFamily super.from,
    required CalendarDate super.argument,
  }) : super(
         retry: null,
         name: r'dailyChoiceCalendarDayMarksViewModelProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() =>
      _$dailyChoiceCalendarDayMarksViewModelHash();

  @override
  String toString() {
    return r'dailyChoiceCalendarDayMarksViewModelProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  DailyChoiceCalendarDayMarksViewModel create() =>
      DailyChoiceCalendarDayMarksViewModel();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(DailyChoiceCalendarDayMarksState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<DailyChoiceCalendarDayMarksState>(
        value,
      ),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is DailyChoiceCalendarDayMarksViewModelProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$dailyChoiceCalendarDayMarksViewModelHash() =>
    r'c5ef32e813d3df91ba6ce5132c717570714adc69';

/// Отметки периода, независимые от выбранного дня и выдачи каталога.
/// Страница удерживает провайдер с её начальной выбранной датой всё время
/// своей жизни и передаёт изменения просмотра через [setViewport].

final class DailyChoiceCalendarDayMarksViewModelFamily extends $Family
    with
        $ClassFamilyOverride<
          DailyChoiceCalendarDayMarksViewModel,
          DailyChoiceCalendarDayMarksState,
          DailyChoiceCalendarDayMarksState,
          DailyChoiceCalendarDayMarksState,
          CalendarDate
        > {
  DailyChoiceCalendarDayMarksViewModelFamily._()
    : super(
        retry: null,
        name: r'dailyChoiceCalendarDayMarksViewModelProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Отметки периода, независимые от выбранного дня и выдачи каталога.
  /// Страница удерживает провайдер с её начальной выбранной датой всё время
  /// своей жизни и передаёт изменения просмотра через [setViewport].

  DailyChoiceCalendarDayMarksViewModelProvider call(CalendarDate initialDate) =>
      DailyChoiceCalendarDayMarksViewModelProvider._(
        argument: initialDate,
        from: this,
      );

  @override
  String toString() => r'dailyChoiceCalendarDayMarksViewModelProvider';
}

/// Отметки периода, независимые от выбранного дня и выдачи каталога.
/// Страница удерживает провайдер с её начальной выбранной датой всё время
/// своей жизни и передаёт изменения просмотра через [setViewport].

abstract class _$DailyChoiceCalendarDayMarksViewModel
    extends $Notifier<DailyChoiceCalendarDayMarksState> {
  late final _$args = ref.$arg as CalendarDate;
  CalendarDate get initialDate => _$args;

  DailyChoiceCalendarDayMarksState build(CalendarDate initialDate);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref
            as $Ref<
              DailyChoiceCalendarDayMarksState,
              DailyChoiceCalendarDayMarksState
            >;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<
                DailyChoiceCalendarDayMarksState,
                DailyChoiceCalendarDayMarksState
              >,
              DailyChoiceCalendarDayMarksState,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}
