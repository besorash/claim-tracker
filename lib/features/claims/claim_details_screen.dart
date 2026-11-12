/// Claim details screen (spec §11): read-only sections for customer, accident,
/// claim and follow-up information plus the actions — Edit, Delete with
/// explicit confirmation, and the Phase-3 status-change flow. Per spec §3.3 no
/// non-functional buttons are shown here.
library;

import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/database/app_database.dart';
import '../../core/database/attachments_repository.dart';
import '../../core/database/claims_repository.dart';
import '../../core/database/reminders_repository.dart';
import '../../core/database/status_history_repository.dart';
import '../../core/l10n/app_strings.dart';
import '../../core/models/attachment.dart';
import '../../core/models/claim.dart';
import '../../core/models/claim_status.dart';
import '../../core/models/reminder.dart';
import '../../core/models/status_history_entry.dart';
import '../../core/theme/app_theme.dart';
import '../../core/notifications/notification_service.dart';
import '../../core/notifications/reminder_scheduler.dart';
import '../../core/utils/time_utils.dart';
import '../../shared/widgets/status_chip.dart';
import '../attachments/attachment_file_service.dart';
import '../attachments/attachment_picker_seam.dart';
import 'claim_actions.dart';
import 'claim_form_screen.dart';

class ClaimDetailsScreen extends StatefulWidget {
  const ClaimDetailsScreen({
    super.key,
    required this.db,
    required this.claimId,
    this.scheduler,
    this.picker,
    this.files,
    this.openExternal,
  });

  final AppDatabase db;
  final int claimId;

  /// OS-side scheduling seam (spec §10). Defaults to the production service;
  /// widget tests inject a recording fake so no method channels are touched.
  final ReminderScheduler? scheduler;

  /// File-picker seam (spec §12); defaults to the real OS picker in
  /// production, and widget tests inject a fake that returns synthetic files.
  final AttachmentPicker? picker;

  /// Physical file service for attachments (spec §12). When null it is
  /// resolved lazily from the app documents directory on first use — host
  /// widget tests avoid path_provider method channels by injecting an
  /// instance backed by a temp directory.
  final AttachmentFileService? files;

  /// Opens non-image attachments in an external app (spec §12). Defaults to
  /// url_launcher; widget tests inject a stub reporting success/failure.
  final Future<bool> Function(Uri)? openExternal;

  @override
  State<ClaimDetailsScreen> createState() => _ClaimDetailsScreenState();
}

class _ClaimDetailsScreenState extends State<ClaimDetailsScreen> {
  ClaimsRepository get _repo => ClaimsRepository(widget.db);

  /// Orchestration for every mutation flow (spec §9–§12) — screens stay
  /// router-free and testable through the injected seams.
  ClaimActions get _actions => ClaimActions(
    widget.db,
    widget.scheduler ?? NotificationService.instance,
    files: widget.files ?? _resolvedFiles,
  );

  Claim? _claim;
  List<StatusHistoryEntry> _history = const [];
  Reminder? _reminder;
  List<Attachment> _attachments = const [];
  bool _loaded = false;

  /// Relative paths whose physical file is missing from the store (spec §12) —
  /// computed at load time so rows can flag them without per-tap I/O.
  Set<String> _missingPaths = const {};

  /// Lazily-resolved file service: only resolved when the claim actually has
  /// attachments, so attachment-less claims never touch path_provider (which
  /// keeps host widget tests free of method channels).
  AttachmentFileService? _resolvedFiles;

  Future<AttachmentFileService?> _ensureFiles() async {
    final AttachmentFileService? injected = widget.files;
    if (injected != null) return injected;
    final AttachmentFileService? cached = _resolvedFiles;
    if (cached != null) return cached;
    final Directory dir = await const AttachmentFileService().storeDir();
    _resolvedFiles = AttachmentFileService(baseDir: dir);
    return _resolvedFiles;
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    // A load failure (e.g. the DB handle was closed mid-load during a restore
    // swap) must never crash into a red screen — treat it as "claim not found"
    // so the user sees an honest state with a way back out (spec §3.3).
    Claim? claim;
    List<StatusHistoryEntry> history = const [];
    Reminder? reminder;
    List<Attachment> attachments = const [];
    try {
      claim = await widget.db.claimById(widget.claimId);
      // History, reminder and attachments are only meaningful while the claim
      // exists (spec §9–§12).
      if (claim != null) {
        history = await StatusHistoryRepository(widget.db)
            .listForClaim(widget.claimId);
        reminder = await RemindersRepository(widget.db)
            .latestForClaim(widget.claimId);
        attachments = await AttachmentsRepository(widget.db)
            .listForClaim(widget.claimId);
      }
    } on Object catch (_) {
      claim = null;
      history = const [];
      reminder = null;
      attachments = const [];
    }

    // Resolve the store early (best-effort) so open/delete work without an
    // extra round-trip, and flag rows whose physical file is missing.
    Set<String> missing = const {};
    if (attachments.isNotEmpty) {
      AttachmentFileService? svc;
      try {
        svc = await _ensureFiles();
      } on Object catch (_) {}
      if (svc != null) {
        final Set<String> foundMissing = <String>{};
        for (final Attachment a in attachments) {
          try {
            if (!svc.fileFor(a).existsSync()) {
              foundMissing.add(a.relativePath);
            }
          } on Object catch (_) {
            foundMissing.add(a.relativePath);
          }
        }
        missing = foundMissing;
      }
    }

    if (!mounted) return;
    setState(() {
      _claim = claim;
      _history = history;
      _reminder = reminder;
      _attachments = attachments;
      _missingPaths = missing;
      _loaded = true;
    });
  }

  Future<void> _edit() async {
    final Claim current = _claim!;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ClaimFormScreen(
          claim: current,
          onSaved: (Claim saved) => _repo.update(saved),
        ),
      ),
    );
    // Refresh after the form is dismissed so edits are visible.
    await _load();
  }

  /// Status-change dialog (spec §9): new status + optional note + an explicit
  /// follow-up decision (keep / set / clear). Confirm runs the atomic
  /// ClaimActions flow, then refreshes.
  Future<void> _changeStatus() async {
    final Claim current = _claim!;
    String selectedKey = current.statusKey;
    String note = '';
    int followUpChoice = 0; // 0 = keep, 1 = set new, 2 = clear
    DateTime? fireAtUtc;

    await showDialog<void>(
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
                        secondary: Icon(Icons.event_available_outlined),
                        value: 0,
                      ),
                      RadioListTile<int>(
                        title: Text(S.setNextFollowUp),
                        secondary: Icon(Icons.event_outlined),
                        value: 1,
                      ),
                      RadioListTile<int>(
                        title: Text(S.clearFollowUp),
                        secondary: Icon(Icons.event_busy_outlined),
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
                DateTime? picked;
                if (followUpChoice == 1) {
                  final DateTime now = DateTime.now().toUtc();
                  final DateTime? d = await showDatePicker(
                    context: ctx,
                    initialDate: (fireAtUtc ?? current.nextFollowUpUtcMs ?? now)
                        .toLocal(),
                    firstDate: DateTime(now.year - 1),
                    lastDate: DateTime(now.year + 5),
                  );
                  if (d == null || !ctx.mounted) return;
                  final TimeOfDay? t = await showTimePicker(
                    context: ctx,
                    initialTime: TimeOfDay.fromDateTime(d.toLocal()),
                  );
                  if (t == null || !ctx.mounted) return;
                  picked = DateTime(
                    d.year,
                    d.month,
                    d.day,
                    t.hour,
                    t.minute,
                  ).toUtc();
                }
                // Persist FIRST, then dismiss — the dialog stays open if the
                // write fails (same principle as the form's self-pop).
                await _applyStatusChange(
                  selectedKey: selectedKey,
                  note: note,
                  followUpChoice: followUpChoice,
                  fireAtUtc: picked,
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

  Future<void> _applyStatusChange({
    required String selectedKey,
    required String note,
    required int followUpChoice,
    DateTime? fireAtUtc,
  }) async {
    final FollowUpChange change = switch (followUpChoice) {
      1 => SetFollowUp(fireAtUtc ?? DateTime.now().toUtc()),
      2 => const ClearFollowUp(),
      _ => const KeepFollowUp(),
    };
    await _actions.changeStatus(
      widget.claimId,
      selectedKey,
      note: note.isEmpty ? null : note,
      followUp: change,
    );
    if (!mounted) return;
    await _load();
  }

  /// Reminder set/reschedule flow (spec §10): date picker → time picker, then
  /// the permission-aware save below.
  Future<void> _pickReminderDate() async {
    final DateTime now = DateTime.now().toUtc();
    final DateTime initial =
        (_reminder?.fireAtUtcMs ?? _claim?.nextFollowUpUtcMs ?? now).toLocal();
    final DateTime? d = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 5),
    );
    if (d == null || !mounted) return;
    final TimeOfDay? t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(d.toLocal()),
    );
    if (t == null || !mounted) return;
    await _saveReminder(
      DateTime(d.year, d.month, d.day, t.hour, t.minute).toUtc(),
    );
  }

  /// Permission-aware save (spec §10): the in-app state — reminder row and
  /// follow-up date — persists regardless of OS notification permission; only
  /// scheduling depends on it. Still denied afterwards → Arabic explanation.
  /// Phase 1 fix #3: a failed or inexact schedule is surfaced to the user via
  /// SnackBar instead of being silently swallowed.
  Future<void> _saveReminder(DateTime fireAtUtc) async {
    final ReminderScheduler scheduler =
        widget.scheduler ?? NotificationService.instance;
    bool enabled = await scheduler.areNotificationsEnabled();

    // Phase 1 fix #1: exact alarms are denied by default on Android 14+ —
    // explain and request before scheduling, in the same dialog style as the
    // notification-permission flow above.
    if (enabled && mounted) {
      final bool exactOk = await scheduler.canScheduleExactAlarms();
      if (!exactOk && mounted) {
        final bool? allowed = await showDialog<bool>(
          context: context,
          builder: (BuildContext ctx) => AlertDialog(
            title: Text(S.exactAlarmExplainTitle),
            content: Text(S.exactAlarmExplainBody),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: Text(S.cancel),
              ),
              FilledButton(
                key: const Key('request-exact-alarms'),
                onPressed: () => Navigator.of(ctx).pop(true),
                child: Text(S.exactAlarmsRequestAction),
              ),
            ],
          ),
        );
        if (allowed == true) {
          await scheduler.requestExactAlarmsPermission();
        }
      }
    }
    if (!enabled && mounted) {
      // Explain first, then let the user request permission explicitly.
      final bool? allowed = await showDialog<bool>(
        context: context,
        builder: (BuildContext ctx) => AlertDialog(
          title: Text(S.notificationsPermissionTitle),
          content: Text(S.notificationsPermissionBody),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(S.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(S.confirm),
            ),
          ],
        ),
      );
      if (allowed == true) {
        enabled =
            await scheduler.requestNotificationsPermission() ==
            NotificationPermissionState.granted;
      }
    }
    // Persist FIRST — the in-app state must not depend on OS permission.
    final ScheduleResult result = await _actions.saveReminder(
      claimId: widget.claimId,
      fireAtUtc: fireAtUtc,
      schedule: enabled,
    );
    if (!mounted) return;
    await _load();
    if (!mounted) return;

    // Phase 1 fix #3 — surface the scheduling outcome instead of hiding it.
    if (enabled && !result.scheduled) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(S.reminderScheduleFailed)));
      return;
    }
    if (enabled && result.precision == AlarmPrecision.inexact) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(S.reminderInexactWarning)));
      return;
    }
    if (!enabled) {
      // Still denied — explain how to enable notifications on the device and
      // offer a direct jump into the system notification settings (BUG B:
      // previously this dialog was static text with no recovery path).
      await showDialog<void>(
        context: context,
        builder: (BuildContext ctx) => AlertDialog(
          title: Text(S.notificationsDeniedTitle),
          content: Text(S.notificationsDeniedBody),
          actions: [
            TextButton(
              key: const Key('open-notification-settings'),
              onPressed: () async {
                Navigator.of(ctx).pop();
                await scheduler.openAppNotificationSettings();
              },
              child: Text(S.notificationsOpenSettingsAction),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(S.confirm),
            ),
          ],
        ),
      );
    }
  }

  /// Cancels the reminder directly, without changing the status. Clears the
  /// alarm, the reminder row and the follow-up date, so the claim leaves the
  /// follow-up and overdue lists — also when the reminder is already overdue
  /// or has already fired.
  Future<void> _cancelReminder() async {
    await _actions.clearFollowUp(widget.claimId);
    if (!mounted) return;
    await _load();
  }

  Future<void> _delete() async {
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
    if (confirmed != true || !mounted) return;
    // Delete through ClaimActions so reminders are cancelled and attachment
    // files cleaned up (spec §12); file cleanup is skipped when the store
    // cannot be resolved, so deletion always succeeds.
    if (_attachments.isNotEmpty) {
      try {
        await _ensureFiles();
      } on Object catch (_) {}
    }
    if (!mounted) return;
    await _actions.deleteClaim(widget.claimId);
    if (!mounted) return;
    // The claim no longer exists — leave the screen.
    Navigator.of(context).maybePop();
  }

  /// Adds one or more picked files to this claim (spec §12): copies them into
  /// the app-private store, records metadata, then refreshes. A single bad
  /// file never aborts the rest of the batch.
  Future<void> _addAttachment() async {
    final AttachmentPicker picker =
        widget.picker ?? const FilePickerAttachmentPicker();
    List<PlatformFile> picked;
    try {
      picked = await picker.pick(type: FileType.any);
    } on Object catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(S.attachmentPickFailed)));
      return;
    }
    if (picked.isEmpty) return;

    final AttachmentFileService? svc = await _ensureFiles();
    if (!mounted) return;
    if (svc == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(S.attachmentStoreError)));
      return;
    }

    for (final PlatformFile f in picked) {
      final String? path = f.path;
      if (path == null || !mounted) continue;
      try {
        await _actions.attachFile(
          widget.claimId,
          path,
          originalName: f.name,
          mimeType: _mimeFor(f.name),
        );
      } on Object catch (_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(S.attachmentPickFailed)));
      }
    }
    await _load();
  }

  /// Opens an attachment (spec §12): images preview in-app, everything else is
  /// handed to the OS. Failures are reported with a message — never crash.
  Future<void> _openAttachment(Attachment a) async {
    final AttachmentFileService? svc = await _ensureFiles();
    if (!mounted) return;
    File? f;
    try {
      f = svc?.fileFor(a);
    } on Object catch (_) {
      // Unresolvable path (e.g. store unavailable).
    }
    final bool exists = f != null && f.existsSync();
    if (!exists) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(S.attachmentOpenFailed)));
      return;
    }

    if (a.mimeType.startsWith('image/')) {
      await showDialog<void>(
        context: context,
        builder: (BuildContext ctx) => Dialog(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Image.file(f!, fit: BoxFit.contain),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: Text(S.close),
                ),
              ],
            ),
          ),
        ),
      );
      return;
    }

    final Future<bool> Function(Uri) open =
        widget.openExternal ?? _launchExternal;
    bool ok = false;
    try {
      ok = await open(f.uri);
    } on Object catch (_) {
      ok = false;
    }
    if (!mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(S.attachmentOpenFailed)));
    }
  }

  /// iOS QuickLook preview channel (ios/Runner/AppDelegate.swift).
  static const MethodChannel _filesChannel = MethodChannel(
    'com.claimtracker/files',
  );

  Future<bool> _launchExternal(Uri uri) async {
    // iOS cannot hand a sandboxed file:// URL to another app, so local
    // attachments are previewed in-app with the system QuickLook viewer.
    if (defaultTargetPlatform == TargetPlatform.iOS && uri.isScheme('file')) {
      try {
        final bool? ok = await _filesChannel.invokeMethod<bool>(
          'previewFile',
          <String, String>{'path': uri.toFilePath()},
        );
        return ok ?? false;
      } on Object catch (_) {
        return false;
      }
    }
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } on Object catch (_) {
      return false;
    }
  }

  /// Deletes one attachment after explicit confirmation (spec §12): removes
  /// the physical file first (best-effort), then the metadata row.
  Future<void> _deleteAttachment(Attachment a) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: Text(S.deleteAttachmentTitle),
        content: Text(S.deleteAttachmentBody),
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
    if (confirmed != true || !mounted) return;

    // Best-effort file cleanup — a failing delete must not block the row.
    try {
      final AttachmentFileService? svc = await _ensureFiles();
      await svc?.deleteFile(a);
    } on Object catch (_) {}
    if (!mounted) return;
    await AttachmentsRepository(widget.db).delete(a.id);
    await _load();
  }

  /// Best-effort MIME type from the file extension (spec §12) — drives in-app
  /// preview routing and external open; falls back to octet-stream.
  String _mimeFor(String name) {
    final int dot = name.lastIndexOf('.');
    if (dot <= 0 || dot == name.length - 1) return 'application/octet-stream';
    switch (name.substring(dot + 1).toLowerCase()) {
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'gif':
        return 'image/gif';
      case 'webp':
        return 'image/webp';
      case 'heic':
      case 'heif':
        return 'image/heic';
      case 'pdf':
        return 'application/pdf';
      case 'txt':
      case 'log':
        return 'text/plain';
      case 'csv':
        return 'text/csv';
      case 'html':
      case 'htm':
        return 'text/html';
      case 'json':
        return 'application/json';
      case 'doc':
        return 'application/msword';
      case 'docx':
        return 'application/vnd.openxmlformats-officedocument'
            '.wordprocessingml.document';
      case 'xls':
        return 'application/vnd.ms-excel';
      case 'xlsx':
        return 'application/vnd.openxmlformats-officedocument'
            '.spreadsheetml.sheet';
      case 'ppt':
        return 'application/vnd.ms-powerpoint';
      case 'pptx':
        return 'application/vnd.openxmlformats-officedocument'
            '.presentationml.presentation';
      default:
        return 'application/octet-stream';
    }
  }

  /// Human-readable byte size for attachment rows (spec §12).
  String _humanSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    final double kb = bytes / 1024;
    if (kb < 1024) return '${kb.toStringAsFixed(1)} KB';
    final double mb = kb / 1024;
    if (mb < 1024) return '${mb.toStringAsFixed(1)} MB';
    return '${(mb / 1024).toStringAsFixed(1)} GB';
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Claim? claim = _claim;

    return Scaffold(
      appBar: AppBar(title: Text(S.claimNumberLabel)),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : claim == null
          // Not-found state (e.g. deleted from another screen).
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(S.claimNotFound, textAlign: TextAlign.center),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(Icons.arrow_back),
                    label: Text(S.close),
                  ),
                ],
              ),
            )
          // Eager (non-lazy) sections — a single claim's details must all be
          // present at once (same ruling as the list and form screens).
          : SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _section(
                    S.customerNameLabel,
                    claim,
                    (c) => [
                      _row(theme, S.customerNameLabel, c.customerName),
                      _row(theme, S.mobileLabel, c.customerMobile),
                      if (c.customerNationalId != null)
                        _row(theme, S.nationalIdLabel, c.customerNationalId!),
                      if (c.customerEmail != null)
                        _row(theme, S.emailLabel, c.customerEmail!),
                    ],
                  ),
                  _section(
                    S.accidentDateLabel,
                    claim,
                    (c) => [
                      _row(
                        theme,
                        S.accidentDateLabel,
                        TimeUtils.formatDate(c.accidentDateUtcMs),
                      ),
                      if (c.accidentNumber != null)
                        _row(theme, S.accidentNumberLabel, c.accidentNumber!),
                      if (c.accidentCity != null)
                        _row(theme, S.cityLabel, c.accidentCity!),
                      if (c.accidentType != null)
                        _row(theme, S.accidentTypeLabel, c.accidentType!),
                      if (c.vehiclePlate != null)
                        _row(theme, S.vehiclePlateLabel, c.vehiclePlate!),
                    ],
                  ),
                  _section(
                    S.claimNumberLabel,
                    claim,
                    (c) => [
                      _row(theme, S.claimNumberLabel, c.claimNumber),
                      _row(
                        theme,
                        S.customerInsurerLabel,
                        c.customerInsuranceCompany,
                      ),
                      _row(
                        theme,
                        S.liabilityPercentLabel,
                        c.liabilityPercent == null
                            ? S.liabilityNotSet
                            : '${c.liabilityPercent!.toStringAsFixed(0)}%',
                      ),
                      _row(
                        theme,
                        S.submissionDateLabel,
                        TimeUtils.formatDate(c.submissionDateUtcMs),
                      ),
                      if (c.insurerReferenceNumber != null)
                        _row(
                          theme,
                          S.insurerRefLabel,
                          c.insurerReferenceNumber!,
                        ),
                      _row(
                        theme,
                        S.claimAmountLabel,
                        TimeUtils.formatSar(c.claimAmountSar),
                      ),
                      if (c.notes != null && c.notes!.isNotEmpty)
                        _row(theme, S.notesLabel, c.notes!),
                    ],
                  ),
                  _section(
                    S.statusLabel,
                    claim,
                    (c) => [
                      // The section title already carries the label — show
                      // only the chip here so S.statusLabel appears once.
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: StatusChip(statusKey: c.statusKey),
                      ),
                      const SizedBox(height: 12),
                      _row(
                        theme,
                        S.lastStatusUpdateLabel,
                        TimeUtils.formatDateTime(c.lastStatusUpdateUtcMs),
                      ),
                      _row(
                        theme,
                        S.nextFollowUpLabel,
                        c.nextFollowUpUtcMs == null
                            ? '—'
                            : TimeUtils.followUpLabel(
                                c.nextFollowUpUtcMs!,
                                nowUtc: DateTime.now().toUtc(),
                              ),
                      ),
                    ],
                  ),
                  _section(
                    S.reminderTitle,
                    claim,
                    (c) => [
                      Text(
                        _reminder != null && _reminder!.enabled
                            ? S.reminderEnabled
                            : S.reminderDisabled,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: AppTheme.muted(context),
                        ),
                      ),
                      if (_reminder != null && _reminder!.enabled) ...[
                        const SizedBox(height: 12),
                        _row(
                          theme,
                          S.reminderWhenLabel,
                          TimeUtils.formatDateTime(_reminder!.fireAtUtcMs),
                        ),
                      ],
                      const SizedBox(height: 16),
                      // No non-functional buttons (spec §3.3): the disable
                      // action only exists while a reminder is enabled.
                      Row(
                        children: [
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: _pickReminderDate,
                              style: FilledButton.styleFrom(
                                minimumSize: const Size(64, 48),
                              ),
                              icon: const Icon(
                                Icons.notifications_active_outlined,
                              ),
                              label: Text(S.reminderSet),
                            ),
                          ),
                          if (c.nextFollowUpUtcMs != null) ...[
                            const SizedBox(width: 12),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: _cancelReminder,
                                style: OutlinedButton.styleFrom(
                                  minimumSize: const Size(64, 48),
                                ),
                                icon: const Icon(
                                  Icons.notifications_off_outlined,
                                ),
                                label: Text(S.reminderDisable),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                  _section(
                    S.statusHistoryLabel,
                    claim,
                    (c) => [
                      if (_history.isEmpty)
                        Text(
                          S.historyEmpty,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: AppTheme.muted(context),
                          ),
                        )
                      else
                        ..._history.map<Widget>(
                          (e) => Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    // The current status is visually
                                    // distinguished (filled chip) from older
                                    // rows (plain label) — spec §11.
                                    if (e.newStatusKey == c.statusKey)
                                      StatusChip(statusKey: e.newStatusKey)
                                    else
                                      Text(
                                        ClaimStatus.byKey(e.newStatusKey).label,
                                        style: theme.textTheme.bodyMedium,
                                      ),
                                    Text(
                                      TimeUtils.formatDateTime(
                                        e.changedAtUtcMs,
                                      ),
                                      style: theme.textTheme.bodySmall,
                                    ),
                                  ],
                                ),
                                if (e.note != null && e.note!.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Text(
                                      e.note!,
                                      style: theme.textTheme.bodyMedium
                                          ?.copyWith(
                                            color: AppTheme.muted(context),
                                          ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                  _section(
                    S.attachmentsLabel,
                    claim,
                    (c) => [
                      if (_attachments.isEmpty)
                        Text(
                          S.attachmentsEmpty,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: AppTheme.muted(context),
                          ),
                        )
                      else
                        ..._attachments.map<Widget>(
                          (a) => Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Row(
                              children: [
                                Expanded(
                                  child: InkWell(
                                    onTap: () => _openAttachment(a),
                                    borderRadius: BorderRadius.circular(8),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          a.originalName,
                                          style: theme.textTheme.bodyMedium,
                                        ),
                                        Text(
                                          _humanSize(a.sizeBytes),
                                          style: theme.textTheme.bodySmall
                                              ?.copyWith(
                                                color: AppTheme.muted(context),
                                              ),
                                        ),
                                        if (_missingPaths.contains(
                                          a.relativePath,
                                        ))
                                          Text(
                                            S.attachmentMissing,
                                            style: theme.textTheme.bodySmall
                                                ?.copyWith(
                                                  color: Theme.of(context)
                                                      .colorScheme
                                                      .error,
                                                ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                                IconButton(
                                  key: Key('attach-del-${a.id}'),
                                  tooltip: S.delete,
                                  icon: const Icon(Icons.delete_outline),
                                  onPressed: () => _deleteAttachment(a),
                                ),
                              ],
                            ),
                          ),
                        ),
                      FilledButton.icon(
                        key: const Key('attach-add'),
                        onPressed: _addAttachment,
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(64, 48),
                        ),
                        icon: const Icon(Icons.attach_file),
                        label: Text(S.attachmentAdd),
                      ),
                    ],
                  ),
                ],
              ),
            ),
      bottomNavigationBar: claim != null
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                // All three actions stay visible on one line (spec §3.3);
                // the labels are short enough for a single Row at any width.
                child: Row(
                  children: [
                    Expanded(
                      flex: 4,
                      child: FilledButton.icon(
                        onPressed: _changeStatus,
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(64, 48),
                        ),
                        icon: const Icon(Icons.swap_vert_outlined),
                        label: Text(S.changeStatus),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 3,
                      child: OutlinedButton.icon(
                        onPressed: _edit,
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(64, 48),
                        ),
                        icon: const Icon(Icons.edit_outlined),
                        label: Text(S.edit),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 3,
                      child: OutlinedButton.icon(
                        onPressed: _delete,
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(64, 48),
                          foregroundColor: theme.colorScheme.error,
                        ),
                        icon: const Icon(Icons.delete_outline),
                        label: Text(S.delete),
                      ),
                    ),
                  ],
                ),
              ),
            )
          : null,
    );
  }

  Widget _section(
    String title,
    Claim claim,
    List<Widget> Function(Claim) rows,
  ) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              ...rows(claim),
            ],
          ),
        ),
      ),
    );
  }

  /// Label/value row — label on the start side, value on the end side so it
  /// reads naturally in RTL (spec §3.4).
  Widget _row(ThemeData theme, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(child: Text(label, style: theme.textTheme.bodyMedium)),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
