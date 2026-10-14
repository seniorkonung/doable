import 'package:flutter/painting.dart';

enum _DoableTypeToken {
  display('display', 30, 36, FontWeight.w700, -0.75),
  pageTitle('page-title', 24, 30, FontWeight.w700, -0.48),
  headline('headline', 20, 26, FontWeight.w600, -0.3),
  number('number', 18, 22, FontWeight.w500, 0),
  title('title', 17, 22, FontWeight.w600, -0.17),
  action('action', 16, 22, FontWeight.w500, -0.16),
  field('field', 16, 22, FontWeight.w400, 0),
  section('section', 15, 20, FontWeight.w600, -0.15),
  row('row', 15, 20, FontWeight.w500, 0),
  body('body', 15, 20, FontWeight.w400, 0),
  note('note', 14, 20, FontWeight.w400, 0),
  caption('caption', 13, 18, FontWeight.w500, 0),
  hint('hint', 13, 18, FontWeight.w400, 0),
  label('label', 13, 18, FontWeight.w600, 0);

  const _DoableTypeToken(
    this.tokenName,
    this.fontSize,
    this.lineHeight,
    this.fontWeight,
    this.letterSpacing,
  );

  final String tokenName;
  final double fontSize;
  final double lineHeight;
  final FontWeight fontWeight;
  final double letterSpacing;

  TextStyle get style => TextStyle(
    fontFamily: 'Inter',
    fontSize: fontSize,
    height: lineHeight / fontSize,
    leadingDistribution: TextLeadingDistribution.even,
    letterSpacing: letterSpacing,
    fontWeight: fontWeight,
    fontVariations: List.unmodifiable([FontVariation.opticalSize(fontSize)]),
  );
}

/// Стили Inter без цвета; межбуквенные интервалы переведены в логические пиксели.
///
/// Оптический размер следует кеглю макета:
/// https://api.flutter.dev/flutter/dart-ui/FontVariation/FontVariation.opticalSize.html
/// Вес задаётся только через [FontWeight], чтобы его можно было менять через
/// [TextStyle.copyWith], в том числе на 650:
/// https://api.flutter.dev/flutter/dart-ui/FontWeight-class.html
/// Равномерное распределение межстрочного интервала повторяет CSS:
/// https://api.flutter.dev/flutter/painting/TextStyle/leadingDistribution.html
abstract final class DoableType {
  static final display = _DoableTypeToken.display.style;
  static final pageTitle = _DoableTypeToken.pageTitle.style;
  static final headline = _DoableTypeToken.headline.style;
  static final number = _DoableTypeToken.number.style;
  static final title = _DoableTypeToken.title.style;
  static final action = _DoableTypeToken.action.style;
  static final field = _DoableTypeToken.field.style;
  static final section = _DoableTypeToken.section.style;
  static final row = _DoableTypeToken.row.style;
  static final body = _DoableTypeToken.body.style;
  static final note = _DoableTypeToken.note.style;
  static final caption = _DoableTypeToken.caption.style;
  static final hint = _DoableTypeToken.hint.style;
  static final label = _DoableTypeToken.label.style;

  /// Все стили с исходными именами в порядке дизайн-системы.
  static final List<({String name, TextStyle style})> entries =
      List.unmodifiable([
        for (final token in _DoableTypeToken.values)
          (name: token.tokenName, style: token.style),
      ]);
}
