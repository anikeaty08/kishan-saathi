import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/localization/app_strings.dart';
import '../../../core/theme/app_theme.dart';
import 'voice_composer_controller.dart';

class ChatComposer extends StatelessWidget {
  const ChatComposer({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.onAttach,
    required this.voiceState,
    required this.voiceElapsed,
    required this.onVoice,
    required this.onLiveVoice,
    required this.onCancelVoice,
    required this.onSend,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onAttach;
  final VoiceComposerState voiceState;
  final Duration voiceElapsed;
  final VoidCallback onVoice;
  final VoidCallback onLiveVoice;
  final VoidCallback onCancelVoice;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(12, 6, 12, 10),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Material(
            key: const ValueKey('chat-composer-surface'),
            elevation: 4,
            shadowColor: Colors.black.withValues(alpha: 0.12),
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(22),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(4, 3, 3, 3),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedSwitcher(
                    duration: MediaQuery.disableAnimationsOf(context)
                        ? Duration.zero
                        : const Duration(milliseconds: 180),
                    child: voiceState == VoiceComposerState.idle
                        ? const SizedBox.shrink()
                        : VoiceComposerStatus(
                            key: ValueKey(voiceState),
                            state: voiceState,
                            elapsed: voiceElapsed,
                            onCancel: onCancelVoice,
                          ),
                  ),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      IconButton(
                        tooltip: context.tr('addLeafPhotos'),
                        onPressed: voiceState == VoiceComposerState.idle
                            ? onAttach
                            : null,
                        icon: const Icon(LucideIcons.plus),
                      ),
                      Expanded(
                        child: TextField(
                          key: const ValueKey('chat-composer'),
                          controller: controller,
                          focusNode: focusNode,
                          minLines: 1,
                          maxLines: 5,
                          textCapitalization: TextCapitalization.sentences,
                          decoration: InputDecoration(
                            hintText: context.tr('askHint'),
                            filled: false,
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 11,
                            ),
                          ),
                          enabled: voiceState == VoiceComposerState.idle,
                          onSubmitted: (_) => onSend(),
                        ),
                      ),
                      if (voiceState != VoiceComposerState.idle &&
                          voiceState != VoiceComposerState.recording)
                        const Padding(
                          padding: EdgeInsets.all(12),
                          child: SizedBox.square(
                            dimension: 20,
                            child: CircularProgressIndicator(strokeWidth: 2.2),
                          ),
                        )
                      else ...[
                        if (voiceState == VoiceComposerState.idle)
                          IconButton(
                            key: const ValueKey('chat-live-voice-button'),
                            tooltip: context.tr('voiceConversationWithSaathi'),
                            onPressed: onLiveVoice,
                            color: AppColors.forest,
                            icon: const Icon(LucideIcons.audioLines),
                          ),
                        IconButton(
                          key: const ValueKey('chat-voice-button'),
                          tooltip: voiceState == VoiceComposerState.recording
                              ? context.tr('voiceStop')
                              : context.tr('voiceStart'),
                          onPressed: onVoice,
                          color: voiceState == VoiceComposerState.recording
                              ? AppColors.amber
                              : AppColors.forest,
                          icon: Icon(
                            voiceState == VoiceComposerState.recording
                                ? LucideIcons.square
                                : LucideIcons.mic,
                          ),
                        ),
                      ],
                      IconButton.filled(
                        tooltip: context.tr('send'),
                        onPressed: voiceState == VoiceComposerState.idle
                            ? onSend
                            : null,
                        icon: const Icon(LucideIcons.arrowUp, size: 20),
                      ),
                    ],
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

class VoiceComposerStatus extends StatelessWidget {
  const VoiceComposerStatus({
    super.key,
    required this.state,
    required this.elapsed,
    required this.onCancel,
  });

  final VoiceComposerState state;
  final Duration elapsed;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final recording = state == VoiceComposerState.recording;
    final minutes = elapsed.inMinutes.toString().padLeft(2, '0');
    final seconds = (elapsed.inSeconds % 60).toString().padLeft(2, '0');
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 4, 0),
      child: Row(
        children: [
          Semantics(
            liveRegion: true,
            label: recording
                ? context.tr('voiceRecordingActive')
                : context.tr('voiceTranscribing'),
            child: const SizedBox.shrink(),
          ),
          const DecoratedBox(
            decoration: BoxDecoration(
              color: AppColors.amber,
              shape: BoxShape.circle,
            ),
            child: SizedBox.square(dimension: 8),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: ExcludeSemantics(
              child: Text(
                recording
                    ? context.tr('voiceRecording', {
                        'time': '$minutes:$seconds',
                      })
                    : context.tr('voiceTranscribing'),
                style: Theme.of(context).textTheme.labelLarge,
              ),
            ),
          ),
          if (recording || state == VoiceComposerState.starting)
            TextButton(onPressed: onCancel, child: Text(context.tr('cancel'))),
        ],
      ),
    );
  }
}
