import 'package:doable/src/favorite/application/favorite_intentions.dart';

/// Подставляет отказ чтения списка избранных намерений в тестовые графы,
/// которые не проверяют избранное.
mixin FavoriteReadContractTestFallback implements FavoriteReadContract {
  @override
  Future<FavoriteIntentionsResult> getFavoriteIntentions() async =>
      const FavoriteIntentionsError(FavoriteIntentionsUnexpectedFailure());
}
