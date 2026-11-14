/// Status chip — always shows the localized status label, color is semantic
/// only (spec §8: never rely on color alone).
library;

import 'package:flutter/material.dart';

import '../../core/models/claim_status.dart';
import '../../core/theme/app_theme.dart';

class StatusChip extends StatelessWidget {
  const StatusChip({super.key, required this.statusKey, this.compact = false});

  final String statusKey;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final ClaimStatusMeta meta = ClaimStatus.byKey(statusKey);
    final StatusChipColors colors = StatusPalette.forTone(
      meta.tone,
      Theme.of(context).brightness,
    );

    return Container(
      padding: compact
          ? const EdgeInsets.symmetric(horizontal: 10, vertical: 4)
          : const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        meta.label,
        style: TextStyle(
          color: colors.foreground,
          fontSize: compact ? 12 : 13,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
