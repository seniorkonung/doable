import 'package:flutter/material.dart' hide Badge;

import '../doable_colors.dart';
import '../doable_icon.dart';
import '../doable_metrics.dart';
import '../doable_type.dart';

/// Тон иконки метки: `muted` — у коробки архива и у молнии архивированного
/// действия.
enum BadgeTone { ink, muted }

/// Метка рядом с названием, которая сообщает факт и не является кнопкой.
final class Badge extends StatelessWidget {
  /// Метка-значок строки списка на заливке `fill`, поэтому её фон — `bg`.
  /// Узла экранного диктора у метки нет: факт называет доступное название
  /// строки.
  const Badge.mark({
    required DoableIconData this.icon,
    required this.tone,
    super.key,
  }) : word = null;

  /// Метка «Архив» после названия: слово [word] цвета `muted` на плоскости
  /// `fill` за коробкой архива. Диктор читает слово.
  const Badge.archived({required String this.word, super.key})
    : icon = DoableIconData.archive,
      tone = BadgeTone.muted;

  /// Метка-слово строки списка: только слово [word] цвета `ink` на заливке
  /// `bg`, как у значковых меток строки, и оформленное одинаково при любом
  /// слове. Узла экранного диктора у метки нет: слово называет доступное
  /// название строки.
  const Badge.word({required String this.word, super.key})
    : icon = null,
      tone = BadgeTone.ink;

  /// Значок метки; у метки-слова его нет.
  final DoableIconData? icon;
  final BadgeTone tone;

  /// Слово метки; без него метка — значок без слова.
  final String? word;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<DoableColors>()!;

    return switch ((icon, word)) {
      (final icon?, final word?) => _archived(colors, icon, word),
      (null, final word?) => _word(colors, word),
      (final icon?, null) => _mark(colors, icon),
      (null, null) => throw StateError('У метки нет ни значка, ни слова'),
    };
  }

  Widget _mark(DoableColors colors, DoableIconData icon) => SizedBox(
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

  Widget _archived(DoableColors colors, DoableIconData icon, String word) =>
      DecoratedBox(
        decoration: BoxDecoration(
          color: colors.fill,
          borderRadius: BorderRadius.circular(DoableMetrics.radiusXs),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(5, 1, 7, 1),
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

  Widget _word(DoableColors colors, String word) => ExcludeSemantics(
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: colors.bg,
        borderRadius: BorderRadius.circular(DoableMetrics.radiusXs),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
        child: Text(
          word,
          maxLines: 1,
          softWrap: false,
          style: DoableType.caption.copyWith(color: colors.ink),
        ),
      ),
    ),
  );
}
