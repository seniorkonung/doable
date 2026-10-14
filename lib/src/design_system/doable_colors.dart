import 'package:flutter/material.dart';

/// Полный перечень цветов с исходными именами для каталога основ.
enum DoableColorToken {
  bg('bg'),
  bgFade('bg-fade'),
  fill('fill'),
  raised('raised'),
  hairline('hairline'),
  track('track'),
  ink('ink'),
  muted('muted'),
  grip('grip'),
  accent('accent'),
  onAccent('on-accent'),
  accentSoft('accent-soft'),
  p1('p1'),
  p2('p2'),
  p3('p3'),
  p4('p4'),
  danger('danger'),
  dangerSoft('danger-soft'),
  onDanger('on-danger'),
  scrim('scrim'),
  tagBrown('tag-brown'),
  tagOrange('tag-orange'),
  tagOlive('tag-olive'),
  tagGreen('tag-green'),
  tagTeal('tag-teal'),
  tagBlue('tag-blue'),
  tagViolet('tag-violet'),
  tagPurple('tag-purple'),
  tagPink('tag-pink');

  const DoableColorToken(this.tokenName);

  final String tokenName;

  DoableColorToken get _source => switch (this) {
    p1 || danger => accent,
    dangerSoft => accentSoft,
    onDanger => onAccent,
    bg ||
    bgFade ||
    fill ||
    raised ||
    hairline ||
    track ||
    ink ||
    muted ||
    grip ||
    accent ||
    onAccent ||
    accentSoft ||
    p2 ||
    p3 ||
    p4 ||
    scrim ||
    tagBrown ||
    tagOrange ||
    tagOlive ||
    tagGreen ||
    tagTeal ||
    tagBlue ||
    tagViolet ||
    tagPurple ||
    tagPink => this,
  };

  // Пара обязательна для каждого токена: светлое и тёмное значения.
  (Color, Color) get _palette => switch (this) {
    bg => (const Color(0xffffffff), const Color(0xff0b0b0d)),
    bgFade => (const Color(0x00ffffff), const Color(0x000b0b0d)),
    fill => (const Color(0xfff4f4f6), const Color(0xff1b1b1f)),
    raised => (const Color(0xffffffff), const Color(0xff232328)),
    hairline => (const Color(0xffe6e6ea), const Color(0xff2e2e34)),
    track => (
      const Color.from(
        alpha: 0.19,
        red: 142 / 255,
        green: 142 / 255,
        blue: 150 / 255,
      ),
      const Color.from(
        alpha: 0.19,
        red: 119 / 255,
        green: 119 / 255,
        blue: 127 / 255,
      ),
    ),
    ink => (const Color(0xff111114), const Color(0xfff4f4f6)),
    muted => (const Color(0xff6e6e76), const Color(0xffa0a0a8)),
    grip => (const Color(0xff8e8e96), const Color(0xff77777f)),
    accent => (const Color(0xffd12f2f), const Color(0xffff6a63)),
    onAccent => (const Color(0xffffffff), const Color(0xff1a0505)),
    accentSoft => (const Color(0xfffef2f2), const Color(0xff3a1618)),
    p1 || danger || dangerSoft || onDanger => _source._palette,
    p2 => (const Color(0xffc76a00), const Color(0xffffa133)),
    p3 => (const Color(0xff2f6fd1), const Color(0xff6ea8ff)),
    p4 => (const Color(0xff85858d), const Color(0xff77777f)),
    scrim => (const Color(0x47111114), const Color(0x80000000)),
    tagBrown => (const Color(0xff8a5841), const Color(0xffa27a60)),
    tagOrange => (const Color(0xffe06d00), const Color(0xfff59a23)),
    tagOlive => (const Color(0xff829403), const Color(0xffa9d24c)),
    tagGreen => (const Color(0xff0a6802), const Color(0xff2ea45a)),
    tagTeal => (const Color(0xff10888d), const Color(0xff45dccd)),
    tagBlue => (const Color(0xff0e49bc), const Color(0xff4a86f0)),
    tagViolet => (const Color(0xffaa6cf6), const Color(0xffb9b4ff)),
    tagPurple => (const Color(0xff7f199c), const Color(0xffa352cc)),
    tagPink => (const Color(0xffd6409a), const Color(0xffee68b8)),
  };
}

/// Палитра Doable; алиасы всегда следуют своим исходным цветам.
///
/// [ThemeExtension] связывает палитру с темой и её плавной сменой:
/// https://api.flutter.dev/flutter/material/ThemeExtension-class.html
final class DoableColors extends ThemeExtension<DoableColors> {
  DoableColors._(Color Function(DoableColorToken token) colorFor)
    : _colors = List.unmodifiable(
        DoableColorToken.values.map((token) => colorFor(token._source)),
      );

  static final light = DoableColors._((token) => token._palette.$1);
  static final dark = DoableColors._((token) => token._palette.$2);

  final List<Color> _colors;

  Color operator [](DoableColorToken token) => _colors[token._source.index];

  Color get bg => this[DoableColorToken.bg];
  Color get bgFade => this[DoableColorToken.bgFade];
  Color get fill => this[DoableColorToken.fill];
  Color get raised => this[DoableColorToken.raised];
  Color get hairline => this[DoableColorToken.hairline];
  Color get track => this[DoableColorToken.track];
  Color get ink => this[DoableColorToken.ink];
  Color get muted => this[DoableColorToken.muted];
  Color get grip => this[DoableColorToken.grip];
  Color get accent => this[DoableColorToken.accent];
  Color get onAccent => this[DoableColorToken.onAccent];
  Color get accentSoft => this[DoableColorToken.accentSoft];
  Color get p1 => accent;
  Color get p2 => this[DoableColorToken.p2];
  Color get p3 => this[DoableColorToken.p3];
  Color get p4 => this[DoableColorToken.p4];
  Color get danger => accent;
  Color get dangerSoft => accentSoft;
  Color get onDanger => onAccent;
  Color get scrim => this[DoableColorToken.scrim];
  Color get tagBrown => this[DoableColorToken.tagBrown];
  Color get tagOrange => this[DoableColorToken.tagOrange];
  Color get tagOlive => this[DoableColorToken.tagOlive];
  Color get tagGreen => this[DoableColorToken.tagGreen];
  Color get tagTeal => this[DoableColorToken.tagTeal];
  Color get tagBlue => this[DoableColorToken.tagBlue];
  Color get tagViolet => this[DoableColorToken.tagViolet];
  Color get tagPurple => this[DoableColorToken.tagPurple];
  Color get tagPink => this[DoableColorToken.tagPink];

  /// Все токены, включая алиасы, в порядке дизайн-системы.
  List<({String name, Color color})> get entries => List.unmodifiable([
    for (final token in DoableColorToken.values)
      (name: token.tokenName, color: this[token]),
  ]);

  /// Заменяет цвета, для которых [colorFor] возвращает ненулевое значение.
  ///
  /// Функция получает исходные токены, а алиасы вычисляются из результата.
  /// Все значения сохраняются сразу, без зависимости от дальнейших вызовов.
  @override
  DoableColors copyWith({Color? Function(DoableColorToken token)? colorFor}) {
    if (colorFor == null) return this;
    return DoableColors._((token) => colorFor(token) ?? this[token]);
  }

  @override
  DoableColors lerp(covariant DoableColors? other, double t) {
    if (other == null) return this;
    return DoableColors._((token) => Color.lerp(this[token], other[token], t)!);
  }
}
