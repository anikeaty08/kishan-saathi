import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../../core/localization/app_strings.dart';
import '../../../core/models/app_models.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/ui/app_ui.dart';
import '../../shared/presentation/app_controller.dart';

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
          return _scope == 'all' || chat.scope == _scope;
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
          child: ListView(
            key: const PageStorageKey('saathi-list'),
            padding: const EdgeInsets.only(top: 8, bottom: 110),
            children: [
              ImageBand(
                asset: 'assets/images/crop_maize.jpg',
                height: 210,
                alignment: const Alignment(0, -0.2),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Spacer(),
                    Row(
                      children: [
                        Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(
                              AppRadius.medium,
                            ),
                          ),
                          child: const Icon(
                            LucideIcons.messageCircle,
                            color: AppColors.forest,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            context.tr('saathiTitle'),
                            style: Theme.of(context).textTheme.headlineMedium
                                ?.copyWith(color: Colors.white),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      context.tr('saathiBody'),
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Colors.white.withValues(alpha: 0.9),
                      ),
                    ),
                  ],
                ),
              ),
              if (!controller.canUseLiveServices) ...[
                const SizedBox(height: 16),
                InlineNotice(
                  title: context.tr('chatOffline'),
                  message: 'Existing sample conversations are available. New messages are not sent in preview mode.',
                  icon: LucideIcons.cloudOff,
                  color: AppColors.amber,
                ),
              ],
              const SizedBox(height: 26),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final filter in const <(String, String, IconData)>[
                      ('all', 'All', LucideIcons.layoutList),
                      ('general', 'General', LucideIcons.messageCircle),
                      ('farm', 'Farm', LucideIcons.warehouse),
                      ('plot', 'Plot', LucideIcons.sprout),
                      ('scan', 'Leaf checks', LucideIcons.scanLine),
                    ]) ...[
                      FilterChip(
                        avatar: Icon(filter.$3, size: 15),
                        label: Text(filter.$2),
                        selected: _scope == filter.$1,
                        onSelected: (_) => setState(() => _scope = filter.$1),
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
                AppStateView(
                  kind: AppStateKind.empty,
                  title: _showArchived
                      ? 'No archived conversations'
                      : 'No matching conversations',
                  message: _showArchived
                      ? 'Chats you archive will remain available here.'
                      : 'Choose another filter or start a general, farm, plot or leaf-check chat.',
                  actionLabel: _showArchived ? null : context.tr('newChat'),
                  onAction: _showArchived
                      ? null
                      : () => context.push('/saathi/new'),
                )
              else
                ...visibleChats.map((chat) => _ChatRow(chat: chat)),
              if (!_showArchived) ...[
                const SizedBox(height: 26),
                Text(
                  'Good questions to ask',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children:
                      [
                            'What should I do before rain?',
                            'Why are lower leaves yellow?',
                            'Plan this week’s field work',
                          ]
                          .map(
                            (prompt) => ActionChip(
                              avatar: const Icon(
                                LucideIcons.sparkles,
                                size: 16,
                              ),
                              label: Text(prompt),
                              onPressed: () => context.push(
                                '/saathi/new?prompt=${Uri.encodeComponent(prompt)}',
                              ),
                            ),
                          )
                          .toList(),
                ),
              ],
            ],
          ),
        ),
      ),
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
      child: Card(
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.medium),
          onTap: () => context.push('/saathi/chat/${chat.id}'),
          child: Padding(
            padding: const EdgeInsets.all(15),
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
                    switch (chat.scope) {
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
                              DateFormat.MMMd().format(latest.sentAt),
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(color: AppColors.mutedInk),
                            ),
                        ],
                      ),
                      const SizedBox(height: 3),
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
    try {
      final controller = context.read<AppController>();
      final chat = await controller.createChat(
        scope: _scope,
        contextId: _contextId,
      );
      await controller.sendMessage(chat.id, prompt);
      if (mounted) context.go('/saathi/chat/${chat.id}');
    } on ApiException catch (error) {
      if (mounted) showAppSnackBar(context, error.message);
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
              if (contextItems.isNotEmpty) ...[
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: _contextId,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Choose context',
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
              if (!controller.canUseLiveServices) ...[
                const SizedBox(height: 14),
                InlineNotice(
                  title: context.tr('chatOffline'),
                  message: 'Preview conversations stay on this device and are clearly marked as not sent.',
                  icon: LucideIcons.cloudOff,
                  color: AppColors.amber,
                ),
              ],
            ],
          ),
        ),
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
  final _scrollController = ScrollController();
  Timer? _draftDebounce;
  late final AppController _controller;

  @override
  void initState() {
    super.initState();
    _controller = context.read<AppController>();
    _message.text = _controller.chatDraft(widget.chatId);
    _message.addListener(_scheduleDraftSave);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        await context.read<AppController>().loadChat(widget.chatId);
      } on ApiException catch (error) {
        if (mounted) showAppSnackBar(context, error.message);
      }
    });
  }

  @override
  void dispose() {
    _draftDebounce?.cancel();
    unawaited(_controller.saveChatDraft(widget.chatId, _message.text));
    _message.removeListener(_scheduleDraftSave);
    _message.dispose();
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
        _message.text = text;
        showAppSnackBar(context, error.message);
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

  void _scheduleDraftSave() {
    _draftDebounce?.cancel();
    _draftDebounce = Timer(const Duration(milliseconds: 350), () {
      unawaited(_controller.saveChatDraft(widget.chatId, _message.text));
    });
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
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(chat.title, maxLines: 1, overflow: TextOverflow.ellipsis),
            if (chat.scopeLabel != null)
              Text(
                chat.scopeLabel!,
                style: Theme.of(context).textTheme.labelSmall
                    ?.copyWith(color: AppColors.mutedInk),
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
              child: AppContent(
                maxWidth: 760,
                child: ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  itemCount: chat.messages.length + 1,
                  itemBuilder: (context, index) {
                    if (index == 0) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 18),
                        child: InlineNotice(
                          title: '${chat.scope.toUpperCase()} context',
                          message: chat.scopeLabel == null
                              ? 'Saathi is using only this conversation.'
                              : 'Saathi can use records linked to ${chat.scopeLabel}.',
                          icon: LucideIcons.brain,
                          color: AppColors.leaf,
                        ),
                      );
                    }
                    return _MessageBubble(message: chat.messages[index - 1]);
                  },
                ),
              ),
            ),
            DecoratedBox(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                border: const Border(top: BorderSide(color: AppColors.divider)),
              ),
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _message,
                          minLines: 1,
                          maxLines: 5,
                          textCapitalization: TextCapitalization.sentences,
                          decoration: InputDecoration(
                            hintText: context.tr('askHint'),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 11,
                            ),
                          ),
                          onSubmitted: (_) => _send(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton.filled(
                        tooltip: context.tr('send'),
                        onPressed: context.watch<AppController>().busy
                            ? null
                            : _send,
                        icon: const Icon(LucideIcons.send, size: 19),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
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
      if (mounted) showAppSnackBar(context, error.message);
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

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message});
  final ChatMessageModel message;

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
                : Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(AppRadius.medium),
            border: farmer ? null : Border.all(color: AppColors.divider),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                message.text,
                style: Theme.of(context).textTheme.bodyMedium
                    ?.copyWith(color: farmer ? Colors.white : null),
              ),
              const SizedBox(height: 5),
              Text(
                message.failed
                    ? 'Not sent'
                    : DateFormat.jm().format(message.sentAt),
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: farmer ? Colors.white70 : AppColors.mutedInk,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
