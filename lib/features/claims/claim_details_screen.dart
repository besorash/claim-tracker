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
import 'package:video_player/video_player.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants/accident_types.dart';
import '../../core/constants/insurers.dart';
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
import 'claim_dialogs.dart';
import 'claim_form_screen.dart';
import 'reminder_save_flow.dart';

class ClaimDetailsScreen extends StatefulWidget {
  const ClaimDetailsScreen({
    super.key,
    required this.db,
    required this.claimId,
    this.scheduler,
    this.picker,
    this.files,
    this.openExternal,
    this.playVideo,
    this.callNumber,
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

  /// In-app video playback seam (spec §12 extension): receives the stored file,
  /// returns success. Default plays in an in-app dialog — videos must NOT be
  /// handed to external apps on Android (file-URI exposure between apps is
  /// blocked). Widget tests inject a recorder so no platform channels run.
  final Future<bool> Function(File)? playVideo;

  /// Tap-to-call seam for the two phone rows: receives the number, returns
  /// success. Defaults to `tel:` via url_launcher (same channel family as
  /// attachment opens); widget tests inject a recorder — never a real call.
  final Future<bool> Function(String phoneNumber)? callNumber;

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
          onSaved: (Claim saved) async {
            await _repo.update(saved);
            if (!mounted) return;
            // Keep the reminder in sync with the edited follow-up (spec §10):
            // reschedule when changed, cancel + clear when removed.
            final ReminderScheduler scheduler =
                widget.scheduler ?? NotificationService.instance;
            await syncFollowUpAfterEdit(
              context,
              widget.db,
              scheduler,
              before: current,
              saved: saved,
            );
          },
        ),
      ),
    );
    // Refresh after the form is dismissed so edits are visible.
    await _load();
  }

  /// Status-change dialog (spec §9), shared with the claims list.
  Future<void> _changeStatus() => showChangeStatusDialog(
    context,
    claim: _claim!,
    onSave: (StatusChangeRequest request) async {
      await _actions.changeStatus(
        widget.claimId,
        request.statusKey,
        note: request.note,
        followUp: request.followUp,
      );
      if (!mounted) return;
      await _load();
    },
  );

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
  /// SnackBar instead of being silently swallowed. The permission sequence and
  /// outcome reporting live in [reminder_save_flow] — shared verbatim with the
  /// form's add/edit flows so every entry point behaves identically.
  Future<void> _saveReminder(DateTime fireAtUtc) async {
    final ReminderScheduler scheduler =
        widget.scheduler ?? NotificationService.instance;
    final bool enabled = await resolveReminderPermissions(context, scheduler);
    if (!mounted) return;

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
    await reportReminderSaveOutcome(
      context,
      scheduler: scheduler,
      enabled: enabled,
      result: result,
    );
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
    final bool confirmed = await confirmDeleteClaim(context);
    if (!confirmed || !mounted) return;
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
  /// file never aborts the rest of the batch. Shared by every picker entry
  /// point — generic files and gallery photos/videos only differ in HOW the
  /// [picked] list is obtained (spec §12 extension).
  Future<void> _importPicked(List<PlatformFile> picked) async {
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

  /// Adds one or more files picked from the generic OS picker (spec §12).
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
    await _importPicked(picked);
  }

  /// Adds photos picked from the phone gallery (spec §12 extension): same store
  /// pipeline as [_addAttachment] — only the picker entry point differs.
  Future<void> _addPhotos() async {
    final AttachmentPicker picker =
        widget.picker ?? const FilePickerAttachmentPicker();
    List<PlatformFile> picked;
    try {
      picked = await picker.pickImages();
    } on Object catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(S.attachmentPickFailed)));
      return;
    }
    if (picked.isEmpty) return;
    await _importPicked(picked);
  }

  /// Adds videos picked from the phone gallery (spec §12 extension): same store
  /// pipeline as [_addAttachment] — only the picker entry point differs.
  Future<void> _addVideos() async {
    final AttachmentPicker picker =
        widget.picker ?? const FilePickerAttachmentPicker();
    List<PlatformFile> picked;
    try {
      picked = await picker.pickVideos();
    } on Object catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(S.attachmentPickFailed)));
      return;
    }
    if (picked.isEmpty) return;
    await _importPicked(picked);
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

    // Video attachments play IN-APP (spec §12 extension): Android blocks
    // file:// URIs between apps, and url_launcher 6.3.x performs no FileProvider
    // conversion — an external video open would be flaky/broken there. The
    // default player is in-app; tests route through the [playVideo] seam.
    if (a.mimeType.startsWith('video/')) {
      final Future<bool> Function(File) play =
          widget.playVideo ?? _playInAppPlayer;
      bool ok;
      try {
        ok = await play(f);
      } on Object catch (_) {
        ok = false; // a throwing player must never crash the screen
      }
      if (!mounted) return;
      if (!ok) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(S.attachmentOpenFailed)));
      }
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

  /// Production default for [ClaimDetailsScreen.playVideo] (spec §12 extension):
  /// plays the stored file in a dialog with play/pause and close, mirroring the
  /// image-preview dialog shape. The controller is ALWAYS disposed — on init
  /// failure and after the dialog pops — so reopening never leaks a native
  /// player. Returns false when playback could not start; failures surface as
  /// S.attachmentOpenFailed at the call site.
  Future<bool> _playInAppPlayer(File file) async {
    final VideoPlayerController controller = VideoPlayerController.file(file);
    try {
      await controller.initialize();
    } on Object catch (_) {
      // Unreadable/undecodable source — report failure, dispose cleanly.
      await controller.dispose();
      return false;
    }
    if (!mounted) {
      // Navigated away mid-init — nothing to show; still release the player.
      await controller.dispose();
      return false;
    }

    bool playing = true;
    controller.play();
    await showDialog<void>(
      context: context,
      builder: (BuildContext ctx) => StatefulBuilder(
        builder: (BuildContext buildCtx, StateSetter setUi) => Dialog(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AspectRatio(
                  aspectRatio: controller.value.aspectRatio,
                  // video_player 2.14.x names the render widget [VideoPlayer].
                  child: VideoPlayer(controller),
                ),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      OutlinedButton.icon(
                        onPressed: () {
                          if (playing) {
                            controller.pause();
                          } else {
                            controller.play();
                          }
                          setUi(() => playing = !playing);
                        },
                        icon: Icon(playing ? Icons.pause : Icons.play_arrow),
                        label: Text(playing ? S.videoPause : S.videoPlay),
                      ),
                      const SizedBox(width: 12),
                      FilledButton(
                        onPressed: () => Navigator.of(buildCtx).pop(),
                        child: Text(S.close),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await controller.dispose(); // dialog dismissed — release the native player.
    return true;
  }

  /// iOS QuickLook preview channel (ios/Runner/AppDelegate.swift).
  static const MethodChannel _filesChannel = MethodChannel(
    'com.claimtracker/files',
  );

  /// Default dialer: hands the number to the OS via `tel:` (url_launcher —
  /// already a dependency, same channel family as attachment opens).
  Future<bool> _dial(String number) async {
    try {
      return await launchUrl(Uri(scheme: 'tel', path: number.trim()));
    } on Object catch (_) {
      return false;
    }
  }

  /// Taps a phone row (customer or insurer mobile): launches the dialer, and
  /// reports any failure — including a throwing caller — as S.callFailed.
  Future<void> _tapCall(String number) async {
    final Future<bool> Function(String) call = widget.callNumber ?? _dial;
    bool ok;
    try {
      ok = await call(number);
    } on Object catch (_) {
      ok = false; // a throwing dialer must never crash the screen
    }
    if (!mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(S.callFailed)));
    }
  }

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
      // Video types (spec §12 extension) — drives in-app playback routing.
      case 'mp4':
        return 'video/mp4';
      case 'm4v':
        return 'video/x-m4v';
      case 'mov':
        return 'video/quicktime';
      case '3gp':
        return 'video/3gpp';
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

    // The page title is the screen's main heading — styled with the brand
    // accent (the theme primary) so it matches the app style in both themes
    // instead of falling back to near-white text.
    return Scaffold(
      appBar: AppBar(
        title: Text(
          S.claimNumberLabel,
          style: TextStyle(color: theme.colorScheme.primary),
        ),
      ),
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
                    S.sectionCustomerInfo,
                    claim,
                    (c) => [
                      _row(theme, S.customerNameLabel, c.customerName),
                      if (c.customerMobile.isNotEmpty)
                        _phoneRow(
                          theme,
                          S.mobileLabel,
                          c.customerMobile,
                          'customerMobile',
                        ),
                      if (c.customerNationalId != null)
                        _row(theme, S.nationalIdLabel, c.customerNationalId!),
                      if (c.customerEmail != null)
                        _row(theme, S.emailLabel, c.customerEmail!),
                    ],
                  ),
                  _section(
                    S.sectionAccidentInfo,
                    claim,
                    (c) => [
                      _row(
                        theme,
                        S.accidentDateLabel,
                        TimeUtils.formatDate(c.accidentDateUtcMs),
                      ),
                      if (c.accidentCity != null)
                        _row(theme, S.cityLabel, c.accidentCity!),
                      if (c.accidentType != null)
                        _row(
                          theme,
                          S.accidentTypeLabel,
                          AccidentTypes.display(c.accidentType!),
                        ),
                      if (c.vehiclePlate != null)
                        // Plate value is always LTR — see [_row]'s `ltr` parameter.
                        _row(
                          theme,
                          S.vehiclePlateLabel,
                          c.vehiclePlate!,
                          ltr: true,
                        ),
                      if (c.vehicleType != null)
                        _row(theme, S.vehicleTypeLabel, c.vehicleType!),
                      _row(
                        theme,
                        S.liabilityPercentLabel,
                        c.liabilityPercent == null
                            ? S.liabilityNotSet
                            : '${c.liabilityPercent!.toStringAsFixed(0)}%',
                      ),
                    ],
                  ),
                  _section(
                    S.sectionClaimInfo,
                    claim,
                    (c) => [
                      _row(theme, S.claimNumberLabel, c.claimNumberDisplay),
                      _row(
                        theme,
                        S.customerInsurerLabel,
                        Insurers.display(c.customerInsuranceCompany),
                      ),
                      if (c.insuranceMobile != null &&
                          c.insuranceMobile!.isNotEmpty)
                        _phoneRow(
                          theme,
                          S.insuranceMobileLabel,
                          c.insuranceMobile!,
                          'insuranceMobile',
                        ),
                      if (c.submissionDateUtcMs != null)
                        _row(
                          theme,
                          S.submissionDateLabel,
                          TimeUtils.formatDate(c.submissionDateUtcMs!),
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
                        _notesRow(theme, S.notesLabel, c.notes!),
                    ],
                  ),
                  if (claim.extraFields.isNotEmpty)
                    _section(
                      S.extraFieldsLabel,
                      claim,
                      (c) => [
                        for (final MapEntry<String, String> e
                            in c.extraFields.entries)
                          _row(theme, e.key, e.value),
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
                      // Gallery entry points (spec §12 extension): half-width
                      // buttons so both fit one line in EN and AR.
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              key: const Key('attach-add-photos'),
                              onPressed: _addPhotos,
                              style: OutlinedButton.styleFrom(
                                minimumSize: const Size(64, 48),
                              ),
                              icon: const Icon(Icons.photo_library_outlined),
                              label: Text(S.attachmentAddPhotos),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: OutlinedButton.icon(
                              key: const Key('attach-add-videos'),
                              onPressed: _addVideos,
                              style: OutlinedButton.styleFrom(
                                minimumSize: const Size(64, 48),
                              ),
                              icon: const Icon(Icons.videocam_outlined),
                              label: Text(S.attachmentAddVideos),
                            ),
                          ),
                        ],
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
              // Section headings use the brand accent (the theme primary —
              // teal in light mode, lightened teal in dark) so every title on
              // this page matches the app style instead of rendering white.
              Text(
                title,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: theme.colorScheme.primary,
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
  /// reads naturally in RTL (spec §3.4). With [ltr] the value renders in an
  /// explicit LTR context (the vehicle plate: always readable like a real
  /// license plate) while keeping that language's native row alignment — EN
  /// flush-right, AR on the left — so it stays in line with sibling rows.
  Widget _row(ThemeData theme, String label, String value, {bool ltr = false}) {
    // Inside our LTR wrapper `TextAlign.end` is always visually right; to keep
    // each language's row convention (AR places values on the left) pin left
    // only when the ambient UI is RTL.
    final bool ambientRtl = Directionality.of(context) == TextDirection.rtl;
    final Widget valueWidget = Text(
      value,
      textAlign: ltr && ambientRtl ? TextAlign.left : TextAlign.end,
      style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(child: Text(label, style: theme.textTheme.bodyMedium)),
          const SizedBox(width: 16),
          Expanded(
            child: ltr
                ? Directionality(
                    textDirection: TextDirection.ltr,
                    child: valueWidget,
                  )
                : valueWidget,
          ),
        ],
      ),
    );
  }

  /// Tappable phone-number row — label takes its natural width at the start
  /// edge, and the value box is pinned against the trailing call affordance
  /// (so every phone row's number ends flush with that icon, in both EN and
  /// AR). The label must NOT be a flex child here: with `Flexible` on it, its
  /// unused share becomes free space that `spaceBetween` spreads between all
  /// children, which shifts the value (and only short-label rows) away from
  /// the icon — misaligning sibling phone numbers. Tapping launches the
  /// dialer for [value] (see [_tapCall]). Stable key per field for tests.
  Widget _phoneRow(ThemeData theme, String label, String value, String id) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Semantics(
        // Screen readers announce the row as a button (review F4) — this
        // Flutter version's InkWell does not set the flag on its own.
        button: true,
        child: InkWell(
          key: Key('call-$id'),
          borderRadius: BorderRadius.circular(8),
          onTap: () => _tapCall(value),
          child: Padding(
            // Real touch target (review F4): the tap area must comfortably
            // exceed the text line height (~20 dp) — WCAG 2.5.8 floor is 44 px.
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(label, style: theme.textTheme.bodyMedium),
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
                const SizedBox(width: 4),
                Icon(Icons.call, size: 18, color: AppTheme.muted(context)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Notes row (spec §11) — the one field that must stand out on this screen:
  /// a distinct orange highlight with fully legible text in both themes. Same
  /// label/value layout as [_row] so it reads naturally in RTL.
  Widget _notesRow(ThemeData theme, String label, String value) {
    final bool isDark = theme.brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkNotesFill : AppColors.lightNotesFill,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isDark
                ? AppColors.darkNotesBorder
                : AppColors.lightNotesBorder,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Flexible(
              child: Text(
                label,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: isDark
                      ? AppColors.darkNotesText
                      : AppColors.lightNotesText,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                value,
                textAlign: TextAlign.end,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: isDark
                      ? AppColors.darkNotesText
                      : AppColors.lightNotesText,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
