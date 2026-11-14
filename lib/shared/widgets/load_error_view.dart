/// Shared "load failed" state (spec §3.3 — no silent failures): shown when a
/// screen's initial data load throws (e.g. the database handle was closed
/// mid-load during a restore swap). Offers an explicit retry instead of a red
/// error screen, and never leaks raw exception text to the user.
library;

import 'package:flutter/material.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/theme/app_theme.dart';

class LoadErrorView extends StatelessWidget {
  const LoadErrorView({super.key, required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.cloud_off_outlined,
              size: 48,
              color: AppTheme.muted(context),
            ),
            const SizedBox(height: 12),
            Text(
              S.loadFailed,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              key: const Key('load-error-retry'),
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: Text(S.retry),
            ),
          ],
        ),
      ),
    );
  }
}
