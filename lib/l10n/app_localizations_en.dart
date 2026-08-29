// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Doable';

  @override
  String get navigationActiveIntentions => 'Active intentions';

  @override
  String get navigationArchive => 'Archive';

  @override
  String get commonLoading => 'Loading…';

  @override
  String get commonEmpty => 'Nothing here yet';

  @override
  String get commonError => 'Something went wrong';

  @override
  String get commonRetry => 'Try again';

  @override
  String get bootstrapLoading => 'Preparing local data…';

  @override
  String get bootstrapMigrationFailure =>
      'Local data couldn’t be prepared. Your data wasn’t changed. Try again.';

  @override
  String get bootstrapIncompatibleSchema =>
      'Install a compatible Doable update to continue.';
}
