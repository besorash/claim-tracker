/// Dialogs shared by the claim details screen and the claims list, so a
/// status change or a delete works the same from either place.
library;

import 'package:flutter/material.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/models/claim.dart';
import '../../core/models/claim_status.dart';
import 'claim_actions.dart';

/// What the user chose in the status-change dialog.
class StatusChangeRequest {
  const StatusChangeRequest({
    required this.statusKey,
    required this.followUp,
    this.note,
  });

  final String statusKey;
  final String? note;
  final FollowUpChange followUp;
}

/// Status-change dialog (spec §9): new status + optional note + an explicit
/// follow-up decision (keep / set / clear). [onSave] runs before the dialog
/// closes, so it stays open if the write fails.
Future<void> showChangeStatusDialog(
  BuildContext context, {
  required Claim claim,
  required Future<void> Function(StatusChangeRequest request) onSave,
}) {
  String selectedKey = claim.statusKey;
  String note = '';
  int followUpChoice = 0; // 0 = keep, 1 = set new, 2 = clear

  return showDialog<void>(
    context: context,
    builder: (BuildContext ctx) => StatefulBuilder(
      builder: (BuildContext ctx, StateSetter setDialogState) => AlertDialog(
        title: Text(S.changeStatusTitle),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DropdownButton<String>(
                value: selectedKey,
                isExpanded: true,
                items: ClaimStatus.all
                    .map(
                      (meta) => DropdownMenuItem<String>(
                        value: meta.key,
                        child: Text(meta.label),
                      ),
                    )
                    .toList(),
                onChanged: (String? key) {
                  if (key != null) setDialogState(() => selectedKey = key);
                },
              ),
              const SizedBox(height: 16),
              TextField(
                key: const Key('status-note'),
                decoration: InputDecoration(hintText: S.statusNoteHint),
                onChanged: (String value) => note = value,
              ),
              const SizedBox(height: 8),
              RadioGroup<int>(
                groupValue: followUpChoice,
                onChanged: (int? v) {
                  if (v != null) setDialogState(() => followUpChoice = v);
                },
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    RadioListTile<int>(
                      title: Text(S.keepExistingFollowUp),
                      secondary: const Icon(Icons.event_available_outlined),
                      value: 0,
                    ),
                    RadioListTile<int>(
                      title: Text(S.setNextFollowUp),
                      secondary: const Icon(Icons.event_outlined),
                      value: 1,
                    ),
                    RadioListTile<int>(
                      title: Text(S.clearFollowUp),
                      secondary: const Icon(Icons.event_busy_outlined),
                      value: 2,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(S.cancel),
          ),
          FilledButton(
            onPressed: () async {
              // Pick the follow-up date/time BEFORE dismissing, so the
              // dialog stays open if the user cancels the pickers.
              FollowUpChange change = const KeepFollowUp();
              if (followUpChoice == 1) {
                final DateTime now = DateTime.now().toUtc();
                final DateTime? d = await showDatePicker(
                  context: ctx,
                  initialDate: (claim.nextFollowUpUtcMs ?? now).toLocal(),
                  firstDate: DateTime(now.year - 1),
                  lastDate: DateTime(now.year + 5),
                );
                if (d == null || !ctx.mounted) return;
                final TimeOfDay? t = await showTimePicker(
                  context: ctx,
                  initialTime: TimeOfDay.fromDateTime(d.toLocal()),
                );
                if (t == null || !ctx.mounted) return;
                change = SetFollowUp(
                  DateTime(d.year, d.month, d.day, t.hour, t.minute).toUtc(),
                );
              } else if (followUpChoice == 2) {
                change = const ClearFollowUp();
              }
              // Persist FIRST, then dismiss — the dialog stays open if the
              // write fails (same principle as the form's self-pop).
              await onSave(
                StatusChangeRequest(
                  statusKey: selectedKey,
                  note: note.isEmpty ? null : note,
                  followUp: change,
                ),
              );
              if (!ctx.mounted) return;
              Navigator.of(ctx).pop();
            },
            child: Text(S.save),
          ),
        ],
      ),
    ),
  );
}

/// Delete confirmation. Returns true only when the user confirmed.
Future<bool> confirmDeleteClaim(BuildContext context) async {
  final bool? confirmed = await showDialog<bool>(
    context: context,
    builder: (BuildContext ctx) => AlertDialog(
      title: Text(S.deleteClaimTitle),
      content: Text(S.deleteClaimBody),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: Text(S.cancel),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            foregroundColor: Theme.of(ctx).colorScheme.error,
            backgroundColor: Theme.of(ctx).colorScheme.errorContainer,
          ),
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text(S.confirm),
        ),
      ],
    ),
  );
  return confirmed == true;
}

/// Bulk-delete confirmation for the claims list's selection mode. Like
/// [confirmDeleteClaim] it returns true only when confirmed — but names the
/// exact number of claims about to be removed so a large accidental selection
/// is visible before it is gone.
Future<bool> confirmDeleteClaims(BuildContext context, int count) async {
  final bool? confirmed = await showDialog<bool>(
    context: context,
    builder: (BuildContext ctx) => AlertDialog(
      title: Text(S.deleteClaimsTitle(count)),
      content: Text(S.deleteClaimsBody),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: Text(S.cancel),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            foregroundColor: Theme.of(ctx).colorScheme.error,
            backgroundColor: Theme.of(ctx).colorScheme.errorContainer,
          ),
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text(S.confirm),
        ),
      ],
    ),
  );
  return confirmed == true;
}
