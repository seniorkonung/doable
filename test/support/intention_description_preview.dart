import 'package:doable/src/shared/domain/text_preview.dart';

/// Строит начало описания так же, как источники краткой сводки намерения.
TextPreview? testDescriptionPreview(String? description) =>
    switch (description) {
      final description? => TextPreview.fromText(description),
      null => null,
    };
