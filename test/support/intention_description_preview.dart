import 'package:doable/src/intention/application/intention_description_preview.dart';

/// Строит начало описания так же, как источники краткой сводки намерения.
IntentionDescriptionPreview? testDescriptionPreview(String? description) =>
    switch (description) {
      final description? => IntentionDescriptionPreview.fromDescription(
        description,
      ),
      null => null,
    };
