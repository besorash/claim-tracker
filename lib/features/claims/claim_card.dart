/// Claim card for the claims list (spec §6): vehicle plate first and large,
/// then the customer name, then the claim number, plus the status chip and
/// the follow-up badge. Notes are never shown here; they belong to the
/// details screen (spec §11). When action callbacks are given, the card shows
/// change-status / edit / delete buttons so the claim can be handled without
/// opening it.
library;

import 'package:flutter/material.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/models/claim.dart';
import '../../core/models/claim_status.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/time_utils.dart';
import '../../shared/widgets/status_chip.dart';

class ClaimCard extends StatelessWidget {
  const ClaimCard({
    super.key,
    required this.claim,
    this.onChangeStatus,
    this.onEdit,
    this.onDelete,
    this.dateNote,
  });

  final Claim claim;
  final VoidCallback? onChangeStatus;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  /// Optional date line (e.g. the date the list is sorted by).
  final String? dateNote;

  bool get _hasActions =>
      onChangeStatus != null || onEdit != null || onDelete != null;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool closed = ClaimStatus.isClosedKey(claim.statusKey);
    final DateTime? followUp = claim.nextFollowUpUtcMs;
    final DateTime nowUtc = DateTime.now().toUtc();
    final bool showFollowUp = followUp != null && !closed;
    final bool overdue = showFollowUp && followUp.isBefore(nowUtc);
    final String? plate = claim.vehiclePlate;

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
                        plate ?? S.noPlate,
                        key: const Key('card-plate'),
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: plate == null ? AppTheme.muted(context) : null,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        claim.customerName,
                        style: theme.textTheme.titleMedium,
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Text(
                            '${S.claimNumberLabel}: ',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: AppTheme.muted(context),
                            ),
                          ),
                          Flexible(
                            child: Text(
                              claim.claimNumber,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (dateNote != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          dateNote!,
                          key: const Key('card-date-note'),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: AppTheme.muted(context),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                StatusChip(statusKey: claim.statusKey, compact: true),
              ],
            ),
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
            if (_hasActions) ...[
              const SizedBox(height: 6),
              const Divider(height: 12),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: 4,
                children: [
                  if (onChangeStatus != null)
                    TextButton.icon(
                      key: Key('card-status-${claim.id}'),
                      onPressed: onChangeStatus,
                      icon: const Icon(Icons.swap_horiz, size: 18),
                      label: Text(S.changeStatus),
                    ),
                  if (onEdit != null)
                    TextButton.icon(
                      key: Key('card-edit-${claim.id}'),
                      onPressed: onEdit,
                      icon: const Icon(Icons.edit_outlined, size: 18),
                      label: Text(S.edit),
                    ),
                  if (onDelete != null)
                    TextButton.icon(
                      key: Key('card-delete-${claim.id}'),
                      onPressed: onDelete,
                      style: TextButton.styleFrom(
                        foregroundColor: theme.colorScheme.error,
                      ),
                      icon: const Icon(Icons.delete_outline, size: 18),
                      label: Text(S.delete),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
