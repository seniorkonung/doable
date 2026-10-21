import '../../../l10n/app_localizations.dart';
import '../../design_system/components/tag_dot.dart';
import '../domain/tag_color.dart';

/// Перевод предметного цвета в визуальный вариант дизайн-системы.
DoableTagColor? tagColorPresentation(TagColor? color) => switch (color) {
  null => null,
  TagColor.brown => DoableTagColor.brown,
  TagColor.orange => DoableTagColor.orange,
  TagColor.olive => DoableTagColor.olive,
  TagColor.green => DoableTagColor.green,
  TagColor.teal => DoableTagColor.teal,
  TagColor.blue => DoableTagColor.blue,
  TagColor.violet => DoableTagColor.violet,
  TagColor.purple => DoableTagColor.purple,
  TagColor.pink => DoableTagColor.pink,
};

/// Перевод выбранного визуального варианта в состояние тега.
TagColor? tagColorFromPresentation(DoableTagColor? color) => switch (color) {
  null => null,
  DoableTagColor.brown => TagColor.brown,
  DoableTagColor.orange => TagColor.orange,
  DoableTagColor.olive => TagColor.olive,
  DoableTagColor.green => TagColor.green,
  DoableTagColor.teal => TagColor.teal,
  DoableTagColor.blue => TagColor.blue,
  DoableTagColor.violet => TagColor.violet,
  DoableTagColor.purple => TagColor.purple,
  DoableTagColor.pink => TagColor.pink,
};

String tagColorLabel(AppLocalizations l10n, DoableTagColor? color) =>
    switch (color) {
      null => l10n.tagColorNone,
      DoableTagColor.brown => l10n.tagColorBrown,
      DoableTagColor.orange => l10n.tagColorOrange,
      DoableTagColor.olive => l10n.tagColorOlive,
      DoableTagColor.green => l10n.tagColorGreen,
      DoableTagColor.teal => l10n.tagColorTeal,
      DoableTagColor.blue => l10n.tagColorBlue,
      DoableTagColor.violet => l10n.tagColorViolet,
      DoableTagColor.purple => l10n.tagColorPurple,
      DoableTagColor.pink => l10n.tagColorPink,
    };
