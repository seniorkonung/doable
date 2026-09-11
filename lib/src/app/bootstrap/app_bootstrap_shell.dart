import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../app_runtime.dart';
import '../localization/app_locale_resolution.dart';

final class AppBootstrapShell extends StatefulWidget {
  const AppBootstrapShell({
    required this.runtime,
    required this.child,
    super.key,
  });

  final AppRuntime runtime;
  final Widget child;

  @override
  State<AppBootstrapShell> createState() => _AppBootstrapShellState();
}

final class _AppBootstrapShellState extends State<AppBootstrapShell> {
  late Future<AppRuntimeBootstrapResult> _bootstrapping;

  @override
  void initState() {
    super.initState();
    _bootstrapping = widget.runtime.bootstrap();
  }

  @override
  void didUpdateWidget(AppBootstrapShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.runtime, widget.runtime)) {
      _bootstrapping = widget.runtime.bootstrap();
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AppRuntimeBootstrapResult>(
      future: _bootstrapping,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const _BootstrapStatusApp(
            status: _BootstrapStatusKind.loading,
          );
        }

        final result = snapshot.data;
        if (snapshot.hasError || result == null) {
          return const _BootstrapStatusApp(
            status: _BootstrapStatusKind.unexpected,
          );
        }

        return switch (result) {
          AppRuntimeReady(:final container) => UncontrolledProviderScope(
            container: container,
            child: widget.child,
          ),
          AppRuntimeRetryableFailure() => _BootstrapStatusApp(
            status: _BootstrapStatusKind.retryable,
            onRetry: _retry,
          ),
          AppRuntimeCorruption() => const _BootstrapStatusApp(
            status: _BootstrapStatusKind.corruption,
          ),
          AppRuntimeIncompatibleSchema() => const _BootstrapStatusApp(
            status: _BootstrapStatusKind.incompatibleSchema,
          ),
          AppRuntimeUnexpectedFailure() => const _BootstrapStatusApp(
            status: _BootstrapStatusKind.unexpected,
          ),
        };
      },
    );
  }

  void _retry() {
    setState(() {
      _bootstrapping = widget.runtime.bootstrap();
    });
  }
}

enum _BootstrapStatusKind {
  loading,
  retryable,
  corruption,
  incompatibleSchema,
  unexpected,
}

final class _BootstrapStatusApp extends StatelessWidget {
  const _BootstrapStatusApp({required this.status, this.onRetry});

  final _BootstrapStatusKind status;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      onGenerateTitle: _appTitle,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      localeListResolutionCallback: resolveAppLocale,
      home: Builder(
        builder: (context) {
          final localizations = AppLocalizations.of(context);
          final message = switch (status) {
            _BootstrapStatusKind.loading => localizations.bootstrapLoading,
            _BootstrapStatusKind.retryable =>
              localizations.bootstrapMigrationFailure,
            _BootstrapStatusKind.corruption =>
              localizations.bootstrapCorruption,
            _BootstrapStatusKind.incompatibleSchema =>
              localizations.bootstrapIncompatibleSchema,
            _BootstrapStatusKind.unexpected =>
              localizations.bootstrapUnexpectedFailure,
          };
          return _BootstrapStatus(
            message: message,
            progressIndicator: status == _BootstrapStatusKind.loading,
            retryLabel: onRetry == null ? null : localizations.commonRetry,
            onRetry: onRetry,
          );
        },
      ),
    );
  }
}

final class _BootstrapStatus extends StatelessWidget {
  const _BootstrapStatus({
    required this.message,
    this.progressIndicator = false,
    this.retryLabel,
    this.onRetry,
  }) : assert((retryLabel == null) == (onRetry == null));

  final String message;
  final bool progressIndicator;
  final String? retryLabel;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Semantics(
              container: true,
              liveRegion: true,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (progressIndicator) ...[
                    const CircularProgressIndicator(),
                    const SizedBox(height: 24),
                  ],
                  Text(message, textAlign: TextAlign.center),
                  if (onRetry case final retry?) ...[
                    const SizedBox(height: 24),
                    FilledButton(onPressed: retry, child: Text(retryLabel!)),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

String _appTitle(BuildContext context) => AppLocalizations.of(context).appTitle;
