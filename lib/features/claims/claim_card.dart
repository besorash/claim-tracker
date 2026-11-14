/// Claim card for the claims list: accident-type badge, vehicle plate first
/// and large, then customer, claim number and insurer, plus the status chip,
/// a status-colored side stripe and the follow-up badge. Notes are never
/// shown here; they belong to the details screen. With action callbacks the
/// card shows change-status / edit / delete buttons.
///
/// Selection mode: when [selection] is non-null the card renders a leading
/// checkbox driven by [onSelectionChanged] and hides the single-claim action
/// row — bulk actions own that state then.
library;

import 'package:flutter/material.dart';

import '../../core/constants/insurers.dart';
import '../../core/l10n/app_strings.dart';
import '../../core/models/claim.dart';
import '../../core/models/claim_status.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/time_utils.dart';
import '../../shared/widgets/modern.dart';
import '../../shared/widgets/status_chip.dart';

class ClaimCard extends StatelessWidget {
  const ClaimCard({
    super.key,
    required this.claim,
    this.onChangeStatus,
    this.onEdit,
    this.onDelete,
    this.dateNote,
    this.selection,
    this.onSelectionChanged,
  });

  final Claim claim;
  final VoidCallback? onChangeStatus;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  /// Optional date line (e.g. the date the list is sorted by).
  final String? dateNote;

  /// Selection mode: `true`/`false` = this claim's checked state, `null` =
  /// not in selection mode.
  final bool? selection;

  /// Toggles [claim]'s selection when in selection mode.
  final VoidCallback? onSelectionChanged;

  bool get _hasActions =>
      onChangeStatus != null || onEdit != null || onDelete != null;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ClaimStatusMeta status = ClaimStatus.byKey(claim.statusKey);
    final bool closed = status.isClosed;
    final DateTime? followUp = claim.nextFollowUpUtcMs;
    final DateTime nowUtc = DateTime.now().toUtc();
    final bool showFollowUp = followUp != null && !closed;
    final bool overdue = showFollowUp && followUp.isBefore(nowUtc);
    final String? plate = claim.vehiclePlate;
    final Color stripe = StatusPalette.accent(status.tone);
    final ColorScheme cs = theme.colorScheme;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(width: 5, color: stripe),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (selection != null) ...[
                          Checkbox(
                            key: Key('card-check-${claim.id}'),
                            value: selection ?? false,
                            onChanged: onSelectionChanged == null
                                ? null
                                : (_) => onSelectionChanged!(),
                            materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                          ),
                          const SizedBox(width: 4),
                        ],
                        IconBubble(
                          icon: AccidentVisual.icon(claim.accidentType),
                          color: AccidentVisual.color(claim.accidentType),
                          size: 50,
                          solid: true,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Plate always renders LTR (both EN and AR UIs)
                              // so a mixed-letter plate keeps its input order.
                              Directionality(
                                textDirection: TextDirection.ltr,
                                child: Text(
                                  plate ?? S.noPlate,
                                  key: const Key('card-plate'),
                                  textAlign: TextAlign.left,
                                  style: theme.textTheme.titleLarge?.copyWith(
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 0.5,
                                    color: plate == null
                                        ? AppTheme.muted(context)
                                        : null,
                                  ),
                                ),
                              ),
                              Text(
                                claim.customerName,
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        StatusChip(statusKey: claim.statusKey, compact: true),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        _InfoPill(
                          icon: Icons.tag_rounded,
                          label: '${S.claimNumberLabel}: ',
                          text: claim.claimNumberDisplay,
                        ),
                        if (claim.customerInsuranceCompany.isNotEmpty)
                          _InfoPill(
                            icon: Icons.shield_outlined,
                            text: Insurers.display(
                              claim.customerInsuranceCompany,
                            ),
                          ),
                      ],
                    ),
                    if (dateNote != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        dateNote!,
                        key: const Key('card-date-note'),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AppTheme.muted(context),
                        ),
                      ),
                    ],
                    if (showFollowUp) ...[
                      const SizedBox(height: 10),
                      Container(
                        // Test hook + semantic marker for the overdue state.
                        key: overdue
                            ? const Key('card-overdue-indicator')
                            : null,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: overdue
                              ? cs.errorContainer
                              : cs.primaryContainer.withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              overdue
                                  ? Icons.alarm_rounded
                                  : Icons.notifications_active_outlined,
                              size: 17,
                              color: overdue
                                  ? cs.onErrorContainer
                                  : cs.onPrimaryContainer,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                TimeUtils.followUpLabel(
                                  followUp,
                                  nowUtc: nowUtc,
                                ),
                                style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w700,
                                  color: overdue
                                      ? cs.onErrorContainer
                                      : cs.onPrimaryContainer,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    // Single-claim actions are hidden in selection mode.
                    if (selection == null && _hasActions) ...[
                      const SizedBox(height: 6),
                      Wrap(
                        alignment: WrapAlignment.end,
                        spacing: 2,
                        children: [
                          if (onChangeStatus != null)
                            TextButton.icon(
                              key: Key('card-status-${claim.id}'),
                              onPressed: onChangeStatus,
                              icon: const Icon(
                                Icons.swap_horiz_rounded,
                                size: 18,
                              ),
                              label: Text(S.changeStatus),
                            ),
                          if (onEdit != null)
                            TextButton.icon(
                              key: Key('card-edit-${claim.id}'),
                              onPressed: onEdit,
                              icon: const Icon(Icons.edit_rounded, size: 18),
                              label: Text(S.edit),
                            ),
                          if (onDelete != null)
                            TextButton.icon(
                              key: Key('card-delete-${claim.id}'),
                              onPressed: onDelete,
                              style: TextButton.styleFrom(
                                foregroundColor: cs.error,
                              ),
                              icon: const Icon(
                                Icons.delete_outline_rounded,
                                size: 18,
                              ),
                              label: Text(S.delete),
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoPill extends StatelessWidget {
  const _InfoPill({required this.icon, required this.text, this.label});

  final IconData icon;
  final String text;

  /// Optional muted prefix, kept as its own Text so the value stays a plain
  /// standalone string.
  final String? label;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.onSurface.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppTheme.muted(context)),
          const SizedBox(width: 4),
          if (label != null)
            Text(
              label!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppTheme.muted(context),
              ),
            ),
          Flexible(
            child: Text(
              text,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
