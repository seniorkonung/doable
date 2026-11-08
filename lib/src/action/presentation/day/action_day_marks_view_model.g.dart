// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'action_day_marks_view_model.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Отметки периода, независимые от выбранного дня и выдачи экрана дня.
/// Страница удерживает провайдер с ключом своего экземпляра всё время
/// своей жизни и передаёт изменения просмотра через [setViewport].

@ProviderFor(ActionDayMarksViewModel)
final actionDayMarksViewModelProvider = ActionDayMarksViewModelFamily._();

/// Отметки периода, независимые от выбранного дня и выдачи экрана дня.
/// Страница удерживает провайдер с ключом своего экземпляра всё время
/// своей жизни и передаёт изменения просмотра через [setViewport].
final class ActionDayMarksViewModelProvider
    extends $NotifierProvider<ActionDayMarksViewModel, ActionDayMarksState> {
  /// Отметки периода, независимые от выбранного дня и выдачи экрана дня.
  /// Страница удерживает провайдер с ключом своего экземпляра всё время
  /// своей жизни и передаёт изменения просмотра через [setViewport].
  ActionDayMarksViewModelProvider._({
    required ActionDayMarksViewModelFamily super.from,
    required ActionDayInstance super.argument,
  }) : super(
         retry: null,
         name: r'actionDayMarksViewModelProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$actionDayMarksViewModelHash();

  @override
  String toString() {
    return r'actionDayMarksViewModelProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  ActionDayMarksViewModel create() => ActionDayMarksViewModel();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ActionDayMarksState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ActionDayMarksState>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is ActionDayMarksViewModelProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$actionDayMarksViewModelHash() =>
    r'e86cc6d997b08b2f5b776ac3be559b619e46ed92';

/// Отметки периода, независимые от выбранного дня и выдачи экрана дня.
/// Страница удерживает провайдер с ключом своего экземпляра всё время
/// своей жизни и передаёт изменения просмотра через [setViewport].

final class ActionDayMarksViewModelFamily extends $Family
    with
        $ClassFamilyOverride<
          ActionDayMarksViewModel,
          ActionDayMarksState,
          ActionDayMarksState,
          ActionDayMarksState,
          ActionDayInstance
        > {
  ActionDayMarksViewModelFamily._()
    : super(
        retry: null,
        name: r'actionDayMarksViewModelProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Отметки периода, независимые от выбранного дня и выдачи экрана дня.
  /// Страница удерживает провайдер с ключом своего экземпляра всё время
  /// своей жизни и передаёт изменения просмотра через [setViewport].

  ActionDayMarksViewModelProvider call(ActionDayInstance instance) =>
      ActionDayMarksViewModelProvider._(argument: instance, from: this);

  @override
  String toString() => r'actionDayMarksViewModelProvider';
}

/// Отметки периода, независимые от выбранного дня и выдачи экрана дня.
/// Страница удерживает провайдер с ключом своего экземпляра всё время
/// своей жизни и передаёт изменения просмотра через [setViewport].

abstract class _$ActionDayMarksViewModel
    extends $Notifier<ActionDayMarksState> {
  late final _$args = ref.$arg as ActionDayInstance;
  ActionDayInstance get instance => _$args;

  ActionDayMarksState build(ActionDayInstance instance);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<ActionDayMarksState, ActionDayMarksState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<ActionDayMarksState, ActionDayMarksState>,
              ActionDayMarksState,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}
