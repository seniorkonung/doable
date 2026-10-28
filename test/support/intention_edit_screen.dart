import 'package:doable/src/design_system/components/button.dart';
import 'package:doable/src/design_system/components/top_bar.dart';
import 'package:doable/src/intention/presentation/edit/intention_edit_page.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Название в шапке страницы намерения: нажатие открывает экран изменения.
final intentionHeadTitle = find.byKey(
  const ValueKey('intention-details-title'),
);

final intentionEditTitleField = find.byKey(
  const ValueKey('intention-edit-title'),
);

final intentionEditDescriptionField = find.byKey(
  const ValueKey('intention-edit-description'),
);

/// «Сохранить» в верхней панели экрана изменения намерения.
final intentionEditSave = find.descendant(
  of: find.descendant(
    of: find.byType(IntentionEditPage),
    matching: find.byType(TopBar),
  ),
  matching: find.byType(Button),
);
