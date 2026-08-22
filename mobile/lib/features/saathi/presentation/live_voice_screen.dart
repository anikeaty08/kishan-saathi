import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../../core/models/app_models.dart';
import '../../../core/localization/app_strings.dart';
import '../../../core/theme/app_theme.dart';
import '../../shared/presentation/app_controller.dart';
import 'live_voice_session_controller.dart';

class LiveVoiceScreen extends StatefulWidget {
  const LiveVoiceScreen({super.key, required this.chatId, this.session});

  final String chatId;
  final LiveVoiceSessionController? session;

  @override
  State<LiveVoiceScreen> createState() => _LiveVoiceScreenState();
}

class _LiveVoiceScreenState extends State<LiveVoiceScreen>
    with WidgetsBindingObserver {
  late final AppController _app;
  late final LiveVoiceSessionController _session;

  @override
  void initState() {
    super.initState();
    _app = context.read<AppController>();
    _session =
        widget.session ??
        LiveVoiceSessionController(
          chatId: widget.chatId,
          transcribe: _app.transcribeChatVoice,
          sendMessage: _app.sendMessage,
          loadSpeech: _app.loadAssistantSpeech,
          messages: () => _chat?.messages ?? const [],
        );
    _session.addListener(_refresh);
    WidgetsBinding.instance.addObserver(this);
    _app.addListener(_handleChatUpdate);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _handleChatUpdate();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _app.removeListener(_handleChatUpdate);
    _session
      ..removeListener(_refresh)
      ..dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.hidden) {
      unawaited(_session.pause());
    }
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  ChatThreadModel? get _chat => _app.chats.cast<ChatThreadModel?>().firstWhere(
    (chat) => chat?.id == widget.chatId,
    orElse: () => null,
  );

  void _handleChatUpdate() {
    final chat = _chat;
    if (chat != null) _session.acceptMessages(chat.messages);
  }

  Future<void> _endAndClose() async {
    await _session.end();
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _primaryAction() async {
    switch (_session.state) {
      case LiveVoiceSessionState.ready:
        await _session.startListening();
      case LiveVoiceSessionState.listening:
        await _session.finishFarmerTurn(_chat?.messages ?? const []);
      case LiveVoiceSessionState.speaking:
        await _session.stopSaathiAndListen();
      case LiveVoiceSessionState.error:
        await _session.retry();
      case LiveVoiceSessionState.ended:
        if (mounted) Navigator.of(context).pop();
      case LiveVoiceSessionState.starting ||
          LiveVoiceSessionState.transcribing ||
          LiveVoiceSessionState.waiting:
        return;
    }
  }

  @override
  Widget build(BuildContext context) {
    final chat = _chat;
    if (chat == null) {
      return Scaffold(
        body: Center(child: Text(context.tr('conversationNotFound'))),
      );
    }
    final dark = Theme.of(context).brightness == Brightness.dark;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_endAndClose());
      },
      child: Scaffold(
        backgroundColor: dark
            ? const Color(0xFF0C1710)
            : const Color(0xFFF7F3E8),
        appBar: AppBar(
          automaticallyImplyLeading: false,
          leading: IconButton(
            tooltip: context.tr('endVoiceConversation'),
            onPressed: _endAndClose,
            icon: const Icon(LucideIcons.x),
          ),
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(context.tr('voiceWithSaathi')),
              Text(
                chat.scopeLabel ?? context.tr('thisConversation'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        body: SafeArea(
          top: false,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 600;
              return Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 720),
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      compact ? 18 : 32,
                      12,
                      compact ? 18 : 32,
                      18,
                    ),
                    child: SingleChildScrollView(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          minHeight: (constraints.maxHeight - 42).clamp(
                            0,
                            double.infinity,
                          ),
                        ),
                        child: IntrinsicHeight(
                          child: Column(
                            children: [
                              _ContextPill(label: chat.scopeLabel),
                              const Spacer(),
                              _VoiceOrb(state: _session.state),
                              const SizedBox(height: 24),
                              Semantics(
                                liveRegion: true,
                                child: Text(
                                  _stateTitle(_session.state),
                                  key: const ValueKey('live-voice-status'),
                                  textAlign: TextAlign.center,
                                  style: Theme.of(context)
                                      .textTheme
                                      .headlineSmall,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                _stateDescription(_session),
                                textAlign: TextAlign.center,
                                style: Theme.of(context).textTheme.bodyMedium
                                    ?.copyWith(color: AppColors.mutedInk),
                              ),
                              const SizedBox(height: 22),
                              _VoiceCaptions(
                                farmer: _session.farmerCaption,
                                assistant: _session.assistantCaption,
                              ),
                              const Spacer(),
                              _VoiceControls(
                                state: _session.state,
                                onPrimary: _primaryAction,
                                onPause: () => unawaited(_session.pause()),
                                onEnd: _endAndClose,
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'AI-generated voice · Your chat, farm and scan context stay linked.',
                                textAlign: TextAlign.center,
                                style: Theme.of(context).textTheme.labelSmall
                                    ?.copyWith(color: AppColors.mutedInk),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _ContextPill extends StatelessWidget {
  const _ContextPill({required this.label});

  final String? label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark
            ? Theme.of(context).colorScheme.surfaceContainerHigh
            : AppColors.mineral,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(LucideIcons.sprout, size: 16, color: AppColors.forest),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                label == null
                    ? context.tr('conversationContext')
                    : context.tr('usingContext', {'label': label}),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelLarge,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VoiceOrb extends StatefulWidget {
  const _VoiceOrb({required this.state});

  final LiveVoiceSessionState state;

  @override
  State<_VoiceOrb> createState() => _VoiceOrbState();
}

class _VoiceOrbState extends State<_VoiceOrb>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  bool get _animated => switch (widget.state) {
    LiveVoiceSessionState.listening ||
    LiveVoiceSessionState.waiting ||
    LiveVoiceSessionState.speaking => true,
    _ => false,
  };

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncMotion();
  }

  @override
  void didUpdateWidget(covariant _VoiceOrb oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncMotion();
  }

  void _syncMotion() {
    if (_animated && !MediaQuery.disableAnimationsOf(context)) {
      if (!_pulse.isAnimating) _pulse.repeat(reverse: true);
    } else {
      _pulse
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = switch (widget.state) {
      LiveVoiceSessionState.listening => AppColors.forest,
      LiveVoiceSessionState.speaking => const Color(0xFF347A56),
      LiveVoiceSessionState.error => AppColors.danger,
      _ => AppColors.youngLeaf,
    };
    final icon = switch (widget.state) {
      LiveVoiceSessionState.listening => LucideIcons.audioLines,
      LiveVoiceSessionState.speaking => LucideIcons.volume2,
      LiveVoiceSessionState.error => LucideIcons.triangleAlert,
      _ => LucideIcons.sprout,
    };
    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, child) => Container(
        key: const ValueKey('live-voice-orb'),
        width: 132 + (_pulse.value * 12),
        height: 132 + (_pulse.value * 12),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color.withValues(alpha: 0.12),
          border: Border.all(
            color: color.withValues(alpha: 0.22),
            width: 10 + (_pulse.value * 5),
          ),
        ),
        alignment: Alignment.center,
        child: Container(
          width: 88,
          height: 88,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          child: Icon(icon, color: Colors.white, size: 36),
        ),
      ),
    );
  }
}

class _VoiceCaptions extends StatelessWidget {
  const _VoiceCaptions({required this.farmer, required this.assistant});

  final String? farmer;
  final String? assistant;

  @override
  Widget build(BuildContext context) {
    if (farmer == null && assistant == null) {
      return Text(
        'Tap Start, speak naturally, then tap Stop & send.',
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodyLarge,
      );
    }
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 190),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (farmer != null)
              _Caption(label: context.tr('you'), text: farmer!, farmer: true),
            if (assistant != null) ...[
              const SizedBox(height: 10),
              _Caption(
                label: context.tr('saathi'),
                text: assistant!,
                farmer: false,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Caption extends StatelessWidget {
  const _Caption({
    required this.label,
    required this.text,
    required this.farmer,
  });

  final String label;
  final String text;
  final bool farmer;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: farmer
            ? AppColors.forest.withValues(alpha: 0.10)
            : Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 4),
            Text(text, style: Theme.of(context).textTheme.bodyMedium),
          ],
        ),
      ),
    );
  }
}

class _VoiceControls extends StatelessWidget {
  const _VoiceControls({
    required this.state,
    required this.onPrimary,
    required this.onPause,
    required this.onEnd,
  });

  final LiveVoiceSessionState state;
  final VoidCallback onPrimary;
  final VoidCallback onPause;
  final VoidCallback onEnd;

  @override
  Widget build(BuildContext context) {
    final busy = switch (state) {
      LiveVoiceSessionState.starting ||
      LiveVoiceSessionState.transcribing ||
      LiveVoiceSessionState.waiting => true,
      _ => false,
    };
    final label = switch (state) {
      LiveVoiceSessionState.ready => 'Start',
      LiveVoiceSessionState.listening => 'Stop & send',
      LiveVoiceSessionState.speaking => 'Stop Saathi',
      LiveVoiceSessionState.error => 'Try again',
      LiveVoiceSessionState.ended => 'Close',
      _ => 'Please wait',
    };
    final icon = switch (state) {
      LiveVoiceSessionState.listening ||
      LiveVoiceSessionState.speaking => LucideIcons.square,
      LiveVoiceSessionState.error => LucideIcons.rotateCcw,
      _ => LucideIcons.mic,
    };
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.start,
      spacing: 26,
      runSpacing: 14,
      children: [
        _RoundControl(
          key: const ValueKey('live-voice-end'),
          label: context.tr('end'),
          icon: LucideIcons.phoneOff,
          color: AppColors.danger,
          onTap: onEnd,
        ),
        if (state == LiveVoiceSessionState.listening ||
            state == LiveVoiceSessionState.speaking)
          _RoundControl(
            key: const ValueKey('live-voice-pause'),
            label: context.tr('pause'),
            icon: LucideIcons.micOff,
            color: AppColors.soil,
            onTap: onPause,
          ),
        _RoundControl(
          key: const ValueKey('live-voice-primary'),
          label: label,
          icon: icon,
          color: AppColors.forest,
          busy: busy,
          onTap: busy ? null : onPrimary,
        ),
      ],
    );
  }
}

class _RoundControl extends StatelessWidget {
  const _RoundControl({
    super.key,
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
    this.busy = false,
  });

  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton.filled(
          onPressed: onTap,
          style: IconButton.styleFrom(
            backgroundColor: color,
            foregroundColor: Colors.white,
            minimumSize: const Size.square(62),
          ),
          icon: busy
              ? const SizedBox.square(
                  dimension: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: Colors.white,
                  ),
                )
              : Icon(icon, size: 25),
        ),
        const SizedBox(height: 7),
        Text(label, style: Theme.of(context).textTheme.labelMedium),
      ],
    );
  }
}

String _stateTitle(LiveVoiceSessionState state) => switch (state) {
  LiveVoiceSessionState.ready => 'Ready when you are',
  LiveVoiceSessionState.starting => 'Starting microphone…',
  LiveVoiceSessionState.listening => 'Listening',
  LiveVoiceSessionState.transcribing => 'Understanding your words…',
  LiveVoiceSessionState.waiting => 'Saathi is thinking',
  LiveVoiceSessionState.speaking => 'Saathi is speaking',
  LiveVoiceSessionState.error => 'Voice paused',
  LiveVoiceSessionState.ended => 'Conversation ended',
};

String _stateDescription(LiveVoiceSessionController session) =>
    switch (session.state) {
      LiveVoiceSessionState.ready =>
        'Speak in the language that feels natural to you.',
      LiveVoiceSessionState.starting => 'Keep this screen open for a moment.',
      LiveVoiceSessionState.listening =>
        'Tap Stop & send when you have finished speaking.',
      LiveVoiceSessionState.transcribing =>
        'Your audio is being converted to text securely.',
      LiveVoiceSessionState.waiting =>
        'Your existing chat, scan and field context are being used.',
      LiveVoiceSessionState.speaking =>
        'You can stop Saathi and continue with your next question.',
      LiveVoiceSessionState.error =>
        'Check your connection and microphone, then try again.',
      LiveVoiceSessionState.ended => 'Your transcript remains in this chat.',
    };
