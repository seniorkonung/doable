// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'daily_choice_edit_view_model.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(DailyChoiceEditViewModel)
final dailyChoiceEditViewModelProvider = DailyChoiceEditViewModelFamily._();

final class DailyChoiceEditViewModelProvider
    extends $NotifierProvider<DailyChoiceEditViewModel, DailyChoiceEditState> {
  DailyChoiceEditViewModelProvider._({
    required DailyChoiceEditViewModelFamily super.from,
    required DailyChoice super.argument,
  }) : super(
         retry: null,
         name: r'dailyChoiceEditViewModelProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$dailyChoiceEditViewModelHash();

  @override
  String toString() {
    return r'dailyChoiceEditViewModelProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  DailyChoiceEditViewModel create() => DailyChoiceEditViewModel();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(DailyChoiceEditState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<DailyChoiceEditState>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is DailyChoiceEditViewModelProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$dailyChoiceEditViewModelHash() =>
    r'1aa33278e3f84f9d7dba42ec1c6eb1ade941cc63';

final class DailyChoiceEditViewModelFamily extends $Family
    with
        $ClassFamilyOverride<
          DailyChoiceEditViewModel,
          DailyChoiceEditState,
          DailyChoiceEditState,
          DailyChoiceEditState,
          DailyChoice
        > {
  DailyChoiceEditViewModelFamily._()
    : super(
        retry: null,
        name: r'dailyChoiceEditViewModelProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  DailyChoiceEditViewModelProvider call(DailyChoice original) =>
      DailyChoiceEditViewModelProvider._(argument: original, from: this);

  @override
  String toString() => r'dailyChoiceEditViewModelProvider';
}

abstract class _$DailyChoiceEditViewModel
    extends $Notifier<DailyChoiceEditState> {
  late final _$args = ref.$arg as DailyChoice;
  DailyChoice get original => _$args;

  DailyChoiceEditState build(DailyChoice original);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<DailyChoiceEditState, DailyChoiceEditState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<DailyChoiceEditState, DailyChoiceEditState>,
              DailyChoiceEditState,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}
