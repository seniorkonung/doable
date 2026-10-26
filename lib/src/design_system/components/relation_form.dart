import 'package:flutter/material.dart';

import '../doable_colors.dart';
import '../doable_metrics.dart';
import '../doable_type.dart';
import 'path_glyph.dart';
import 'path_rail.dart';
import 'relation_stroke.dart';

/// Поле формы связи: исходное намерение стоит первым, связанное — вторым.
enum RelationFormRole { source, related }

/// Вид связи на линии между полями.
enum RelationFormKind { need, can, undetermined }

/// Состояние поля формы связи.
sealed class RelationFormField {
  const RelationFormField();
}

/// Поле, участника которого выбирают сейчас.
final class RelationFieldChoosing extends RelationFormField {
  const RelationFieldChoosing({this.replacing});

  /// Название прежнего участника этой роли, если поле уже было заполнено.
  final String? replacing;
}

/// Поле, которое форма только показывает.
sealed class RelationFieldShown extends RelationFormField {
  const RelationFieldShown();
}

final class RelationFieldFilled extends RelationFieldShown {
  const RelationFieldFilled(this.name, {this.archived = false});

  final String name;
  final bool archived;
}

final class RelationFieldEmpty extends RelationFieldShown {
  const RelationFieldEmpty();
}

/// Готовые тексты формы связи.
final class RelationFormTexts {
  const RelationFormTexts({
    required this.sourceRole,
    required this.relatedRole,
    required this.choosingNow,
    required this.fromList,
    required this.replacing,
    required this.notChosen,
    required this.archived,
    required this.kind,
  });

  /// Названия ролей полей для экранного диктора.
  final String sourceRole;
  final String relatedRole;

  /// Подпись над текстом выбираемого поля, например «Сейчас выбирается».
  final String choosingNow;

  /// Текст выбираемого поля без прежнего участника.
  final String fromList;

  /// Текст выбираемого поля с прежним участником, например «Вместо: …».
  final String Function(String name) replacing;

  /// Текст пустого поля.
  final String notChosen;

  /// Признак архивного участника для экранного диктора.
  final String archived;

  /// Слово вида связи.
  final String kind;
}

/// Связь, нарисованная на рейке пути: исходное намерение, строка вида и
/// связанное намерение сверху вниз.
final class RelationForm extends StatelessWidget {
  /// Форма только для чтения, в которой поле [role] выбирается сейчас.
  /// Нажатий и шевронов у неё нет.
  const RelationForm.choosing({
    required this.role,
    required this.chosen,
    required this.other,
    required this.kind,
    required this.texts,
    super.key,
  });

  final RelationFormRole role;
  final RelationFieldChoosing chosen;

  /// Поле другой роли.
  final RelationFieldShown other;
  final RelationFormKind kind;
  final RelationFormTexts texts;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<DoableColors>()!;
    final stroke = switch (kind) {
      RelationFormKind.need => RelationStrokeKind.need(colors.grip),
      RelationFormKind.can => RelationStrokeKind.can(colors.grip),
      RelationFormKind.undetermined => const RelationStrokeKind.undetermined(),
    };
    final (
      RelationFormField source,
      RelationFormField related,
    ) = switch (role) {
      RelationFormRole.source => (chosen, other),
      RelationFormRole.related => (other, chosen),
    };

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _FieldRow(
          shape: PathGlyphShape.diamond,
          below: stroke,
          roleLabel: texts.sourceRole,
          field: source,
          texts: texts,
        ),
        _KindRow(stroke: stroke, word: texts.kind, kind: kind),
        _FieldRow(
          shape: PathGlyphShape.ring,
          above: stroke,
          roleLabel: texts.relatedRole,
          field: related,
          texts: texts,
        ),
      ],
    );
  }
}

const _glyphSize = 14.0;
const _fieldMinHeight = 48.0;
const _fieldGap = 10.0;
const _fieldPadding = EdgeInsets.symmetric(vertical: 13, horizontal: 14);
const _fieldTextGap = 2.0;
const _choosingRingWidth = 1.5;
const _kindRowHeight = 52.0;
const _kindGap = 24.0;
const _kindMarkGap = 7.0;

final class _FieldRow extends StatelessWidget {
  const _FieldRow({
    required this.shape,
    required this.roleLabel,
    required this.field,
    required this.texts,
    this.above,
    this.below,
  });

  final PathGlyphShape shape;
  final RelationStrokeKind? above;
  final RelationStrokeKind? below;
  final String roleLabel;
  final RelationFormField field;
  final RelationFormTexts texts;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<DoableColors>()!;
    final (outline, glyphColor) = switch (field) {
      RelationFieldChoosing() => (PathGlyphOutline.dashed, colors.accent),
      RelationFieldEmpty() => (PathGlyphOutline.dashed, colors.grip),
      RelationFieldFilled() => (PathGlyphOutline.solid, colors.grip),
    };
    final faint = DoableType.action.copyWith(
      fontWeight: FontWeight.w400,
      color: colors.muted,
    );
    final (caption, text, style) = switch (field) {
      RelationFieldChoosing(:final replacing) => (
        texts.choosingNow,
        replacing == null ? texts.fromList : texts.replacing(replacing),
        faint,
      ),
      RelationFieldFilled(:final name, :final archived) => (
        null,
        name,
        DoableType.action.copyWith(
          fontWeight: FontWeight.w500,
          color: archived ? colors.muted : colors.ink,
        ),
      ),
      RelationFieldEmpty() => (null, texts.notChosen, faint),
    };
    final archived = switch (field) {
      RelationFieldFilled(:final archived) => archived,
      RelationFieldChoosing() || RelationFieldEmpty() => false,
    };
    final choosing = field is RelationFieldChoosing;

    return PathRail(
      mark: PathRailMark.glyph(
        PathGlyph(
          shape: shape,
          outline: outline,
          size: _glyphSize,
          color: glyphColor,
        ),
        above: above,
        below: below,
      ),
      child: Padding(
        padding: const EdgeInsets.only(left: _fieldGap),
        // Поле читается одним узлом без действия: роль, состояние и
        // название участника, а у архивного — ещё и архивность.
        child: Semantics(
          container: true,
          excludeSemantics: true,
          label: [
            roleLabel,
            ?caption,
            text,
            if (archived) texts.archived,
          ].join('\n'),
          // Кольцо выбираемого поля внутреннее, как в макете: оно не
          // сдвигает текст.
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: choosing ? colors.accentSoft : colors.fill,
              borderRadius: BorderRadius.circular(DoableMetrics.radiusLg),
              border: choosing
                  ? Border.all(color: colors.accent, width: _choosingRingWidth)
                  : null,
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: _fieldMinHeight),
              child: Padding(
                padding: _fieldPadding,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: _fieldTextGap,
                  children: [
                    if (caption != null)
                      Text(
                        caption,
                        style: DoableType.label.copyWith(color: colors.accent),
                      ),
                    Text(text, style: style),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

final class _KindRow extends StatelessWidget {
  const _KindRow({
    required this.stroke,
    required this.word,
    required this.kind,
  });

  final RelationStrokeKind stroke;
  final String word;
  final RelationFormKind kind;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<DoableColors>()!;
    return PathRail(
      mark: PathRailMark.stroke(stroke),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: _kindRowHeight),
        child: Padding(
          padding: const EdgeInsets.only(left: _kindGap),
          child: Row(
            spacing: _kindMarkGap,
            children: [
              RelationKindMark(kind: stroke),
              Flexible(
                child: Text(
                  word,
                  style: DoableType.section.copyWith(
                    color: switch (kind) {
                      RelationFormKind.need ||
                      RelationFormKind.can => colors.ink,
                      RelationFormKind.undetermined => colors.muted,
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
