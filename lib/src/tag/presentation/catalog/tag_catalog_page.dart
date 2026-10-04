import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';

import '../../../app/routing/app_router.gr.dart';
import '../../domain/tag.dart';
import '../../../intention/domain/intention_id.dart';
import 'tag_catalog_view.dart';
import 'tag_selection_context.dart';

@RoutePage()
final class TagCatalogPage extends StatelessWidget {
  const TagCatalogPage({this.intentionId, super.key});

  final IntentionId? intentionId;

  @override
  Widget build(BuildContext context) => TagCatalogView(
    selectionContext: switch (intentionId) {
      null => const TagBrowseContext(),
      final intentionId => TagAssignmentContext(intentionId),
    },
    onOpenEditor: (editorContext) =>
        context.router.push<Tag>(TagEditorRoute(editorContext: editorContext)),
    onOpenNavigation: (tagId) =>
        unawaited(context.router.push<void>(TagNavigationRoute(tagId: tagId))),
  );
}
