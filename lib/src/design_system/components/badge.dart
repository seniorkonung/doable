import 'package:flutter/material.dart' hide Badge;

import '../doable_colors.dart';
import '../doable_icon.dart';
import '../doable_metrics.dart';
import '../doable_type.dart';

/// Тон иконки метки: `muted` — у коробки архива и у молнии архивированного
/// действия.
enum BadgeTone { ink, muted }

/// Метка рядом с названием, которая сообщает факт и не является кнопкой.
///
/// Варианты закрыты: у каждого есть значок, слово или оба сразу, а метки без
/// того и другого не существует.
sealed class Badge extends StatelessWidget {
  const Badge._({super.key});

  /// Метка-значок строки списка на заливке `fill`, поэтому её фон — `bg`.
  /// Узла экранного диктора у метки нет: факт называет доступное название
  /// строки.
  const factory Badge.mark({
    required DoableIconData icon,
    required BadgeTone tone,
    Key? key,
  }) = BadgeMark;

  /// Метка «Архив» после названия: слово [word] цвета `muted` на плоскости
  /// `fill` за коробкой архива. Диктор читает слово.
  const factory Badge.archived({required String word, Key? key}) =
      BadgeArchived;

  /// Та же метка в строке, которая не должна стать выше своего текста: без
  /// полей сверху и снизу, поэтому она высотой со строку слова при любом
  /// размере шрифта.
  const factory Badge.archivedInline({required String word, Key? key}) =
      BadgeArchived.inline;

  /// Метка «Удалено» после намерения или связи, удалённых после сохранения
  /// пути: слово [word] цвета `muted` на плоскости `fill` за значком корзины.
  /// Диктор читает слово.
  const factory Badge.deleted({required String word, Key? key}) = BadgeDeleted;

  /// Та же метка в строке, которая не должна стать выше своего текста: как
  /// [Badge.archivedInline].
  const factory Badge.deletedInline({required String word, Key? key}) =
      BadgeDeleted.inline;
}

/// Метка-значок: плитка 22×20 со значком [icon] тона [tone].
final class BadgeMark extends Badge {
  const BadgeMark({required this.icon, required this.tone, super.key})
    : super._();

  final DoableIconData icon;
  final BadgeTone tone;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<DoableColors>()!;

    return SizedBox(
      width: 22,
      height: 20,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.bg,
          borderRadius: BorderRadius.circular(DoableMetrics.radiusXs),
        ),
        child: Center(
          child: DoableIcon(
            icon,
            size: 14,
            color: switch (tone) {
              BadgeTone.ink => colors.ink,
              BadgeTone.muted => colors.muted,
            },
          ),
        ),
      ),
    );
  }
}

/// Метка архива: коробка архива и слово [word].
final class BadgeArchived extends Badge {
  const BadgeArchived({required this.word, super.key})
    : _verticalPadding = 1,
      super._();

  const BadgeArchived.inline({required this.word, super.key})
    : _verticalPadding = 0,
      super._();

  final String word;
  final double _verticalPadding;

  @override
  Widget build(BuildContext context) => _WordBadge(
    icon: DoableIconData.archive,
    word: word,
    verticalPadding: _verticalPadding,
  );
}

/// Метка удаления: корзина и слово [word].
final class BadgeDeleted extends Badge {
  const BadgeDeleted({required this.word, super.key})
    : _verticalPadding = 1,
      super._();

  const BadgeDeleted.inline({required this.word, super.key})
    : _verticalPadding = 0,
      super._();

  final String word;
  final double _verticalPadding;

  @override
  Widget build(BuildContext context) => _WordBadge(
    icon: DoableIconData.delete,
    word: word,
    verticalPadding: _verticalPadding,
  );
}

/// Слово `muted` на плоскости `fill` за значком [icon]: общий вид меток
/// архива и удаления.
final class _WordBadge extends StatelessWidget {
  const _WordBadge({
    required this.icon,
    required this.word,
    required this.verticalPadding,
  });

  final DoableIconData icon;
  final String word;
  final double verticalPadding;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<DoableColors>()!;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.fill,
        borderRadius: BorderRadius.circular(DoableMetrics.radiusXs),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(5, verticalPadding, 7, verticalPadding),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          spacing: DoableMetrics.space1,
          children: [
            DoableIcon(icon, size: 13, color: colors.muted),
            Text(
              word,
              maxLines: 1,
              softWrap: false,
              style: DoableType.caption.copyWith(color: colors.muted),
            ),
          ],
        ),
      ),
    );
  }
}
