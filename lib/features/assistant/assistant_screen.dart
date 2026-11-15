/// AI assistant tab: a chat with Google Gemini that can look up claims and,
/// after the user confirms a card, register claims, set or remove reminders,
/// change statuses and add notes.
library;

import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/database/app_database.dart';
import '../../core/l10n/app_strings.dart';
import '../../core/models/claim.dart';
import '../../core/notifications/reminder_scheduler.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/widgets/modern.dart';
import '../../shared/widgets/status_chip.dart';
import '../claims/reminder_save_flow.dart';
import 'assistant_agent.dart';
import 'assistant_tools.dart';
import 'gemini_client.dart';

class AssistantScreen extends StatefulWidget {
  const AssistantScreen({
    super.key,
    required this.db,
    required this.scheduler,
    this.keyStore = const SecureAssistantKeyStore(),
    this.transport,
    this.onDataChanged,
    this.onOpenClaim,
  });

  final AppDatabase db;
  final ReminderScheduler scheduler;
  final AssistantKeyStore keyStore;

  /// Gemini HTTP seam (tests); null = real network.
  final GeminiTransport? transport;

  /// After a confirmed change, so the other tabs reload.
  final VoidCallback? onDataChanged;
  final void Function(int claimId)? onOpenClaim;

  static const String defaultModel = 'gemini-flash-latest';

  @override
  State<AssistantScreen> createState() => _AssistantScreenState();
}

class _AssistantScreenState extends State<AssistantScreen> {
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();
  AssistantAgent? _agent;
  bool _loading = true;

  // Voice input. Initialized on the first mic tap, so the permission prompt
  // only appears when the user actually wants to speak.
  final SpeechToText _speech = SpeechToText();
  bool? _speechReady;
  bool _listening = false;

  /// Speech language; Arabic by default, a long press on the mic toggles.
  bool _speakArabic = true;

  @override
  void initState() {
    super.initState();
    _connect();
  }

  @override
  void dispose() {
    if (_listening) _speech.cancel();
    _agent?.dispose();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// (Re)builds the agent from the stored key; no key → setup view.
  Future<void> _connect() async {
    String? key;
    String? model;
    try {
      key = await widget.keyStore.readKey();
      model = await widget.keyStore.readModel();
    } on Object catch (_) {
      key = null;
    }
    if (!mounted) return;
    _agent?.dispose();
    _agent = null;
    if (key != null && key.trim().isNotEmpty) {
      _agent = AssistantAgent(
        client: GeminiClient(
          apiKey: key.trim(),
          model: (model == null || model.trim().isEmpty)
              ? AssistantScreen.defaultModel
              : model.trim(),
          transport: widget.transport,
        ),
        tools: AssistantTools(
          db: widget.db,
          scheduler: widget.scheduler,
          // Same permission prompts and outcome messages as every other
          // reminder entry point in the app.
          saveFollowUp: (int id, DateTime whenUtc) async {
            if (!mounted) return;
            await scheduleFollowUpOnCreate(
              context,
              widget.db,
              widget.scheduler,
              id,
              whenUtc,
            );
          },
        ),
        onDataChanged: widget.onDataChanged,
      )..addListener(_onAgentChanged);
    }
    setState(() => _loading = false);
  }

  void _onAgentChanged() {
    if (!mounted) return;
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _send([String? text]) {
    final AssistantAgent? agent = _agent;
    final String message = (text ?? _input.text).trim();
    if (agent == null || agent.busy || message.isEmpty) return;
    _input.clear();
    agent.send(message);
  }

  void _snack(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Future<void> _toggleMic() async {
    if (_listening) {
      await _speech.stop(); // the final result then sends the text
      return;
    }
    final AssistantAgent? agent = _agent;
    if (agent == null || agent.busy) return;
    _speechReady ??= await _initSpeech();
    if (!mounted) return;
    if (_speechReady != true) {
      _speechReady = null; // try again next tap (e.g. permission granted later)
      _snack(S.assistantMicUnavailable);
      return;
    }
    _input.clear();
    setState(() => _listening = true);
    try {
      await _speech.listen(
        onResult: (result) {
          if (!mounted) return;
          final String words = result.recognizedWords;
          _input.value = TextEditingValue(
            text: words,
            selection: TextSelection.collapsed(offset: words.length),
          );
          if (result.finalResult) {
            setState(() => _listening = false);
            _send(words);
          }
        },
        listenOptions: SpeechListenOptions(
          localeId: _speakArabic ? 'ar_SA' : 'en_US',
          partialResults: true,
          cancelOnError: true,
          listenMode: ListenMode.dictation,
          pauseFor: const Duration(seconds: 3),
          listenFor: const Duration(seconds: 60),
        ),
      );
    } on Object catch (_) {
      if (!mounted) return;
      setState(() => _listening = false);
      _snack(S.assistantMicUnavailable);
    }
  }

  Future<bool> _initSpeech() async {
    try {
      return await _speech.initialize(
        options: <SpeechConfigOption>[SpeechToText.androidNoBluetooth],
        onStatus: (String status) {
          if (!mounted) return;
          if ((status == 'done' || status == 'notListening') && _listening) {
            setState(() => _listening = false);
          }
        },
        onError: (_) {
          if (mounted && _listening) setState(() => _listening = false);
        },
      );
    } on Object catch (_) {
      return false;
    }
  }

  void _switchVoiceLanguage() {
    if (_listening) return;
    setState(() => _speakArabic = !_speakArabic);
    _snack(S.assistantMicLanguage(_speakArabic ? 'العربية' : 'English'));
  }

  Future<void> _openSettings() async {
    final bool? changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) =>
          _KeySheet(keyStore: widget.keyStore, transport: widget.transport),
    );
    if (changed == true) {
      setState(() => _loading = true);
      await _connect();
    }
  }

  @override
  Widget build(BuildContext context) {
    final AssistantAgent? agent = _agent;
    return Column(
      children: <Widget>[
        _Header(
          canReset: agent != null && agent.items.isNotEmpty && !agent.busy,
          onReset: () => agent?.clear(),
          onSettings: _openSettings,
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : agent == null
              ? _SetupView(onAddKey: _openSettings)
              : agent.items.isEmpty
              ? _Welcome(onPick: _send)
              : _ChatList(
                  agent: agent,
                  controller: _scroll,
                  onOpenClaim: widget.onOpenClaim,
                  onOpenSettings: _openSettings,
                ),
        ),
        if (agent != null)
          _InputBar(
            listening: _listening,
            voiceLabel: _speakArabic ? 'AR' : 'EN',
            onMic: _toggleMic,
            onMicLongPress: _switchVoiceLanguage,
            controller: _input,
            busy: agent.busy,
            onSend: () => _send(),
          ),
      ],
    );
  }
}

// -----------------------------------------------------------------------------
// Header
// -----------------------------------------------------------------------------

class _Header extends StatelessWidget {
  const _Header({
    required this.canReset,
    required this.onReset,
    required this.onSettings,
  });

  final bool canReset;
  final VoidCallback onReset;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: GradientHero(
        radius: 24,
        padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
        child: Row(
          children: <Widget>[
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(
                Icons.auto_awesome_rounded,
                color: Colors.white,
                size: 26,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    S.assistantTitle,
                    style: text.titleMedium?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  Text(
                    S.assistantPoweredBy,
                    style: text.bodySmall?.copyWith(
                      color: Colors.white.withValues(alpha: 0.82),
                    ),
                  ),
                ],
              ),
            ),
            if (canReset)
              IconButton(
                key: const Key('assistant-new-chat'),
                tooltip: S.assistantNewChat,
                onPressed: onReset,
                icon: const Icon(
                  Icons.add_comment_rounded,
                  color: Colors.white,
                ),
              ),
            IconButton(
              key: const Key('assistant-settings'),
              tooltip: S.assistantSettingsTitle,
              onPressed: onSettings,
              icon: const Icon(Icons.key_rounded, color: Colors.white),
            ),
          ],
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Empty states
// -----------------------------------------------------------------------------

class _SetupView extends StatelessWidget {
  const _SetupView({required this.onAddKey});

  final VoidCallback onAddKey;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: <Widget>[
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: <Widget>[
                const IconBubble(
                  icon: Icons.vpn_key_rounded,
                  color: AppColors.violet,
                  size: 64,
                  solid: true,
                ),
                const SizedBox(height: 16),
                Text(
                  S.assistantSetupTitle,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  S.assistantSetupBody,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: AppTheme.muted(context),
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    key: const Key('assistant-add-key'),
                    onPressed: onAddKey,
                    icon: const Icon(Icons.key_rounded),
                    label: Text(S.assistantAddKey),
                  ),
                ),
                const SizedBox(height: 8),
                const _GetKeyButton(),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _GetKeyButton extends StatelessWidget {
  const _GetKeyButton();

  @override
  Widget build(BuildContext context) => TextButton.icon(
    onPressed: () => launchUrl(
      Uri.parse('https://aistudio.google.com/apikey'),
      mode: LaunchMode.externalApplication,
    ),
    icon: const Icon(Icons.open_in_new_rounded, size: 18),
    label: Text(S.assistantGetKey),
  );
}

class _Welcome extends StatelessWidget {
  const _Welcome({required this.onPick});

  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final List<(IconData, Color, String)> ideas = <(IconData, Color, String)>[
      (Icons.alarm_rounded, AppColors.rose, S.assistantSuggestOverdue),
      (Icons.insights_rounded, AppColors.sky, S.assistantSuggestSummary),
      (
        Icons.notifications_active_rounded,
        AppColors.amber,
        S.assistantSuggestReminder,
      ),
      (Icons.note_add_rounded, AppColors.mint, S.assistantSuggestCreate),
    ];
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      children: <Widget>[
        Text(
          S.assistantSubtitle,
          textAlign: TextAlign.center,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 20),
        Text(
          S.assistantTryAsking,
          style: theme.textTheme.labelLarge?.copyWith(
            color: AppTheme.muted(context),
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 10),
        for (final (IconData icon, Color color, String text) in ideas)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Card(
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () => onPick(text),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: <Widget>[
                      IconBubble(icon: icon, color: color, size: 38),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          text,
                          style: theme.textTheme.bodyLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      Icon(
                        Icons.arrow_forward_ios_rounded,
                        size: 14,
                        color: AppTheme.muted(context),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// -----------------------------------------------------------------------------
// Conversation
// -----------------------------------------------------------------------------

class _ChatList extends StatelessWidget {
  const _ChatList({
    required this.agent,
    required this.controller,
    required this.onOpenClaim,
    required this.onOpenSettings,
  });

  final AssistantAgent agent;
  final ScrollController controller;
  final void Function(int claimId)? onOpenClaim;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final List<ChatItem> items = agent.items;
    final bool waiting =
        agent.busy &&
        !(items.isNotEmpty &&
            items.last is ActionCard &&
            (items.last as ActionCard).state == ActionState.pending);
    return ListView.builder(
      controller: controller,
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      itemCount: items.length + (waiting ? 1 : 0),
      itemBuilder: (BuildContext context, int i) {
        if (i == items.length) return const _Thinking();
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: switch (items[i]) {
            UserMessage(:final String text) => _Bubble(text: text, mine: true),
            AssistantMessage(:final String text) => _Bubble(
              text: text,
              mine: false,
            ),
            ClaimsResult(:final List<Claim> claims) => _ClaimList(
              claims: claims,
              onOpen: onOpenClaim,
            ),
            final ActionCard card => _ActionCardView(
              card: card,
              onOpen: onOpenClaim,
            ),
            final ErrorMessage e => _ErrorView(
              error: e,
              onOpenSettings: onOpenSettings,
            ),
          },
        );
      },
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.text, required this.mine});

  final String text;
  final bool mine;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    const Radius r = Radius.circular(20);
    const Radius tail = Radius.circular(6);
    final Widget bubble = Container(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.sizeOf(context).width * 0.78,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        gradient: mine ? AppGradients.brand : null,
        color: mine ? null : theme.cardTheme.color ?? theme.colorScheme.surface,
        border: mine
            ? null
            : Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadiusDirectional.only(
          topStart: r,
          topEnd: r,
          bottomStart: mine ? r : tail,
          bottomEnd: mine ? tail : r,
        ),
      ),
      child: SelectableText(
        text,
        style: theme.textTheme.bodyLarge?.copyWith(
          color: mine ? Colors.white : null,
          height: 1.45,
        ),
      ),
    );
    return Row(
      mainAxisAlignment: mine ? MainAxisAlignment.end : MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: <Widget>[
        if (!mine) ...<Widget>[const _Avatar(), const SizedBox(width: 8)],
        Flexible(child: bubble),
      ],
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar();

  @override
  Widget build(BuildContext context) => Container(
    width: 30,
    height: 30,
    decoration: BoxDecoration(
      gradient: AppGradients.brand,
      borderRadius: BorderRadius.circular(10),
    ),
    child: const Icon(
      Icons.auto_awesome_rounded,
      size: 17,
      color: Colors.white,
    ),
  );
}

class _Thinking extends StatelessWidget {
  const _Thinking();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Row(
      children: <Widget>[
        const _Avatar(),
        const SizedBox(width: 10),
        const SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2.2),
        ),
        const SizedBox(width: 10),
        Text(
          S.assistantThinking,
          style: Theme.of(context).textTheme.bodyMedium
              ?.copyWith(color: AppTheme.muted(context)),
        ),
      ],
    ),
  );
}

class _ClaimList extends StatelessWidget {
  const _ClaimList({required this.claims, required this.onOpen});

  final List<Claim> claims;
  final void Function(int claimId)? onOpen;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsetsDirectional.only(start: 38),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: <Widget>[
            for (int i = 0; i < claims.length; i++) ...<Widget>[
              if (i > 0) const Divider(height: 1),
              InkWell(
                onTap: onOpen == null ? null : () => onOpen!(claims[i].id),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  child: Row(
                    children: <Widget>[
                      IconBubble(
                        icon: AccidentVisual.icon(claims[i].accidentType),
                        color: AccidentVisual.color(claims[i].accidentType),
                        size: 34,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Directionality(
                              textDirection: TextDirection.ltr,
                              child: Text(
                                claims[i].vehiclePlate ?? S.noPlate,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                            Text(
                              claims[i].customerName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: AppTheme.muted(context),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 6),
                      StatusChip(statusKey: claims[i].statusKey, compact: true),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ActionCardView extends StatelessWidget {
  const _ActionCardView({required this.card, required this.onOpen});

  final ActionCard card;
  final void Function(int claimId)? onOpen;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final (
      IconData icon,
      Color color,
      String title,
    ) = switch (card.action.kind) {
      AssistantActionKind.createClaim => (
        Icons.note_add_rounded,
        AppColors.mint,
        S.assistantActionCreate,
      ),
      AssistantActionKind.setReminder => (
        Icons.notifications_active_rounded,
        AppColors.amber,
        S.assistantActionReminder,
      ),
      AssistantActionKind.clearReminder => (
        Icons.notifications_off_rounded,
        AppColors.rose,
        S.assistantActionClearReminder,
      ),
      AssistantActionKind.status => (
        Icons.flag_rounded,
        AppColors.sky,
        S.assistantActionStatus,
      ),
      AssistantActionKind.note => (
        Icons.sticky_note_2_rounded,
        AppColors.violet,
        S.assistantActionNote,
      ),
    };
    final int? openId = card.claimId;
    return Padding(
      padding: const EdgeInsetsDirectional.only(start: 38),
      child: Card(
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: color.withValues(alpha: 0.45), width: 1.4),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                children: <Widget>[
                  IconBubble(icon: icon, color: color, size: 36, solid: true),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          title,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        if (card.state == ActionState.pending)
                          Text(
                            S.assistantReviewAction,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: AppTheme.muted(context),
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (card.state != ActionState.pending)
                    _StateBadge(state: card.state),
                ],
              ),
              const SizedBox(height: 12),
              for (final (String label, String value) in card.action.rows)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      SizedBox(
                        width: 110,
                        child: Text(
                          label,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: AppTheme.muted(context),
                          ),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          value,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              if (card.state == ActionState.pending) ...<Widget>[
                const SizedBox(height: 8),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: OutlinedButton(
                        key: const Key('assistant-cancel-action'),
                        onPressed: () => card.decide(false),
                        child: Text(S.cancel),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton.icon(
                        key: const Key('assistant-confirm-action'),
                        onPressed: () => card.decide(true),
                        icon: const Icon(Icons.check_rounded),
                        label: Text(S.confirm),
                      ),
                    ),
                  ],
                ),
              ],
              if (card.state == ActionState.done &&
                  openId != null &&
                  onOpen != null)
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: TextButton.icon(
                    onPressed: () => onOpen!(openId),
                    icon: const Icon(Icons.open_in_new_rounded, size: 18),
                    label: Text(S.assistantOpenClaim),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StateBadge extends StatelessWidget {
  const _StateBadge({required this.state});

  final ActionState state;

  @override
  Widget build(BuildContext context) {
    final (IconData icon, Color color, String label) = switch (state) {
      ActionState.done => (
        Icons.check_circle_rounded,
        AppColors.mint,
        S.assistantStateDone,
      ),
      ActionState.cancelled => (
        Icons.block_rounded,
        AppTheme.muted(context),
        S.assistantStateCancelled,
      ),
      ActionState.failed => (
        Icons.error_rounded,
        AppColors.rose,
        S.assistantStateFailed,
      ),
      _ => (
        Icons.hourglass_top_rounded,
        AppColors.amber,
        S.assistantStateRunning,
      ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium
                ?.copyWith(color: color, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.error, required this.onOpenSettings});

  final ErrorMessage error;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final String message = switch (error.code) {
      'invalid-key' => S.assistantErrInvalidKey,
      'rate-limit' => S.assistantErrRateLimit,
      'model-not-found' => S.assistantErrModel,
      'network' => S.assistantErrNetwork,
      'empty' => S.assistantErrEmpty,
      _ => S.assistantErrOther(
        error.detail.isEmpty ? error.code : error.detail,
      ),
    };
    final bool fixInSettings =
        error.code == 'invalid-key' || error.code == 'model-not-found';
    return Padding(
      padding: const EdgeInsetsDirectional.only(start: 38),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.rose.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.rose.withValues(alpha: 0.35)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Icon(Icons.error_outline_rounded, color: AppColors.rose),
                const SizedBox(width: 8),
                Expanded(child: Text(message)),
              ],
            ),
            if (fixInSettings)
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: TextButton(
                  onPressed: onOpenSettings,
                  child: Text(S.assistantSettingsTitle),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _InputBar extends StatelessWidget {
  const _InputBar({
    required this.listening,
    required this.voiceLabel,
    required this.onMic,
    required this.onMicLongPress,
    required this.controller,
    required this.busy,
    required this.onSend,
  });

  final bool listening;

  /// Short tag of the speech language shown on the mic.
  final String voiceLabel;
  final VoidCallback onMic;
  final VoidCallback onMicLongPress;
  final TextEditingController controller;
  final bool busy;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        border: Border(
          top: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: <Widget>[
          _MicButton(
            listening: listening,
            enabled: !busy,
            label: voiceLabel,
            onTap: onMic,
            onLongPress: onMicLongPress,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              key: const Key('assistant-input'),
              controller: controller,
              readOnly: listening,
              minLines: 1,
              maxLines: 5,
              textInputAction: TextInputAction.newline,
              keyboardType: TextInputType.multiline,
              decoration: InputDecoration(
                hintText: listening
                    ? S.assistantMicListening
                    : S.assistantInputHint,
                filled: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 12,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(26),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(26),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(26),
                  borderSide: BorderSide(
                    color: theme.colorScheme.primary,
                    width: 1.5,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: controller,
            builder: (BuildContext context, TextEditingValue value, _) {
              final bool enabled = !busy && value.text.trim().isNotEmpty;
              return Semantics(
                button: true,
                label: S.assistantSend,
                child: GestureDetector(
                  key: const Key('assistant-send'),
                  onTap: enabled ? onSend : null,
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 150),
                    opacity: enabled ? 1 : 0.45,
                    child: Container(
                      width: 50,
                      height: 50,
                      decoration: const BoxDecoration(
                        gradient: AppGradients.brand,
                        shape: BoxShape.circle,
                      ),
                      child: busy
                          ? const Padding(
                              padding: EdgeInsets.all(15),
                              child: CircularProgressIndicator(
                                strokeWidth: 2.2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(
                              Icons.arrow_upward_rounded,
                              color: Colors.white,
                            ),
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

/// Round mic button: tap to talk, long press to switch the speech language.
/// Turns red and pulses while listening.
class _MicButton extends StatefulWidget {
  const _MicButton({
    required this.listening,
    required this.enabled,
    required this.label,
    required this.onTap,
    required this.onLongPress,
  });

  final bool listening;
  final bool enabled;
  final String label;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  State<_MicButton> createState() => _MicButtonState();
}

class _MicButtonState extends State<_MicButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void didUpdateWidget(covariant _MicButton old) {
    super.didUpdateWidget(old);
    if (widget.listening && !_pulse.isAnimating) {
      _pulse.repeat(reverse: true);
    } else if (!widget.listening && _pulse.isAnimating) {
      _pulse.stop();
      _pulse.value = 0;
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool on = widget.listening;
    return Tooltip(
      message: S.assistantMicTooltip,
      child: Semantics(
        button: true,
        label: S.assistantMicTooltip,
        child: GestureDetector(
          key: const Key('assistant-mic'),
          onTap: widget.enabled || on ? widget.onTap : null,
          onLongPress: widget.enabled ? widget.onLongPress : null,
          child: AnimatedBuilder(
            animation: _pulse,
            builder: (BuildContext context, Widget? child) => Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: on
                    ? AppColors.rose
                    : theme.colorScheme.surfaceContainerHighest,
                boxShadow: on
                    ? <BoxShadow>[
                        BoxShadow(
                          color: AppColors.rose.withValues(alpha: 0.45),
                          blurRadius: 6 + 14 * _pulse.value,
                          spreadRadius: 1 + 5 * _pulse.value,
                        ),
                      ]
                    : null,
              ),
              child: child,
            ),
            child: Stack(
              alignment: Alignment.center,
              children: <Widget>[
                Icon(
                  on ? Icons.stop_rounded : Icons.mic_rounded,
                  color: on
                      ? Colors.white
                      : widget.enabled
                      ? theme.colorScheme.primary
                      : AppTheme.muted(context),
                  size: 26,
                ),
                if (!on)
                  PositionedDirectional(
                    bottom: 9,
                    end: 9,
                    child: Text(
                      widget.label,
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontSize: 9,
                        height: 1,
                        fontWeight: FontWeight.w900,
                        color: AppTheme.muted(context),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Key / model settings
// -----------------------------------------------------------------------------

class _KeySheet extends StatefulWidget {
  const _KeySheet({required this.keyStore, required this.transport});

  final AssistantKeyStore keyStore;
  final GeminiTransport? transport;

  @override
  State<_KeySheet> createState() => _KeySheetState();
}

class _KeySheetState extends State<_KeySheet> {
  final TextEditingController _key = TextEditingController();
  final TextEditingController _model = TextEditingController();
  bool _hasKey = false;
  bool _obscure = true;
  bool _testing = false;
  String? _message;
  bool _ok = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    String? key;
    String? model;
    try {
      key = await widget.keyStore.readKey();
      model = await widget.keyStore.readModel();
    } on Object catch (_) {}
    if (!mounted) return;
    setState(() {
      _hasKey = key != null && key.isNotEmpty;
      _key.text = key ?? '';
      _model.text = (model == null || model.isEmpty)
          ? AssistantScreen.defaultModel
          : model;
    });
  }

  @override
  void dispose() {
    _key.dispose();
    _model.dispose();
    super.dispose();
  }

  Future<void> _testAndSave() async {
    final String key = _key.text.trim();
    final String model = _model.text.trim().isEmpty
        ? AssistantScreen.defaultModel
        : _model.text.trim();
    if (key.isEmpty) return;
    setState(() {
      _testing = true;
      _message = null;
    });
    String? error;
    try {
      await GeminiClient(
        apiKey: key,
        model: model,
        transport: widget.transport,
      ).ping();
    } on GeminiException catch (e) {
      error = switch (e.code) {
        'invalid-key' => S.assistantErrInvalidKey,
        'model-not-found' => S.assistantErrModel,
        'network' => S.assistantErrNetwork,
        'rate-limit' => S.assistantErrRateLimit,
        _ => S.assistantErrOther(e.detail.isEmpty ? e.code : e.detail),
      };
    } on Object catch (e) {
      error = S.assistantErrOther('$e');
    }
    if (error == null) {
      await widget.keyStore.writeKey(key);
      await widget.keyStore.writeModel(model);
    }
    if (!mounted) return;
    setState(() {
      _testing = false;
      _ok = error == null;
      _hasKey = _hasKey || _ok;
      _message = error ?? S.assistantConnected;
    });
    if (_ok) {
      await Future<void>.delayed(const Duration(milliseconds: 700));
      if (mounted) Navigator.of(context).pop(true);
    }
  }

  Future<void> _remove() async {
    await widget.keyStore.deleteKey();
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(S.assistantKeyRemoved)));
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        0,
        20,
        20 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            SectionTitle(
              icon: Icons.auto_awesome_rounded,
              title: S.assistantSettingsTitle,
              color: AppColors.violet,
            ),
            const SizedBox(height: 16),
            TextField(
              key: const Key('assistant-key-field'),
              controller: _key,
              obscureText: _obscure,
              autocorrect: false,
              enableSuggestions: false,
              textDirection: TextDirection.ltr,
              decoration: InputDecoration(
                labelText: S.assistantKeyLabel,
                prefixIcon: const Icon(Icons.key_rounded),
                suffixIcon: IconButton(
                  onPressed: () => setState(() => _obscure = !_obscure),
                  icon: Icon(
                    _obscure
                        ? Icons.visibility_rounded
                        : Icons.visibility_off_rounded,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('assistant-model-field'),
              controller: _model,
              autocorrect: false,
              textDirection: TextDirection.ltr,
              decoration: InputDecoration(
                labelText: S.assistantModelLabel,
                helperText: S.assistantModelHelp,
                helperMaxLines: 2,
                prefixIcon: const Icon(Icons.memory_rounded),
              ),
            ),
            const SizedBox(height: 16),
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: _key,
              builder: (BuildContext context, TextEditingValue v, _) =>
                  FilledButton.icon(
                    key: const Key('assistant-test-save'),
                    onPressed: _testing || v.text.trim().isEmpty
                        ? null
                        : _testAndSave,
                    icon: _testing
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.check_rounded),
                    label: Text(S.assistantTestSave),
                  ),
            ),
            if (_message != null) ...<Widget>[
              const SizedBox(height: 10),
              Text(
                _message!,
                key: const Key('assistant-key-message'),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: _ok ? AppColors.mint : AppColors.rose,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
            const SizedBox(height: 4),
            const _GetKeyButton(),
            if (_hasKey)
              TextButton.icon(
                key: const Key('assistant-remove-key'),
                onPressed: _testing ? null : _remove,
                style: TextButton.styleFrom(foregroundColor: AppColors.rose),
                icon: const Icon(Icons.delete_outline_rounded),
                label: Text(S.assistantRemoveKey),
              ),
          ],
        ),
      ),
    );
  }
}
