import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../../core/localization/app_strings.dart';
import '../../../core/models/app_models.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/ui/app_ui.dart';
import '../../shared/presentation/app_controller.dart';
import 'assistant_rich_text.dart';
import 'chat_composer.dart';
import 'live_voice_screen.dart';
import 'voice_composer_controller.dart';

class SaathiScreen extends StatefulWidget {
  const SaathiScreen({super.key});

  @override
  State<SaathiScreen> createState() => _SaathiScreenState();
}

class _SaathiScreenState extends State<SaathiScreen> {
  String _scope = 'all';
  bool _showArchived = false;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AppController>();
    final visibleChats = controller.chats
        .where((chat) {
          if (chat.archived != _showArchived) return false;
          return _scope == 'all' || chat.contextScope == _scope;
        })
        .toList(growable: false);
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('saathi')),
        actions: [
          IconButton(
            tooltip: _showArchived
                ? 'Show active conversations'
                : 'Show archived conversations',
            onPressed: () => setState(() => _showArchived = !_showArchived),
            icon: Icon(_showArchived ? LucideIcons.inbox : LucideIcons.archive),
          ),
          IconButton(
            tooltip: context.tr('newChat'),
            onPressed: () => context.push('/saathi/new'),
            icon: const Icon(LucideIcons.squarePen),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        top: false,
        bottom: false,
        child: AppContent(
          maxWidth: 980,
          padding: EdgeInsets.zero,
          child: ListView(
            key: const PageStorageKey('saathi-list'),
            padding: const EdgeInsets.only(bottom: 110),
            children: [
              _SaathiHeroStage(onStartChat: () => context.push('/saathi/new')),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 26),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          for (final filter
                              in const <(String, String, IconData)>[
                                ('all', 'All', LucideIcons.layoutList),
                                (
                                  'general',
                                  'General',
                                  LucideIcons.messageCircle,
                                ),
                                ('farm', 'Farm', LucideIcons.warehouse),
                                ('plot', 'Plot', LucideIcons.sprout),
                                ('scan', 'Leaf checks', LucideIcons.scanLine),
                              ]) ...[
                            FilterChip(
                              avatar: Icon(filter.$3, size: 15),
                              label: Text(filter.$2),
                              selected: _scope == filter.$1,
                              onSelected: (_) =>
                                  setState(() => _scope = filter.$1),
                            ),
                            const SizedBox(width: 7),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    SectionHeader(
                      title: _showArchived
                          ? 'Archived conversations'
                          : 'Recent conversations',
                      action: FilledButton.tonalIcon(
                        onPressed: () => context.push('/saathi/new'),
                        icon: const Icon(LucideIcons.plus, size: 18),
                        label: Text(context.tr('newChat')),
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (visibleChats.isEmpty)
                      Card(
                        child: AppStateView(
                          kind: AppStateKind.empty,
                          title: _showArchived
                              ? 'No archived conversations'
                              : 'No matching conversations',
                          message: _showArchived
                              ? 'Chats you archive will remain available here.'
                              : 'Choose another filter or start a general, farm, plot or leaf-check chat.',
                          actionLabel: _showArchived
                              ? null
                              : context.tr('newChat'),
                          onAction: _showArchived
                              ? null
                              : () => context.push('/saathi/new'),
                        ),
                      )
                    else
                      ...visibleChats.map((chat) => _ChatRow(chat: chat)),
                    if (!_showArchived) ...[
                      const SizedBox(height: 26),
                      Text(
                        'Good questions to ask',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 12),
                      for (final prompt in [
                        'What should I do before rain?',
                        'Why are lower leaves yellow?',
                        'Plan this week\'s field work',
                      ]) ...[
                        _PromptTile(
                          prompt: prompt,
                          onTap: () => context.push(
                            '/saathi/new?prompt=${Uri.encodeComponent(prompt)}',
                          ),
                        ),
                        const SizedBox(height: 8),
                      ],
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SaathiHeroStage extends StatelessWidget {
  const _SaathiHeroStage({required this.onStartChat});

  final VoidCallback onStartChat;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final inset = constraints.maxWidth >= 600;
        final textScale = MediaQuery.textScalerOf(context).scale(1);
        final visualBreathingRoom =
            (inset ? 58.0 : 42.0) - ((textScale - 1).clamp(0.0, 1.0) * 26);
        final radius = BorderRadius.circular(inset ? AppRadius.hero : 0);
        final stage = ClipRRect(
          borderRadius: radius,
          child: SizedBox(
            key: const ValueKey('saathi-hero-stage'),
            width: double.infinity,
            child: Stack(
              children: [
                Positioned.fill(
                  child: Image.asset(
                    'assets/images/crop_maize.jpg',
                    fit: BoxFit.cover,
                    alignment: const AlignmentDirectional(-0.58, -0.15),
                    semanticLabel: 'Healthy crop rows in warm morning light with a farmer in the field',
                    errorBuilder: (_, _, _) => Image.asset(
                      'assets/images/auth_field_hero.webp',
                      fit: BoxFit.cover,
                      alignment: Alignment.center,
                    ),
                  ),
                ),
                const Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        stops: [0, 0.42, 1],
                        colors: [
                          Color(0x26112417),
                          Color(0x70112417),
                          Color(0xF20A190F),
                        ],
                      ),
                    ),
                  ),
                ),
                ConstrainedBox(
                  constraints: BoxConstraints(minHeight: inset ? 350 : 330),
                  child: Padding(
                    padding: EdgeInsets.all(inset ? 28 : 20),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 11,
                            vertical: 7,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xB2132619),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.24),
                            ),
                          ),
                          child: Wrap(
                            crossAxisAlignment: WrapCrossAlignment.center,
                            spacing: 7,
                            runSpacing: 3,
                            children: [
                              const Icon(
                                LucideIcons.sparkles,
                                color: AppColors.amber,
                                size: 15,
                              ),
                              Text(
                                'Your field companion',
                                style: Theme.of(context).textTheme.labelMedium
                                    ?.copyWith(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w700,
                                    ),
                              ),
                            ],
                          ),
                        ),
                        SizedBox(height: visualBreathingRoom),
                        Container(
                          width: 42,
                          height: 4,
                          decoration: BoxDecoration(
                            color: AppColors.amber,
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                        const SizedBox(height: 14),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 590),
                          child: Text(
                            context.tr('saathiTitle'),
                            style: Theme.of(context).textTheme.headlineLarge
                                ?.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                  shadows: const [
                                    Shadow(
                                      color: Color(0x66000000),
                                      blurRadius: 16,
                                    ),
                                  ],
                                ),
                          ),
                        ),
                        const SizedBox(height: 7),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 620),
                          child: Text(
                            context.tr('saathiBody'),
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                                  color: Colors.white.withValues(alpha: 0.86),
                                  height: 1.45,
                                ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          onPressed: onStartChat,
                          icon: const Icon(LucideIcons.messageCircle, size: 18),
                          label: Text(context.tr('newChat')),
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: AppColors.forest,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
        if (!inset) return stage;
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
          child: stage,
        );
      },
    );
  }
}

class _ChatRow extends StatelessWidget {
  const _ChatRow({required this.chat});
  final ChatThreadModel chat;

  @override
  Widget build(BuildContext context) {
    final latest = chat.messages.lastOrNull;
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(AppRadius.large),
          boxShadow: [
            BoxShadow(
              color: AppColors.ink.withValues(alpha: 0.04),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: BorderRadius.circular(AppRadius.large),
            onTap: () => context.push('/saathi/chat/${chat.id}'),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: AppColors.leaf.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(AppRadius.medium),
                    ),
                    child: Icon(
                      switch (chat.contextScope) {
                        'farm' => LucideIcons.warehouse,
                        'plot' => LucideIcons.sprout,
                        'scan' => LucideIcons.scanLine,
                        _ => LucideIcons.messageCircle,
                      },
                      color: AppColors.forest,
                      size: 21,
                    ),
                  ),
                  const SizedBox(width: 13),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                chat.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                            ),
                            if (latest != null)
                              Text(
                                context.strings.formatShortDate(latest.sentAt),
                                style: Theme.of(context).textTheme.labelSmall
                                    ?.copyWith(color: AppColors.mutedInk),
                              ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          latest?.text ?? 'No messages yet',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: AppColors.mutedInk),
                        ),
                        if (chat.scopeLabel != null) ...[
                          const SizedBox(height: 7),
                          Text(
                            chat.scopeLabel!,
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(color: AppColors.leaf),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Icon(
                    LucideIcons.chevronRight,
                    size: 20,
                    color: AppColors.mutedInk,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class NewChatScreen extends StatefulWidget {
  const NewChatScreen({
    super.key,
    this.initialPrompt,
    this.initialScope,
    this.initialContextId,
  });
  final String? initialPrompt;
  final String? initialScope;
  final String? initialContextId;

  @override
  State<NewChatScreen> createState() => _NewChatScreenState();
}

class _NewChatScreenState extends State<NewChatScreen> {
  late String _scope;
  String? _contextId;
  late final TextEditingController _prompt;

  @override
  void initState() {
    super.initState();
    _scope = widget.initialScope ?? 'general';
    _contextId = widget.initialContextId;
    _prompt = TextEditingController(text: widget.initialPrompt);
  }

  @override
  void dispose() {
    _prompt.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final prompt = _prompt.text.trim();
    if (_scope != 'general' && _contextId == null) {
      showAppSnackBar(context, 'Choose the $_scope before continuing.');
      return;
    }
    if (prompt.isEmpty) {
      showAppSnackBar(context, 'Write the first question for Saathi.');
      return;
    }
    final controller = context.read<AppController>();
    late final ChatThreadModel chat;
    try {
      chat = await controller.createChat(scope: _scope, contextId: _contextId);
    } on ApiException catch (error) {
      if (mounted) showAppSnackBar(context, context.localizedError(error));
      return;
    }
    if (!mounted) return;
    context.go('/saathi/chat/${chat.id}');
    try {
      await controller.sendMessage(chat.id, prompt);
    } on ApiException {
      // The destination chat now owns the failed bubble and retry action.
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AppController>();
    final contextItems = switch (_scope) {
      'farm' => controller.farms.map((item) => (item.id, item.name)).toList(),
      'plot' =>
        controller.farms
            .expand((farm) => farm.plots.map((plot) => (plot.id, plot.name)))
            .toList(),
      'scan' =>
        controller.diagnoses.map((item) => (item.id, item.cropName)).toList(),
      _ => <(String, String)>[],
    };
    final selectedContextId = contextItems.any((item) => item.$1 == _contextId)
        ? _contextId
        : null;
    if (_contextId != null && selectedContextId == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _contextId != null) setState(() => _contextId = null);
      });
    }
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('newChat'))),
      body: SafeArea(
        top: false,
        child: AppContent(
          maxWidth: 680,
          child: ListView(
            padding: const EdgeInsets.only(top: 10, bottom: 32),
            children: [
              Text(
                'What should Saathi use?',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 8),
              Text(
                'A narrow scope gives more relevant answers and keeps context under your control.',
                style: Theme.of(context).textTheme.bodyLarge
                    ?.copyWith(color: AppColors.mutedInk),
              ),
              const SizedBox(height: 22),
              SegmentedButton<String>(
                segments: [
                  ButtonSegment(
                    value: 'general',
                    icon: const Icon(LucideIcons.messageCircle),
                    label: Text(context.tr('general')),
                  ),
                  ButtonSegment(
                    value: 'farm',
                    icon: const Icon(LucideIcons.warehouse),
                    label: Text(context.tr('farmScope')),
                  ),
                  ButtonSegment(
                    value: 'plot',
                    icon: const Icon(LucideIcons.sprout),
                    label: Text(context.tr('plotScope')),
                  ),
                  const ButtonSegment(
                    value: 'scan',
                    icon: Icon(LucideIcons.scanLine),
                    label: Text('Leaf check'),
                  ),
                ],
                selected: {_scope},
                showSelectedIcon: false,
                onSelectionChanged: (value) => setState(() {
                  _scope = value.first;
                  _contextId = null;
                }),
              ),
              if (_scope != 'general') ...[
                const SizedBox(height: 16),
                if (contextItems.isEmpty)
                  _MissingChatContext(scope: _scope)
                else
                  DropdownButtonFormField<String>(
                    initialValue: selectedContextId,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText:
                          'Choose ${_scope == 'scan' ? 'leaf check' : _scope}',
                    ),
                    items: contextItems
                        .map(
                          (item) => DropdownMenuItem(
                            value: item.$1,
                            child: Text(item.$2),
                          ),
                        )
                        .toList(),
                    onChanged: (value) => setState(() => _contextId = value),
                  ),
              ],
              const SizedBox(height: 22),
              TextField(
                controller: _prompt,
                minLines: 4,
                maxLines: 7,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  labelText: context.tr('askHint'),
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: controller.busy ? null : _create,
                icon: const Icon(LucideIcons.send, size: 18),
                label: controller.busy
                    ? const SizedBox.square(
                        dimension: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(context.tr('send')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MissingChatContext extends StatelessWidget {
  const _MissingChatContext({required this.scope});

  final String scope;

  @override
  Widget build(BuildContext context) {
    final (icon, title, message, action, route) = switch (scope) {
      'farm' => (
        LucideIcons.warehouse,
        'No farm available',
        'Create a farm first, then return here to connect this conversation.',
        'Create farm',
        '/farm/add',
      ),
      'plot' => (
        LucideIcons.sprout,
        'No plot available',
        'Add a plot inside a farm before starting a plot conversation.',
        'Open farms',
        '/farm',
      ),
      _ => (
        LucideIcons.scanLine,
        'No leaf check available',
        'Complete a leaf check first so Saathi can use its result safely.',
        'Start leaf check',
        '/scan',
      ),
    };
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.mineral,
        borderRadius: BorderRadius.circular(AppRadius.large),
        border: Border.all(color: AppColors.leaf.withValues(alpha: 0.18)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppColors.forest, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 4),
                Text(message, style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 10),
                TextButton.icon(
                  onPressed: () => context.push(route),
                  icon: const Icon(LucideIcons.arrowUpRight, size: 16),
                  label: Text(action),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class ChatDetailScreen extends StatefulWidget {
  const ChatDetailScreen({super.key, required this.chatId});
  final String chatId;

  @override
  State<ChatDetailScreen> createState() => _ChatDetailScreenState();
}

class _ChatDetailScreenState extends State<ChatDetailScreen> {
  final _message = TextEditingController();
  final _messageFocus = FocusNode();
  final _scrollController = ScrollController();
  Timer? _draftDebounce;
  late final AppController _controller;
  late final VoiceComposerController _voice;
  int _lastMessageCount = 0;
  final Set<String> _decidingProposalIds = {};
  final Map<String, bool> _messageFeedback = {};

  @override
  void initState() {
    super.initState();
    _controller = context.read<AppController>();
    _voice = VoiceComposerController(
      transcribe: _controller.transcribeChatVoice,
      loadSpeech: _controller.loadAssistantSpeech,
    )..addListener(_handleVoiceUpdate);
    _message.text = _controller.chatDraft(widget.chatId);
    _message.addListener(_scheduleDraftSave);
    _controller.addListener(_handleChatUpdate);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        await _controller.loadChat(widget.chatId);
        final loadedChat = _controller.chats
            .cast<ChatThreadModel?>()
            .firstWhere(
              (item) => item?.id == widget.chatId,
              orElse: () => null,
            );
        final caseId = loadedChat?.diagnosisCaseId;
        if (caseId != null &&
            !_controller.diagnoses.any((item) => item.id == caseId)) {
          await _controller.loadDiagnosis(caseId);
        }
      } on ApiException catch (error) {
        if (mounted) showAppSnackBar(context, context.localizedError(error));
      }
    });
  }

  @override
  void dispose() {
    _draftDebounce?.cancel();
    unawaited(_controller.saveChatDraft(widget.chatId, _message.text));
    _message.removeListener(_scheduleDraftSave);
    _controller.removeListener(_handleChatUpdate);
    _message.dispose();
    _messageFocus.dispose();
    _voice
      ..removeListener(_handleVoiceUpdate)
      ..dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _message.text;
    if (text.trim().isEmpty) return;
    _message.clear();
    try {
      await _controller.sendMessage(widget.chatId, text);
      await _controller.saveChatDraft(widget.chatId, '');
    } on ApiException catch (error) {
      if (mounted) {
        showAppSnackBar(context, context.localizedError(error));
      }
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 240),
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  void _handleChatUpdate() {
    final chat = _controller.chats.cast<ChatThreadModel?>().firstWhere(
      (item) => item?.id == widget.chatId,
      orElse: () => null,
    );
    final count = chat?.messages.length ?? 0;
    if (count == _lastMessageCount) return;
    _lastMessageCount = count;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      final position = _scrollController.position;
      final nearBottom = position.maxScrollExtent - position.pixels < 240;
      if (!nearBottom) return;
      _scrollController.animateTo(
        position.maxScrollExtent,
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
    });
  }

  void _scheduleDraftSave() {
    _draftDebounce?.cancel();
    _draftDebounce = Timer(const Duration(milliseconds: 350), () {
      unawaited(_controller.saveChatDraft(widget.chatId, _message.text));
    });
  }

  void _useFollowUp(String question) {
    _message
      ..text = question
      ..selection = TextSelection.collapsed(offset: question.length);
    _messageFocus.requestFocus();
  }

  Future<void> _copyMessage(ChatMessageModel message) async {
    await Clipboard.setData(ClipboardData(text: message.text));
    if (mounted) showAppSnackBar(context, 'Response copied.');
  }

  Future<void> _readMessage(ChatMessageModel message) async {
    try {
      final usedAiVoice = await _voice.toggleSpeech(
        chatId: widget.chatId,
        messageId: message.id,
      );
      if (usedAiVoice && mounted && _voice.speakingMessageId != null) {
        showAppSnackBar(context, context.tr('voiceAiDisclosure'));
      }
    } on ApiException catch (error) {
      if (mounted) showAppSnackBar(context, context.localizedError(error));
    } catch (_) {
      if (mounted) showAppSnackBar(context, context.tr('voiceUnavailable'));
    }
  }

  void _handleVoiceUpdate() {
    if (mounted) setState(() {});
  }

  Future<void> _toggleRecording() async {
    if (_voice.isTranscribing) return;
    if (_voice.isRecording) {
      await _finishVoiceRecording();
      return;
    }
    if (!_controller.canUseLiveServices) {
      showAppSnackBar(context, context.tr('error.VOICE_REQUIRES_CONNECTION'));
      return;
    }
    try {
      await _voice.startRecording(onLimitReached: _finishVoiceRecording);
    } on ApiException catch (error) {
      if (mounted) showAppSnackBar(context, context.localizedError(error));
    } catch (_) {
      if (mounted) showAppSnackBar(context, context.tr('voiceUnavailable'));
    }
  }

  Future<void> _finishVoiceRecording() async {
    try {
      final transcript = await _voice.stopAndTranscribe(widget.chatId);
      if (transcript == null || transcript.trim().isEmpty || !mounted) return;
      final current = _message.text.trim();
      final composed = current.isEmpty
          ? transcript.trim()
          : '$current ${transcript.trim()}';
      _message
        ..text = composed
        ..selection = TextSelection.collapsed(offset: composed.length);
      _messageFocus.requestFocus();
      showAppSnackBar(context, context.tr('voiceTranscriptReady'));
    } on ApiException catch (error) {
      if (mounted) showAppSnackBar(context, context.localizedError(error));
    } catch (_) {
      if (mounted) showAppSnackBar(context, context.tr('voiceUnavailable'));
    }
  }

  Future<void> _cancelRecording() async {
    await _voice.cancelRecording();
  }

  Future<void> _openLiveVoice() async {
    if (!_controller.canUseLiveServices) {
      showAppSnackBar(context, context.tr('error.VOICE_REQUIRES_CONNECTION'));
      return;
    }
    await _voice.stopSpeech();
    if (!mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => LiveVoiceScreen(chatId: widget.chatId),
      ),
    );
  }

  void _setFeedback(ChatMessageModel message, bool helpful) {
    setState(() => _messageFeedback[message.id] = helpful);
    showAppSnackBar(
      context,
      helpful
          ? 'Marked as helpful on this device.'
          : 'Feedback noted on this device.',
    );
  }

  void _openAttachmentMenu(ChatThreadModel chat) {
    final retake = chat.diagnosisCaseId == null
        ? ''
        : '&retake=${Uri.encodeQueryComponent(chat.diagnosisCaseId!)}';
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.fromLTRB(18, 4, 18, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              chat.diagnosisCaseId == null
                  ? 'Start a leaf check'
                  : 'Add follow-up leaf photos',
              style: Theme.of(sheetContext).textTheme.titleLarge,
            ),
            const SizedBox(height: 6),
            Text(
              chat.diagnosisCaseId == null
                  ? 'Photos are processed by the trained leaf model before Saathi can discuss the result.'
                  : 'New photos stay linked to this scan and its conversation.',
              style: Theme.of(sheetContext).textTheme.bodyMedium
                  ?.copyWith(color: AppColors.mutedInk),
            ),
            const SizedBox(height: 14),
            ListTile(
              leading: const Icon(LucideIcons.camera),
              title: const Text('Take a photo'),
              onTap: () {
                Navigator.pop(sheetContext);
                context.push('/scan?source=camera$retake');
              },
            ),
            ListTile(
              leading: const Icon(LucideIcons.images),
              title: const Text('Choose from gallery'),
              onTap: () {
                Navigator.pop(sheetContext);
                context.push('/scan?source=gallery$retake');
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showContextSheet(ChatThreadModel chat) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(LucideIcons.brain, color: AppColors.forest),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Context Saathi can use',
                    style: Theme.of(sheetContext).textTheme.titleLarge,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              chat.scopeLabel == null
                  ? 'Only messages in this conversation are used. You can connect it to a farm or plot from conversation options.'
                  : 'This conversation can use relevant records linked to ${chat.scopeLabel}. Saathi receives filtered facts, not your complete history.',
              style: Theme.of(sheetContext).textTheme.bodyLarge,
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final chat = context
        .watch<AppController>()
        .chats
        .cast<ChatThreadModel?>()
        .firstWhere((item) => item?.id == widget.chatId, orElse: () => null);
    if (chat == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const AppStateView(
          kind: AppStateKind.error,
          title: 'Conversation not found',
          message: 'It may have been archived or deleted.',
        ),
      );
    }
    final controller = context.watch<AppController>();
    final responding = controller.isChatResponding(chat.id);
    final queued = controller.queuedChatTurns(chat.id);
    final hasOlder = controller.hasOlderChatMessages(chat.id);
    final proposals = controller.reminderProposals
        .where(
          (proposal) =>
              proposal.chatId == chat.id && proposal.status == 'pending',
        )
        .toList(growable: false);
    final linkedDiagnosis = chat.diagnosisCaseId == null
        ? null
        : controller.diagnoses.cast<DiagnosisCaseModel?>().firstWhere(
            (item) => item?.id == chat.diagnosisCaseId,
            orElse: () => null,
          );
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: dark ? const Color(0xFF0E1812) : const Color(0xFFF8F5EC),
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(chat.title, maxLines: 1, overflow: TextOverflow.ellipsis),
            Text(
              _chatScopeCaption(chat),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Conversation options',
            onPressed: () => _showConversationOptions(chat),
            icon: const Icon(LucideIcons.ellipsisVertical),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 720),
                  child: ListView(
                    controller: _scrollController,
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
                    children: [
                      if (chat.messages.isEmpty && chat.scope == 'general')
                        _GeneralChatWelcome(onPrompt: _useFollowUp)
                      else
                        Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: _ConversationContextPill(
                            chat: chat,
                            onTap: () => _showContextSheet(chat),
                          ),
                        ),
                      if (linkedDiagnosis != null) ...[
                        const SizedBox(height: 12),
                        _LinkedScanCard(
                          diagnosis: linkedDiagnosis,
                          onTap: () => context.push(
                            '/scan/result/${linkedDiagnosis.id}',
                          ),
                        ),
                      ],
                      if (hasOlder) ...[
                        const SizedBox(height: 8),
                        Center(
                          child: TextButton.icon(
                            onPressed:
                                controller.isLoadingOlderChatMessages(chat.id)
                                ? null
                                : _loadOlderMessages,
                            icon: controller.isLoadingOlderChatMessages(chat.id)
                                ? const SizedBox.square(
                                    dimension: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(LucideIcons.history, size: 17),
                            label: Text(
                              controller.isLoadingOlderChatMessages(chat.id)
                                  ? context.tr('loading')
                                  : context.tr('viewAll'),
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 18),
                      for (var index = 0; index < chat.messages.length; index++)
                        _MessageEntry(
                          message: chat.messages[index],
                          showAssistantLabel:
                              chat.messages[index].author ==
                                  ChatAuthor.assistant &&
                              (index == 0 ||
                                  chat.messages[index - 1].author !=
                                      ChatAuthor.assistant),
                          onRetry:
                              chat.messages[index].delivery ==
                                  ChatDelivery.failed
                              ? () => _retry(chat.messages[index])
                              : null,
                          onFollowUp: _useFollowUp,
                          onCopy: () => _copyMessage(chat.messages[index]),
                          onSpeak: () => _readMessage(chat.messages[index]),
                          speaking:
                              _voice.speakingMessageId ==
                              chat.messages[index].id,
                          feedback: _messageFeedback[chat.messages[index].id],
                          onFeedback: (helpful) =>
                              _setFeedback(chat.messages[index], helpful),
                        ),
                      if (responding) _ThinkingIndicator(queuedCount: queued),
                    ],
                  ),
                ),
              ),
            ),
            for (final proposal in proposals)
              AppContent(
                maxWidth: 760,
                child: _ReminderProposalCard(
                  proposal: proposal,
                  deciding: _decidingProposalIds.contains(proposal.id),
                  onDecision: (accepted) =>
                      _decideProposal(proposal.id, accepted: accepted),
                ),
              ),
            if (chat.archived)
              AppContent(
                maxWidth: 760,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: InlineNotice(
                    title: 'Archived conversation',
                    message: 'Restore this conversation before sending another message.',
                    icon: LucideIcons.archive,
                    color: AppColors.amber,
                    action: TextButton(
                      onPressed: () => _controller.restoreChat(chat.id),
                      child: const Text('Restore'),
                    ),
                  ),
                ),
              )
            else
              ChatComposer(
                controller: _message,
                focusNode: _messageFocus,
                onAttach: () => _openAttachmentMenu(chat),
                voiceState: _voice.state,
                voiceElapsed: _voice.elapsed,
                onVoice: _toggleRecording,
                onLiveVoice: _openLiveVoice,
                onCancelVoice: _cancelRecording,
                onSend: _send,
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _retry(ChatMessageModel message) async {
    try {
      await _controller.retryChatMessage(widget.chatId, message.id);
    } on ApiException catch (error) {
      if (mounted) showAppSnackBar(context, context.localizedError(error));
    }
  }

  Future<void> _loadOlderMessages() async {
    final oldExtent = _scrollController.hasClients
        ? _scrollController.position.maxScrollExtent
        : 0.0;
    try {
      await _controller.loadOlderChatMessages(widget.chatId);
    } on ApiException catch (error) {
      if (mounted) showAppSnackBar(context, context.localizedError(error));
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      final addedExtent =
          _scrollController.position.maxScrollExtent - oldExtent;
      _scrollController.jumpTo(
        (_scrollController.position.pixels + addedExtent).clamp(
          0,
          _scrollController.position.maxScrollExtent,
        ),
      );
    });
  }

  Future<void> _decideProposal(
    String proposalId, {
    required bool accepted,
  }) async {
    if (!_decidingProposalIds.add(proposalId)) return;
    setState(() {});
    try {
      await _controller.decideReminderProposal(proposalId, accepted: accepted);
    } on ApiException catch (error) {
      if (mounted) showAppSnackBar(context, context.localizedError(error));
    } finally {
      if (mounted) {
        setState(() => _decidingProposalIds.remove(proposalId));
      }
    }
  }

  Future<void> _showConversationOptions(ChatThreadModel chat) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(LucideIcons.pencil),
              title: const Text('Rename conversation'),
              onTap: () => Navigator.pop(context, 'rename'),
            ),
            if (chat.scope == 'general')
              ListTile(
                leading: const Icon(LucideIcons.folderSymlink),
                title: const Text('Connect to farm or plot'),
                subtitle: const Text(
                  'Save only relevant facts to shared memory.',
                ),
                onTap: () => Navigator.pop(context, 'connect'),
              ),
            if (chat.scope == 'general')
              ListTile(
                leading: const Icon(LucideIcons.unlink),
                title: const Text('Disconnect shared memory'),
                onTap: () => Navigator.pop(context, 'disconnect'),
              ),
            if (chat.archived)
              ListTile(
                leading: const Icon(LucideIcons.archiveRestore),
                title: const Text('Restore conversation'),
                onTap: () => Navigator.pop(context, 'restore'),
              )
            else
              ListTile(
                leading: const Icon(LucideIcons.archive),
                title: const Text('Archive conversation'),
                onTap: () => Navigator.pop(context, 'archive'),
              ),
            ListTile(
              leading: const Icon(LucideIcons.trash2, color: Colors.red),
              title: const Text(
                'Delete conversation',
                style: TextStyle(color: Colors.red),
              ),
              onTap: () => Navigator.pop(context, 'delete'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    try {
      switch (action) {
        case 'rename':
          await _rename(chat);
          break;
        case 'connect':
          await _connectMemory(chat);
          break;
        case 'disconnect':
          await _controller.disconnectChatMemory(chat.id);
          if (mounted) {
            showAppSnackBar(
              context,
              'Conversation disconnected from shared memory.',
              success: true,
            );
          }
          break;
        case 'archive':
          await _controller.archiveChat(chat.id);
          if (mounted) context.go('/saathi');
          break;
        case 'restore':
          await _controller.restoreChat(chat.id);
          break;
        case 'delete':
          final confirmed = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Delete this conversation?'),
              content: const Text(
                'Its messages will be removed. Plot memories are managed separately in Memory settings.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Delete'),
                ),
              ],
            ),
          );
          if (confirmed ?? false) {
            await _controller.deleteChat(chat.id);
            if (mounted) context.go('/saathi');
          }
          break;
      }
    } on ApiException catch (error) {
      if (mounted) showAppSnackBar(context, context.localizedError(error));
    }
  }

  Future<void> _rename(ChatThreadModel chat) async {
    final controller = TextEditingController(text: chat.title);
    final title = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename conversation'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 150,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(labelText: 'Conversation title'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (!mounted) return;
    if (title != null && title.isNotEmpty && title != chat.title) {
      await _controller.renameChat(chat.id, title);
    }
  }

  Future<void> _connectMemory(ChatThreadModel chat) async {
    final controller = context.read<AppController>();
    final targets = <(String, String, String)>[
      for (final farm in controller.farms) ('farm', farm.id, farm.name),
      for (final farm in controller.farms)
        for (final plot in farm.plots)
          ('plot', plot.id, '${farm.name} · ${plot.name}'),
    ];
    if (targets.isEmpty) {
      showAppSnackBar(
        context,
        'Create a farm or plot before connecting this conversation.',
      );
      return;
    }
    final selected = await showModalBottomSheet<(String, String)>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: AppContent(
          maxWidth: 620,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Connect conversation',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 8),
              Text(
                'Only confirmed, relevant facts are copied. The full conversation is never stored as memory.',
                style: Theme.of(context).textTheme.bodyMedium
                    ?.copyWith(color: AppColors.mutedInk),
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 360,
                child: ListView(
                  children: targets
                      .map(
                        (target) => ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(
                            target.$1 == 'farm'
                                ? LucideIcons.warehouse
                                : LucideIcons.sprout,
                          ),
                          title: Text(target.$3),
                          subtitle: Text(
                            target.$1 == 'farm'
                                ? 'Farm-wide memory'
                                : 'Isolated plot memory',
                          ),
                          trailing: const Icon(LucideIcons.chevronRight),
                          onTap: () =>
                              Navigator.pop(context, (target.$1, target.$2)),
                        ),
                      )
                      .toList(growable: false),
                ),
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
    if (selected == null || !mounted) return;
    await controller.connectChatMemory(
      chatId: chat.id,
      targetType: selected.$1,
      targetId: selected.$2,
    );
    if (mounted) {
      showAppSnackBar(
        context,
        'Relevant conversation facts were connected.',
        success: true,
      );
    }
  }
}

class _ReminderProposalCard extends StatelessWidget {
  const _ReminderProposalCard({
    required this.proposal,
    required this.deciding,
    required this.onDecision,
  });

  final ReminderProposalModel proposal;
  final bool deciding;
  final ValueChanged<bool> onDecision;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 6, 0, 12),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.amber.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(AppRadius.medium),
          border: Border.all(color: AppColors.amber.withValues(alpha: 0.24)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    LucideIcons.calendarClock,
                    color: AppColors.amber,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      context.tr('reminderProposal'),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(proposal.title),
              const SizedBox(height: 4),
              Text(
                context.strings.formatDateTime(proposal.dueAt.toLocal()),
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: AppColors.mutedInk),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: deciding ? null : () => onDecision(false),
                    child: Text(context.tr('notNow')),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: deciding ? null : () => onDecision(true),
                    child: deciding
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(context.tr('accept')),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Kept temporarily for compatibility with older golden fixtures.
// ignore: unused_element
class _MessageBubble extends StatelessWidget {
  // ignore: unused_element_parameter
  const _MessageBubble({required this.message, this.onRetry});
  final ChatMessageModel message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final farmer = message.author == ChatAuthor.farmer;
    final system = message.author == ChatAuthor.system;
    return Align(
      alignment: farmer
          ? AlignmentDirectional.centerEnd
          : AlignmentDirectional.centerStart,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.78,
        ),
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
          decoration: BoxDecoration(
            color: system
                ? AppColors.amber.withValues(alpha: 0.1)
                : farmer
                ? AppColors.forest
                : Colors.transparent,
            borderRadius: BorderRadius.circular(AppRadius.medium),
            border: farmer || !system
                ? null
                : Border.all(color: AppColors.divider),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!farmer && !system)
                Row(
                  children: [
                    Container(
                      width: 26,
                      height: 26,
                      decoration: const BoxDecoration(
                        color: AppColors.leaf,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        LucideIcons.sprout,
                        size: 15,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 9),
                    Text(
                      'KrishiSathi',
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                  ],
                ),
              if (!farmer && !system) const SizedBox(height: 10),
              _MessageContent(message: message, farmer: farmer),
              const SizedBox(height: 5),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _deliveryLabel(context, message),
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: farmer ? Colors.white70 : AppColors.mutedInk,
                    ),
                  ),
                  if (onRetry != null) ...[
                    const SizedBox(width: 8),
                    TextButton.icon(
                      onPressed: onRetry,
                      icon: const Icon(LucideIcons.refreshCw, size: 14),
                      label: Text(context.tr('retry')),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _deliveryLabel(BuildContext context, ChatMessageModel value) =>
      switch (value.delivery) {
        ChatDelivery.queued => context.tr('chatQueued'),
        ChatDelivery.sending => context.tr('chatProcessing'),
        ChatDelivery.failed => context.tr('chatFailed'),
        ChatDelivery.sent => context.strings.formatTime(value.sentAt),
      };
}

class _MessageContent extends StatelessWidget {
  const _MessageContent({required this.message, required this.farmer});

  final ChatMessageModel message;
  final bool farmer;

  @override
  Widget build(BuildContext context) {
    final reply = message.structuredReply;
    if (reply == null || farmer) {
      return Text(
        message.text,
        style: Theme.of(context).textTheme.bodyMedium
            ?.copyWith(color: farmer ? Colors.white : null),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(reply.shortAnswer, style: Theme.of(context).textTheme.bodyLarge),
        if (reply.details case final details?) ...[
          const SizedBox(height: 10),
          Text(details),
        ],
        for (final section in reply.answerSections) ...[
          const SizedBox(height: 14),
          Text(section.title, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 4),
          Text(section.body),
        ],
        if (reply.explanationPoints.isNotEmpty)
          _ReplyList(
            title: context.tr('whyThisMatters'),
            values: reply.explanationPoints,
          ),
        if (reply.nextSteps.isNotEmpty)
          _ReplyList(
            title: context.tr('nextSteps'),
            values: reply.nextSteps,
            numbered: true,
          ),
        if (reply.retakeAdvice case final advice?)
          _ReplyList(
            title: context.tr('retakePhotos'),
            values: advice.instructions,
          ),
        if (reply.generalPrecautions.isNotEmpty)
          _ReplyList(
            title: context.tr('generalPrecautions'),
            values: reply.generalPrecautions,
          ),
        if (reply.followUpQuestions.isNotEmpty)
          _ReplyList(
            title: context.tr('followUpQuestions'),
            values: reply.followUpQuestions,
          ),
        if (reply.consultLocalExpert) ...[
          const SizedBox(height: 12),
          InlineNotice(
            title: context.tr('localExpertRecommended'),
            message: context.tr('localExpertBody'),
            icon: LucideIcons.shieldCheck,
            color: AppColors.amber,
          ),
        ],
      ],
    );
  }
}

class _ReplyList extends StatelessWidget {
  const _ReplyList({
    required this.title,
    required this.values,
    this.numbered = false,
  });

  final String title;
  final List<String> values;
  final bool numbered;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 5),
          for (var index = 0; index < values.length; index++)
            Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child: Text(
                '${numbered ? '${index + 1}.' : '•'} ${values[index]}',
              ),
            ),
        ],
      ),
    );
  }
}

// Kept temporarily for compatibility with older golden fixtures.
// ignore: unused_element
class _ThinkingBar extends StatelessWidget {
  // ignore: unused_element_parameter
  const _ThinkingBar({super.key, required this.queuedCount});

  final int queuedCount;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      label: context.tr('saathiThinking'),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
        color: AppColors.leaf.withValues(alpha: 0.06),
        child: Row(
          children: [
            const SizedBox.square(
              dimension: 15,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                queuedCount > 0
                    ? context.tr('saathiThinkingQueued', {'count': queuedCount})
                    : context.tr('saathiThinking'),
                style: Theme.of(context).textTheme.labelMedium,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ConversationContextPill extends StatelessWidget {
  const _ConversationContextPill({required this.chat, required this.onTap});

  final ChatThreadModel chat;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final background = dark
        ? AppColors.leaf.withValues(alpha: 0.14)
        : const Color(0xFFEAF1E5);
    final border = dark
        ? AppColors.leaf.withValues(alpha: 0.28)
        : AppColors.youngLeaf.withValues(alpha: 0.26);
    return Material(
      key: const ValueKey('conversation-context-pill'),
      color: background,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 520),
          padding: const EdgeInsetsDirectional.fromSTEB(10, 7, 12, 7),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(LucideIcons.brain, size: 15, color: AppColors.forest),
              const SizedBox(width: 7),
              Flexible(
                child: Text(
                  chat.scopeLabel == null
                      ? 'Conversation only'
                      : '${chat.scopeLabel} context',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: dark
                        ? Theme.of(context).colorScheme.onSurface
                        : AppColors.forest,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 5),
              const Icon(
                LucideIcons.chevronDown,
                size: 14,
                color: AppColors.leaf,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GeneralChatWelcome extends StatelessWidget {
  const _GeneralChatWelcome({required this.onPrompt});

  final ValueChanged<String> onPrompt;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final prompts = <(IconData, String)>[
      (LucideIcons.cloudSun, 'How should I plan farm work around the weather?'),
      (LucideIcons.sprout, 'Help me think through a crop problem'),
      (LucideIcons.calendarClock, 'What should I remember this week?'),
    ];
    return Padding(
      key: const ValueKey('general-chat-welcome'),
      padding: const EdgeInsets.fromLTRB(2, 28, 2, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: dark
                  ? AppColors.leaf.withValues(alpha: 0.18)
                  : const Color(0xFFE7EFE1),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(
              LucideIcons.sprout,
              color: AppColors.forest,
              size: 24,
            ),
          ),
          const SizedBox(height: 18),
          Text(
            'What can I help with today?',
            style: Theme.of(context).textTheme.headlineMedium
                ?.copyWith(letterSpacing: -0.6, height: 1.12),
          ),
          const SizedBox(height: 8),
          Text(
            'Ask naturally about crops, field work, weather planning, or a farm decision. You can connect this conversation to a farm or plot later.',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 26),
          for (final prompt in prompts)
            Padding(
              padding: const EdgeInsets.only(bottom: 9),
              child: Material(
                color: dark
                    ? Theme.of(context).colorScheme.surfaceContainerHigh
                    : Colors.white.withValues(alpha: 0.72),
                borderRadius: BorderRadius.circular(18),
                child: InkWell(
                  borderRadius: BorderRadius.circular(18),
                  onTap: () => onPrompt(prompt.$2),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 13, 12, 13),
                    child: Row(
                      children: [
                        Icon(prompt.$1, size: 19, color: AppColors.leaf),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            prompt.$2,
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Icon(
                          LucideIcons.arrowUpRight,
                          size: 17,
                          color: AppColors.mutedInk,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          const SizedBox(height: 4),
          TextButton.icon(
            onPressed: () => onPrompt(''),
            icon: const Icon(LucideIcons.messageCircle, size: 17),
            label: const Text('Or write your own question below'),
          ),
        ],
      ),
    );
  }
}

class _LinkedScanCard extends StatelessWidget {
  const _LinkedScanCard({required this.diagnosis, required this.onTap});

  final DiagnosisCaseModel diagnosis;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final prediction = diagnosis.predictions.firstOrNull;
    return Material(
      color: Theme.of(context).brightness == Brightness.dark
          ? AppColors.darkSurface
          : const Color(0xFFEAF1E5),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        key: const ValueKey('linked-scan-card'),
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: AppColors.leaf.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  LucideIcons.scanLine,
                  color: AppColors.forest,
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${diagnosis.cropName} · ${prediction?.name ?? 'Possible issue'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                    const SizedBox(height: 3),
                    Wrap(
                      spacing: 6,
                      runSpacing: 3,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          'Linked leaf check',
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(color: AppColors.mutedInk),
                        ),
                        Container(
                          width: 3,
                          height: 3,
                          decoration: const BoxDecoration(
                            color: AppColors.mutedInk,
                            shape: BoxShape.circle,
                          ),
                        ),
                        Text(
                          '${prediction?.confidenceLabel ?? diagnosis.confidenceLabel} confidence',
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(color: AppColors.leaf),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(LucideIcons.chevronRight, size: 19),
            ],
          ),
        ),
      ),
    );
  }
}

class _MessageEntry extends StatelessWidget {
  const _MessageEntry({
    required this.message,
    required this.showAssistantLabel,
    required this.onFollowUp,
    required this.onCopy,
    required this.onSpeak,
    required this.speaking,
    required this.onFeedback,
    this.feedback,
    this.onRetry,
  });

  final ChatMessageModel message;
  final bool showAssistantLabel;
  final ValueChanged<String> onFollowUp;
  final VoidCallback onCopy;
  final VoidCallback onSpeak;
  final bool speaking;
  final bool? feedback;
  final ValueChanged<bool> onFeedback;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final farmer = message.author == ChatAuthor.farmer;
    final system = message.author == ChatAuthor.system;
    if (!farmer && !system) {
      return _AssistantResponse(
        message: message,
        showLabel: showAssistantLabel,
        onFollowUp: onFollowUp,
        onCopy: onCopy,
        onSpeak: onSpeak,
        speaking: speaking,
        feedback: feedback,
        onFeedback: onFeedback,
      );
    }
    if (system) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: AppColors.amber.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Text(message.text),
          ),
        ),
      );
    }
    return Align(
      alignment: AlignmentDirectional.centerEnd,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: math.min(440, MediaQuery.sizeOf(context).width * 0.78),
        ),
        child: Container(
          key: ValueKey('farmer-message-${message.id}'),
          margin: const EdgeInsets.only(bottom: 14),
          padding: const EdgeInsets.fromLTRB(14, 10, 12, 7),
          decoration: const BoxDecoration(
            color: AppColors.forest,
            borderRadius: BorderRadiusDirectional.only(
              topStart: Radius.circular(20),
              topEnd: Radius.circular(6),
              bottomStart: Radius.circular(20),
              bottomEnd: Radius.circular(20),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                message.text,
                style: Theme.of(context).textTheme.bodyMedium
                    ?.copyWith(color: Colors.white),
              ),
              const SizedBox(height: 5),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (message.delivery != ChatDelivery.sent)
                    Padding(
                      padding: const EdgeInsetsDirectional.only(end: 5),
                      child: Icon(
                        message.delivery == ChatDelivery.failed
                            ? LucideIcons.circleAlert
                            : LucideIcons.clock3,
                        size: 12,
                        color: message.delivery == ChatDelivery.failed
                            ? const Color(0xFFFFD0C8)
                            : Colors.white60,
                      ),
                    ),
                  Text(
                    switch (message.delivery) {
                      ChatDelivery.queued => context.tr('chatQueued'),
                      ChatDelivery.sending => context.tr('chatProcessing'),
                      ChatDelivery.failed => context.tr('chatFailed'),
                      ChatDelivery.sent => context.strings.formatTime(
                        message.sentAt,
                      ),
                    },
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: message.delivery == ChatDelivery.failed
                          ? const Color(0xFFFFD0C8)
                          : Colors.white60,
                    ),
                  ),
                  if (onRetry != null) ...[
                    const SizedBox(width: 5),
                    TextButton(
                      onPressed: onRetry,
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.white,
                        minimumSize: const Size(44, 30),
                        padding: const EdgeInsets.symmetric(horizontal: 7),
                      ),
                      child: Text(context.tr('retry')),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AssistantResponse extends StatelessWidget {
  const _AssistantResponse({
    required this.message,
    required this.showLabel,
    required this.onFollowUp,
    required this.onCopy,
    required this.onSpeak,
    required this.speaking,
    required this.onFeedback,
    this.feedback,
  });

  final ChatMessageModel message;
  final bool showLabel;
  final ValueChanged<String> onFollowUp;
  final VoidCallback onCopy;
  final VoidCallback onSpeak;
  final bool speaking;
  final bool? feedback;
  final ValueChanged<bool> onFeedback;

  @override
  Widget build(BuildContext context) {
    final reply = message.structuredReply;
    return Padding(
      key: ValueKey('saathi-response-${message.id}'),
      padding: const EdgeInsets.only(bottom: 26),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (showLabel) ...[
            Row(
              children: [
                const Icon(LucideIcons.sprout, size: 17, color: AppColors.leaf),
                const SizedBox(width: 7),
                Text(
                  'Saathi',
                  style: Theme.of(context).textTheme.labelLarge
                      ?.copyWith(color: AppColors.forest),
                ),
              ],
            ),
            const SizedBox(height: 10),
          ],
          if (reply == null)
            AssistantRichText(message.text, prominent: true)
          else ...[
            AssistantRichText(reply.shortAnswer, prominent: true),
            if (reply.nextSteps.isNotEmpty) ...[
              const SizedBox(height: 20),
              Text(
                'What to do now',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 10),
              for (var index = 0; index < reply.nextSteps.length; index++)
                _NumberedStep(index: index, text: reply.nextSteps[index]),
            ],
            for (final section in reply.answerSections) ...[
              const SizedBox(height: 18),
              Text(
                section.title,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 6),
              AssistantRichText(section.body),
            ],
            if (reply.retakeAdvice case final advice?) ...[
              const SizedBox(height: 14),
              _CautionSection(
                title: context.tr('retakePhotos'),
                values: advice.instructions,
              ),
            ],
            if (reply.details != null ||
                reply.explanationPoints.isNotEmpty) ...[
              const SizedBox(height: 12),
              _CollapsibleSection(
                title: context.tr('whyThisMatters'),
                icon: LucideIcons.circleHelp,
                text: reply.details,
                values: reply.explanationPoints,
              ),
            ],
            if (reply.generalPrecautions.isNotEmpty) ...[
              const SizedBox(height: 8),
              _CollapsibleSection(
                title: context.tr('generalPrecautions'),
                icon: LucideIcons.shieldCheck,
                values: reply.generalPrecautions,
              ),
            ],
            if (reply.consultLocalExpert) ...[
              const SizedBox(height: 12),
              _CautionSection(
                title: context.tr('localExpertRecommended'),
                values: [context.tr('localExpertBody')],
              ),
            ],
            if (reply.followUpQuestions.isNotEmpty) ...[
              const SizedBox(height: 18),
              Text(
                context.tr('followUpQuestions'),
                style: Theme.of(context).textTheme.labelLarge,
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final question in reply.followUpQuestions)
                    ActionChip(
                      avatar: const Icon(LucideIcons.cornerDownRight, size: 14),
                      label: Text(question),
                      onPressed: () => onFollowUp(question),
                    ),
                ],
              ),
            ],
          ],
          const SizedBox(height: 12),
          _AssistantActions(
            onCopy: onCopy,
            onSpeak: onSpeak,
            speaking: speaking,
            feedback: feedback,
            onFeedback: onFeedback,
          ),
        ],
      ),
    );
  }
}

String _chatScopeCaption(ChatThreadModel chat) {
  final scope = switch (chat.contextScope) {
    'scan' => 'Scan context',
    'plot' => 'Plot context',
    'farm' => 'Farm context',
    _ => 'Conversation context',
  };
  return [if (chat.scopeLabel != null) chat.scopeLabel!, scope].join(' · ');
}

class _NumberedStep extends StatelessWidget {
  const _NumberedStep({required this.index, required this.text});

  final int index;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 27,
            height: 27,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.youngLeaf.withValues(alpha: 0.13),
              shape: BoxShape.circle,
            ),
            child: Text(
              '${index + 1}',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: AppColors.forest,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 3),
              child: AssistantRichText(text),
            ),
          ),
        ],
      ),
    );
  }
}

class _CollapsibleSection extends StatelessWidget {
  const _CollapsibleSection({
    required this.title,
    required this.icon,
    this.text,
    this.values = const [],
  });

  final String title;
  final IconData icon;
  final String? text;
  final List<String> values;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.youngLeaf.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(14),
      ),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 13),
        childrenPadding: const EdgeInsets.fromLTRB(15, 0, 15, 14),
        shape: const Border(),
        collapsedShape: const Border(),
        leading: Icon(icon, size: 18, color: AppColors.forest),
        title: Text(title, style: Theme.of(context).textTheme.labelLarge),
        children: [
          if (text case final body?)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: AssistantRichText(body),
            ),
          for (final value in values)
            Padding(
              padding: const EdgeInsets.only(top: 7),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 7),
                    child: CircleAvatar(
                      radius: 2,
                      backgroundColor: AppColors.leaf,
                    ),
                  ),
                  const SizedBox(width: 9),
                  Expanded(child: AssistantRichText(value)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _CautionSection extends StatelessWidget {
  const _CautionSection({required this.title, required this.values});

  final String title;
  final List<String> values;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.amber.withValues(alpha: 0.11),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.amber.withValues(alpha: 0.25)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(13),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  LucideIcons.triangleAlert,
                  size: 17,
                  color: AppColors.soil,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                ),
              ],
            ),
            for (final value in values)
              Padding(
                padding: const EdgeInsetsDirectional.only(start: 25, top: 6),
                child: AssistantRichText(value),
              ),
          ],
        ),
      ),
    );
  }
}

class _AssistantActions extends StatelessWidget {
  const _AssistantActions({
    required this.onCopy,
    required this.onSpeak,
    required this.speaking,
    required this.onFeedback,
    this.feedback,
  });

  final VoidCallback onCopy;
  final VoidCallback onSpeak;
  final bool speaking;
  final bool? feedback;
  final ValueChanged<bool> onFeedback;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 2,
      runSpacing: 2,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        IconButton(
          visualDensity: VisualDensity.compact,
          tooltip: 'Copy response',
          onPressed: onCopy,
          icon: const Icon(LucideIcons.copy, size: 17),
        ),
        IconButton(
          visualDensity: VisualDensity.compact,
          tooltip: feedback == true ? 'Marked helpful' : 'Helpful',
          onPressed: () => onFeedback(true),
          color: feedback == true ? AppColors.leaf : null,
          icon: const Icon(LucideIcons.thumbsUp, size: 17),
        ),
        IconButton(
          visualDensity: VisualDensity.compact,
          tooltip: feedback == false ? 'Marked not helpful' : 'Not helpful',
          onPressed: () => onFeedback(false),
          color: feedback == false ? AppColors.danger : null,
          icon: const Icon(LucideIcons.thumbsDown, size: 17),
        ),
        TextButton.icon(
          onPressed: onSpeak,
          icon: Icon(
            speaking ? LucideIcons.square : LucideIcons.volume2,
            size: 16,
          ),
          label: Text(speaking ? 'Stop' : 'Read aloud'),
        ),
      ],
    );
  }
}

class _ThinkingIndicator extends StatefulWidget {
  const _ThinkingIndicator({required this.queuedCount});

  final int queuedCount;

  @override
  State<_ThinkingIndicator> createState() => _ThinkingIndicatorState();
}

class _ThinkingIndicatorState extends State<_ThinkingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller
        ..stop()
        ..value = 0.5;
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      label: context.tr('saathiThinking'),
      child: Padding(
        key: const ValueKey('saathi-thinking-indicator'),
        padding: const EdgeInsets.only(bottom: 20),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: AppColors.youngLeaf.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                LucideIcons.sprout,
                size: 16,
                color: AppColors.leaf,
              ),
            ),
            const SizedBox(width: 9),
            AnimatedBuilder(
              animation: _controller,
              builder: (context, _) => Row(
                children: List.generate(3, (index) {
                  final phase = _controller.value * math.pi * 2 - index * 0.8;
                  final opacity = 0.25 + ((math.sin(phase) + 1) / 2) * 0.75;
                  return Container(
                    width: 6,
                    height: 6,
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    decoration: BoxDecoration(
                      color: AppColors.leaf.withValues(alpha: opacity),
                      shape: BoxShape.circle,
                    ),
                  );
                }),
              ),
            ),
            if (widget.queuedCount > 0) ...[
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  context.tr('saathiThinkingQueued', {
                    'count': widget.queuedCount,
                  }),
                  style: Theme.of(context).textTheme.labelSmall
                      ?.copyWith(color: AppColors.mutedInk),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PromptTile extends StatelessWidget {
  const _PromptTile({required this.prompt, required this.onTap});
  final String prompt;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(AppRadius.medium),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.medium),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.medium),
            border: Border.all(color: AppColors.divider),
          ),
          child: Row(
            children: [
              const Icon(
                LucideIcons.sparkles,
                size: 16,
                color: AppColors.amber,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  prompt,
                  style: Theme.of(context).textTheme.bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w500),
                ),
              ),
              const Icon(
                LucideIcons.arrowRight,
                size: 16,
                color: AppColors.mutedInk,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
