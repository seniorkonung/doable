// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'relation_editor_view_model.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Черновик одной формы создания долговременной связи.
///
/// ViewModel не хранит связь: он собирает выбор пользователя, проверяет его до
/// отправки и передаёт готовую команду общему coordinator графа. Пока принятая
/// отправка выполняется, вторая команда той же формы не принимается, а уход с
/// экрана завершает только экранную сессию — выполнение продолжается до
/// различимого результата.

@ProviderFor(RelationEditorViewModel)
final relationEditorViewModelProvider = RelationEditorViewModelFamily._();

/// Черновик одной формы создания долговременной связи.
///
/// ViewModel не хранит связь: он собирает выбор пользователя, проверяет его до
/// отправки и передаёт готовую команду общему coordinator графа. Пока принятая
/// отправка выполняется, вторая команда той же формы не принимается, а уход с
/// экрана завершает только экранную сессию — выполнение продолжается до
/// различимого результата.
final class RelationEditorViewModelProvider
    extends $NotifierProvider<RelationEditorViewModel, RelationEditorState> {
  /// Черновик одной формы создания долговременной связи.
  ///
  /// ViewModel не хранит связь: он собирает выбор пользователя, проверяет его до
  /// отправки и передаёт готовую команду общему coordinator графа. Пока принятая
  /// отправка выполняется, вторая команда той же формы не принимается, а уход с
  /// экрана завершает только экранную сессию — выполнение продолжается до
  /// различимого результата.
  RelationEditorViewModelProvider._({
    required RelationEditorViewModelFamily super.from,
    required (LongTermRelationCreationFormKey, RelationCreationContext)
    super.argument,
  }) : super(
         retry: null,
         name: r'relationEditorViewModelProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$relationEditorViewModelHash();

  @override
  String toString() {
    return r'relationEditorViewModelProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  RelationEditorViewModel create() => RelationEditorViewModel();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(RelationEditorState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<RelationEditorState>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is RelationEditorViewModelProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$relationEditorViewModelHash() =>
    r'6c950e130ad59f956dbfcb3aa889578d8b056d82';

/// Черновик одной формы создания долговременной связи.
///
/// ViewModel не хранит связь: он собирает выбор пользователя, проверяет его до
/// отправки и передаёт готовую команду общему coordinator графа. Пока принятая
/// отправка выполняется, вторая команда той же формы не принимается, а уход с
/// экрана завершает только экранную сессию — выполнение продолжается до
/// различимого результата.

final class RelationEditorViewModelFamily extends $Family
    with
        $ClassFamilyOverride<
          RelationEditorViewModel,
          RelationEditorState,
          RelationEditorState,
          RelationEditorState,
          (LongTermRelationCreationFormKey, RelationCreationContext)
        > {
  RelationEditorViewModelFamily._()
    : super(
        retry: null,
        name: r'relationEditorViewModelProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Черновик одной формы создания долговременной связи.
  ///
  /// ViewModel не хранит связь: он собирает выбор пользователя, проверяет его до
  /// отправки и передаёт готовую команду общему coordinator графа. Пока принятая
  /// отправка выполняется, вторая команда той же формы не принимается, а уход с
  /// экрана завершает только экранную сессию — выполнение продолжается до
  /// различимого результата.

  RelationEditorViewModelProvider call(
    LongTermRelationCreationFormKey formKey,
    RelationCreationContext context,
  ) => RelationEditorViewModelProvider._(
    argument: (formKey, context),
    from: this,
  );

  @override
  String toString() => r'relationEditorViewModelProvider';
}

/// Черновик одной формы создания долговременной связи.
///
/// ViewModel не хранит связь: он собирает выбор пользователя, проверяет его до
/// отправки и передаёт готовую команду общему coordinator графа. Пока принятая
/// отправка выполняется, вторая команда той же формы не принимается, а уход с
/// экрана завершает только экранную сессию — выполнение продолжается до
/// различимого результата.

abstract class _$RelationEditorViewModel
    extends $Notifier<RelationEditorState> {
  late final _$args =
      ref.$arg as (LongTermRelationCreationFormKey, RelationCreationContext);
  LongTermRelationCreationFormKey get formKey => _$args.$1;
  RelationCreationContext get context => _$args.$2;

  RelationEditorState build(
    LongTermRelationCreationFormKey formKey,
    RelationCreationContext context,
  );
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<RelationEditorState, RelationEditorState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<RelationEditorState, RelationEditorState>,
              RelationEditorState,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args.$1, _$args.$2));
  }
}
