import 'package:doable/src/intention/presentation/catalog/intention_tag_conditions_view_model.dart';

/// Число переключений, которыми нажатия в панели тегов задают условие с
/// [requirement] по тегу без условия: «должен отсутствовать» следует за
/// «должен быть». Каждое переключение начинает новую выдачу.
int tagConditionCycles(IntentionTagRequirement requirement) =>
    switch (requirement) {
      IntentionTagRequirement.mustBePresent => 1,
      IntentionTagRequirement.mustBeAbsent => 2,
    };
