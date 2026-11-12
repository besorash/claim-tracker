/// Claim card for the claims list (spec §6) — a balanced subset: claim number,
/// customer name, submitted-to insurer and status chip. Notes are never shown
/// here; they belong to the details screen (spec §11).
library;

import 'package:flutter/material.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/models/claim.dart';
import '../../core/models/claim_status.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/time_utils.dart';
import '../../shared/widgets/status_chip.dart';

class ClaimCard extends StatelessWidget {
  const ClaimCard({super.key, required this.claim});

  final Claim claim;

  @override
  Widget build(BuildContext context) {
    final bool closed = ClaimStatus.isClosedKey(claim.statusKey);
    final DateTime? followUp = claim.nextFollowUpUtcMs;
    final DateTime nowUtc = DateTime.now().toUtc();
    final bool showFollowUp = followUp != null && !closed;
    final bool overdue = showFollowUp && followUp.isBefore(nowUtc);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        S.claimNumberLabel,
                        style: Theme.of(context).textTheme.labelSmall
                            ?.copyWith(color: AppTheme.muted(context)),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        claim.claimNumber,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 4),
                      Text(claim.customerName),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                StatusChip(statusKey: claim.statusKey, compact: true),
              ],
            ),
            if (claim.liabilityPercent != null) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  Icon(
                    Icons.percent,
                    size: 16,
                    color: AppTheme.muted(context),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '${S.liabilityPercentLabel}: '
                      '${claim.liabilityPercent!.toStringAsFixed(0)}%',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall
                          ?.copyWith(color: AppTheme.muted(context)),
                    ),
                  ),
                ],
              ),
            ],
            if (showFollowUp) ...[
              const SizedBox(height: 10),
              Container(
                // Test hook + semantic marker for the overdue state (spec §6).
                key: overdue ? const Key('card-overdue-indicator') : null,
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color:
                      (overdue
                              ? Theme.of(context).colorScheme.errorContainer
                              : Theme.of(context)
                                    .colorScheme
                                    .secondaryContainer)
                          .withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(
                      overdue ? Icons.alarm : Icons.schedule,
                      size: 16,
                      color: overdue
                          ? Theme.of(context).colorScheme.onErrorContainer
                          : Theme.of(context).colorScheme.onSecondaryContainer,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        TimeUtils.followUpLabel(followUp, nowUtc: nowUtc),
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: overdue
                              ? Theme.of(context).colorScheme.onErrorContainer
                              : Theme.of(context)
                                    .colorScheme
                                    .onSecondaryContainer,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
