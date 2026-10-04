import '../../../l10n/app_localizations.dart';
import '../application/favorite_order_command.dart';

/// Безопасный локализованный текст отказа перестановки избранных намерений.
///
/// Только выбирает текст по категории отказа: сообщение предъявляет общая
/// поверхность, а команда не повторяется. Текст понятен без Главной, потому
/// что отказ предъявляется независимо от выбранной корневой страницы.
String favoriteOrderFailureMessage(
  AppLocalizations localizations,
  FavoriteOrderCommandFailure failure,
) => switch (failure) {
  FavoriteOrderConflictFailure() => localizations.favoriteOrderConflict,
  FavoriteOrderInputFailure() => localizations.favoriteOrderInvalid,
  FavoriteOrderUnavailableFailure() => localizations.favoriteOrderUnavailable,
  FavoriteOrderCorruptionFailure() => localizations.favoriteOrderCorruption,
  FavoriteOrderUnexpectedFailure() => localizations.favoriteOrderUnexpected,
};
