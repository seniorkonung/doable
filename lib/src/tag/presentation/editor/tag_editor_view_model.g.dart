// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'tag_editor_view_model.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(TagEditorViewModel)
final tagEditorViewModelProvider = TagEditorViewModelFamily._();

final class TagEditorViewModelProvider
    extends $NotifierProvider<TagEditorViewModel, TagEditorState> {
  TagEditorViewModelProvider._({
    required TagEditorViewModelFamily super.from,
    required TagEditorContext super.argument,
  }) : super(
         retry: null,
         name: r'tagEditorViewModelProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$tagEditorViewModelHash();

  @override
  String toString() {
    return r'tagEditorViewModelProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  TagEditorViewModel create() => TagEditorViewModel();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(TagEditorState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<TagEditorState>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is TagEditorViewModelProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$tagEditorViewModelHash() =>
    r'cccc8cf4494bf90a5936d32d87ef7a2193e978db';

final class TagEditorViewModelFamily extends $Family
    with
        $ClassFamilyOverride<
          TagEditorViewModel,
          TagEditorState,
          TagEditorState,
          TagEditorState,
          TagEditorContext
        > {
  TagEditorViewModelFamily._()
    : super(
        retry: null,
        name: r'tagEditorViewModelProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  TagEditorViewModelProvider call(TagEditorContext context) =>
      TagEditorViewModelProvider._(argument: context, from: this);

  @override
  String toString() => r'tagEditorViewModelProvider';
}

abstract class _$TagEditorViewModel extends $Notifier<TagEditorState> {
  late final _$args = ref.$arg as TagEditorContext;
  TagEditorContext get context => _$args;

  TagEditorState build(TagEditorContext context);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<TagEditorState, TagEditorState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<TagEditorState, TagEditorState>,
              TagEditorState,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}
