import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../app_runtime.dart';

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
        final localizations = AppLocalizations.of(context);
        if (snapshot.connectionState != ConnectionState.done) {
          return _BootstrapStatus(
            message: localizations.bootstrapLoading,
            progressIndicator: true,
          );
        }

        final result = snapshot.data;
        if (snapshot.hasError || result == null) {
          return _BootstrapStatus(
            message: localizations.bootstrapUnexpectedFailure,
          );
        }

        return switch (result) {
          AppRuntimeReady(:final container) => UncontrolledProviderScope(
            container: container,
            child: widget.child,
          ),
          AppRuntimeRetryableFailure() => _BootstrapStatus(
            message: localizations.bootstrapMigrationFailure,
            retryLabel: localizations.commonRetry,
            onRetry: _retry,
          ),
          AppRuntimeCorruption() => _BootstrapStatus(
            message: localizations.bootstrapCorruption,
          ),
          AppRuntimeIncompatibleSchema() => _BootstrapStatus(
            message: localizations.bootstrapIncompatibleSchema,
          ),
          AppRuntimeUnexpectedFailure() => _BootstrapStatus(
            message: localizations.bootstrapUnexpectedFailure,
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
