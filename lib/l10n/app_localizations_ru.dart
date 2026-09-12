// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Russian (`ru`).
class AppLocalizationsRu extends AppLocalizations {
  AppLocalizationsRu([String locale = 'ru']) : super(locale);

  @override
  String get appTitle => 'Doable';

  @override
  String get navigationActiveIntentions => 'Активные намерения';

  @override
  String get navigationArchive => 'Архив';

  @override
  String get commonLoading => 'Загрузка…';

  @override
  String get commonEmpty => 'Пока здесь ничего нет';

  @override
  String get commonError => 'Что-то пошло не так';

  @override
  String get commonRetry => 'Повторить';

  @override
  String get bootstrapLoading => 'Подготавливаем локальные данные…';

  @override
  String get bootstrapMigrationFailure =>
      'Не удалось подготовить локальные данные. Данные не изменены. Повторите попытку.';

  @override
  String get bootstrapCorruption =>
      'Локальные данные повреждены и не могут быть открыты.';

  @override
  String get bootstrapIncompatibleSchema =>
      'Чтобы продолжить, установите совместимое обновление Doable.';

  @override
  String get bootstrapUnexpectedFailure =>
      'Не удалось открыть локальные данные из-за непредвиденной ошибки.';

  @override
  String get catalogLoading => 'Загружаем намерения…';

  @override
  String get catalogTitle => 'Намерения';

  @override
  String get catalogScopeLabel => 'Охват';

  @override
  String get catalogScopeActive => 'Активные';

  @override
  String get catalogScopeArchived => 'Архивные';

  @override
  String get catalogScopeAll => 'Все';

  @override
  String get catalogFilterLabel => 'Фильтр по названию';

  @override
  String get catalogFilterInvalidUnicode =>
      'Введите корректный Unicode-текст без NUL.';

  @override
  String get catalogFilterTooLong => 'Используйте не более 255 символов.';

  @override
  String get catalogOrderLabel => 'Порядок';

  @override
  String get catalogOrderCreatedNewest => 'По созданию: сначала новые';

  @override
  String get catalogOrderCreatedOldest => 'По созданию: сначала старые';

  @override
  String get catalogOrderUpdatedNewest => 'По изменению: сначала новые';

  @override
  String get catalogOrderUpdatedOldest => 'По изменению: сначала старые';

  @override
  String catalogTotalCount(int count) {
    return 'Всего намерений: $count';
  }

  @override
  String get catalogActiveEmpty => 'Активных намерений пока нет.';

  @override
  String get catalogArchivedEmpty => 'Архивных намерений пока нет.';

  @override
  String get catalogAllEmpty => 'Намерений пока нет.';

  @override
  String get catalogUnavailable =>
      'Не удалось загрузить намерения. Повторите попытку.';

  @override
  String get catalogCorruption =>
      'Сохранённые данные намерений повреждены и не могут быть показаны.';

  @override
  String get catalogUnexpectedFailure =>
      'Не удалось загрузить намерения из-за непредвиденной ошибки.';

  @override
  String get catalogLoadingMore => 'Загружаем ещё намерения…';

  @override
  String get catalogLoadMoreUnavailable =>
      'Не удалось загрузить следующие намерения.';

  @override
  String get catalogLoadMoreCorruption =>
      'Сохранённые данные повреждены; следующие намерения нельзя показать.';

  @override
  String get catalogLoadMoreUnexpected =>
      'Не удалось загрузить следующие намерения из-за непредвиденной ошибки.';

  @override
  String get catalogLoadMoreValidation =>
      'Сохранённая позиция каталога больше недействительна.';

  @override
  String get catalogReload => 'Перезагрузить каталог';

  @override
  String get catalogReloading => 'Перезагружаем каталог…';

  @override
  String get catalogReady => 'Готово к действию';

  @override
  String get catalogNotReady => 'Не готово к действию';

  @override
  String get catalogHasDescription => 'Есть описание';

  @override
  String get catalogNoDescription => 'Нет описания';
}
