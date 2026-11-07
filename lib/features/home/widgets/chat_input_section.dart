import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/models/chat_input_data.dart';
import '../../../core/models/assistant.dart';
import '../../../core/models/conversation_mcp_settings.dart';
import '../../../core/services/api/reasoning/reasoning_level_options.dart';
import '../../../core/services/api/reasoning/reasoning_dialects.dart';
import '../../../core/services/api/reasoning/reasoning_selection.dart';
import '../../../core/services/model_spec/model_spec_resolver.dart';
import '../../../core/models/workspace_binding.dart';
import '../../../core/models/skills_binding.dart';
import '../../../core/providers/asr_provider.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../core/providers/assistant_provider.dart';
import '../../../core/providers/mcp_provider.dart';
import '../../../core/providers/quick_phrase_provider.dart';
import '../../../core/providers/world_book_provider.dart';
import '../../../core/providers/instruction_injection_provider.dart';
import '../../../core/services/chat/chat_service.dart';
import '../../../core/services/skills/skills_service.dart';
import '../../../features/chat/utils/prompt_injection_selection.dart';
import '../../../features/workspace/widgets/environment/environment_status_chip.dart';
import '../../../features/workspace/workspace_navigation.dart';
import '../../../theme/design_tokens.dart';
import 'chat_input_bar.dart';
import 'grok_quick_chips.dart';
import 'live_call_bar.dart';
import 'model_icon.dart';

/// Callback for checking if a model supports tool calling.
typedef IsToolModelCallback = bool Function(String providerKey, String modelId);

/// Callback for checking if a model supports reasoning.
typedef IsReasoningModelCallback =
    bool Function(String providerKey, String modelId);

/// Callback for checking if reasoning is enabled.
typedef IsReasoningEnabledCallback = bool Function(ReasoningRequest request);

/// Widget that wraps ChatInputBar with all the necessary logic and callbacks.
class ChatInputSection extends StatefulWidget {
  const ChatInputSection({
    super.key,
    required this.inputBarKey,
    this.chatModelProviderKey,
    this.chatModelId,
    this.chatModelIsConversationOverride = false,
    required this.inputFocus,
    required this.inputController,
    required this.mediaController,
    required this.isTablet,
    required this.isLoading,
    this.hasMessages = false,
    this.latestAiResponse,
    required this.isToolModel,
    required this.isReasoningModel,
    required this.isReasoningEnabled,
    this.onMore,
    this.onSelectModel,
    this.onLongPressSelectModel,
    this.onOpenTools,
    this.onLongPressTools,
    this.onOpenWorkspace,
    this.onOpenSkills,
    this.onOpenSearch,
    this.onConfigureReasoning,
    this.onOpenContextUsage,
    this.onSend,
    this.onStop,
    this.hasQueuedInput = false,
    this.queuedPreviewText,
    this.queuedStatusLabel,
    this.queuedSubtitle,
    this.queuedPaused = false,
    this.onCancelQueuedInput,
    this.onSendNowQueuedInput,
    this.onExpandedChanged,
    this.onQuickPhrase,
    this.onLongPressQuickPhrase,
    this.onToggleOcr,
    this.onOpenMiniMap,
    this.onPickCamera,
    this.onPickPhotos,
    this.onUploadFiles,
    this.onOpenBrowser,
    this.onToggleLearningMode,
    this.onOpenWorldBook,
    this.onLongPressLearning,
    this.onClearContext,
    this.onCompressContext,
    this.conversationId,
    this.sendButtonTooltip,
    this.backgroundImageActive = false,
  });

  final GlobalKey inputBarKey;
  final FocusNode inputFocus;
  final TextEditingController inputController;
  final ChatInputBarController mediaController;
  final bool isTablet;
  final bool isLoading;
  final bool hasMessages;
  final String? latestAiResponse;

  // Model capability checkers
  final IsToolModelCallback isToolModel;
  final IsReasoningModelCallback isReasoningModel;
  final IsReasoningEnabledCallback isReasoningEnabled;

  // Callbacks
  final VoidCallback? onMore;
  final VoidCallback? onSelectModel;
  final VoidCallback? onLongPressSelectModel;
  final VoidCallback? onOpenTools;
  final VoidCallback? onLongPressTools;
  final VoidCallback? onOpenWorkspace;
  final VoidCallback? onOpenSkills;
  final VoidCallback? onOpenSearch;
  final VoidCallback? onConfigureReasoning;
  final VoidCallback? onOpenContextUsage;
  final Future<ChatInputSubmissionResult> Function(ChatInputData)? onSend;
  final VoidCallback? onStop;
  final bool hasQueuedInput;
  final String? queuedPreviewText;
  final String? queuedStatusLabel;
  final String? queuedSubtitle;
  final bool queuedPaused;
  final VoidCallback? onCancelQueuedInput;
  final VoidCallback? onSendNowQueuedInput;
  final ValueChanged<bool>? onExpandedChanged;
  final VoidCallback? onQuickPhrase;
  final VoidCallback? onLongPressQuickPhrase;
  final VoidCallback? onToggleOcr;
  final VoidCallback? onOpenMiniMap;
  final VoidCallback? onPickCamera;
  final VoidCallback? onPickPhotos;
  final VoidCallback? onUploadFiles;
  final VoidCallback? onOpenBrowser;
  final VoidCallback? onToggleLearningMode;
  final VoidCallback? onOpenWorldBook;
  final VoidCallback? onLongPressLearning;
  final VoidCallback? onClearContext;
  final VoidCallback? onCompressContext;
  final String? conversationId;
  final String? chatModelProviderKey;
  final String? chatModelId;
  final bool chatModelIsConversationOverride;
  final String? sendButtonTooltip;
  final bool backgroundImageActive;

  @override
  State<ChatInputSection> createState() => _ChatInputSectionState();
}

class _ChatInputSectionState extends State<ChatInputSection> {
  bool _isLiveCall = false;

  @override
  void initState() {
    super.initState();
    widget.mediaController.onStartLiveCall = () {
      if (mounted) setState(() => _isLiveCall = true);
    };
  }

  @override
  void didUpdateWidget(covariant ChatInputSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.mediaController != widget.mediaController) {
      widget.mediaController.onStartLiveCall = () {
        if (mounted) setState(() => _isLiveCall = true);
      };
    }
  }

  @override
  void dispose() {
    widget.mediaController.onStartLiveCall = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLiveCall) {
      return LiveCallBar(
        latestAiResponse: widget.latestAiResponse,
        isLoading: widget.isLoading,
        onSend: (text, {imagePaths}) async {
          await widget.onSend?.call(
            ChatInputData(text: text, imagePaths: imagePaths ?? const []),
          );
        },
        onHangup: () {
          if (mounted) setState(() => _isLiveCall = false);
        },
      );
    }

    final settings = context.watch<SettingsProvider>();
    final asr = context.watch<AsrProvider>();
    final ap = context.watch<AssistantProvider>();
    final a = ap.currentAssistant;

    final pk = widget.chatModelProviderKey;
    final mid = widget.chatModelId;
    final supportsModelTools =
        pk != null && mid != null && widget.isToolModel(pk, mid);
    final selectedReasoning = _selectedReasoning(settings, a, pk, mid);
    final reasoningSpec = (pk != null && mid != null)
        ? ModelSpecResolver.instance.spec(settings.getProviderConfig(pk), mid)
        : null;
    final effectiveReasoning = reasoningSpec == null
        ? selectedReasoning
        : ReasoningRequest(
            resolveReasoning(reasoningSpec, selectedReasoning).effective,
            budgetTokens: selectedReasoning.budgetTokens,
          );

    if (!widget.chatModelIsConversationOverride &&
        a?.allowConversationMcp != true) {
      _enforceModelCapabilities(context, settings, ap, a, pk, mid);
    }

    final isDesktop = _isDesktopPlatform(context);
    final hasWorldBooks =
        widget.isTablet && context.watch<WorldBookProvider>().books.isNotEmpty;
    final showWorkspaceButton = isDesktop && widget.onOpenWorkspace != null;
    final showEnvChip = !isDesktop && (Platform.isAndroid || Platform.isIOS);
    var workspaceBound = false;
    if (showWorkspaceButton || showEnvChip) {
      workspaceBound = _isWorkspaceBound(context);
    }

    final bar = ChatInputBar(
      key: widget.inputBarKey,
      chatModelProviderKey: pk,
      chatModelId: mid,
      onMore: widget.onMore,
      onSelectModel: widget.onSelectModel,
      onLongPressSelectModel: widget.onLongPressSelectModel,
      conversationId: widget.conversationId,
      onOpenTools: widget.onOpenTools,
      onLongPressTools: widget.onLongPressTools,
      onOpenWorkspace: widget.onOpenWorkspace,
      showWorkspaceButton: showWorkspaceButton,
      workspaceActive: workspaceBound,
      onOpenSkills: isDesktop ? widget.onOpenSkills : null,
      skillsActive:
          isDesktop &&
          widget.onOpenSkills != null &&
          _isSkillsActive(context, a),
      onStop: widget.onStop,
      modelIcon: (pk != null && mid != null)
          ? CurrentModelIcon(
              providerKey: pk,
              modelId: mid,
              size: 40,
              withBackground: true,
              backgroundColor: Colors.transparent,
            )
          : null,
      focusNode: widget.inputFocus,
      controller: widget.inputController,
      mediaController: widget.mediaController,
      asrProvider: asr,
      onConfigureReasoning: widget.onConfigureReasoning,
      onOpenContextUsage: widget.onOpenContextUsage,
      reasoningActive: widget.isReasoningEnabled(effectiveReasoning),
      reasoning: effectiveReasoning,
      reasoningCustomBudget: reasoningSpec != null
          ? isCustomBudgetSelection(reasoningSpec, selectedReasoning)
          : false,
      supportsReasoning: (pk != null && mid != null)
          ? widget.isReasoningModel(pk, mid)
          : false,
      onOpenSearch: widget.onOpenSearch,
      onSend: widget.onSend,
      loading: widget.isLoading,
      sendButtonTooltip: widget.sendButtonTooltip,
      hasQueuedInput: widget.hasQueuedInput,
      queuedPreviewText: widget.queuedPreviewText,
      queuedStatusLabel: widget.queuedStatusLabel,
      queuedSubtitle: widget.queuedSubtitle,
      queuedPaused: widget.queuedPaused,
      onCancelQueuedInput: widget.onCancelQueuedInput,
      onSendNowQueuedInput: widget.onSendNowQueuedInput,
      onExpandedChanged: widget.onExpandedChanged,
      showToolsButton: supportsModelTools,
      toolsActive:
          supportsModelTools && _isToolsActive(context, a, workspaceBound),
      showQuickPhraseButton: _hasQuickPhrases(context, a),
      onQuickPhrase: widget.onQuickPhrase,
      onLongPressQuickPhrase: widget.onLongPressQuickPhrase,
      showOcrButton:
          (settings.ocrModelProvider != null && settings.ocrModelId != null),
      ocrActive: settings.ocrEnabled,
      onToggleOcr: widget.onToggleOcr,
      showMiniMapButton: true,
      onOpenMiniMap: widget.onOpenMiniMap,
      onPickCamera: isDesktop ? null : widget.onPickCamera,
      onPickPhotos: isDesktop ? null : widget.onPickPhotos,
      onUploadFiles: widget.onUploadFiles,
      onOpenBrowser: widget.onOpenBrowser,
      onToggleLearningMode: widget.onToggleLearningMode,
      onOpenWorldBook: hasWorldBooks ? widget.onOpenWorldBook : null,
      onLongPressLearning: widget.onLongPressLearning,
      learningModeActive: _isPromptSelectionActive(
        context,
        a,
        PromptSelectionKind.instruction,
      ),
      worldBookActive: _isPromptSelectionActive(
        context,
        a,
        PromptSelectionKind.worldBook,
      ),
      showMoreButton: true,
      onClearContext: widget.onClearContext,
      onCompressContext: widget.onCompressContext,
      backgroundImageActive: widget.backgroundImageActive,
      inputBackgroundOpacityLight: settings.chatInputBackgroundOpacityLight,
      inputBackgroundOpacityDark: settings.chatInputBackgroundOpacityDark,
    );

    // Quick chips are hidden after the user sends their first message!
    final quickChips = (!widget.isTablet && !widget.hasMessages)
        ? GrokQuickChips(
            onSelectChip: (id) {
              switch (id) {
                case 'videos':
                  widget.inputController.text = 'Generate a video showing ';
                  widget.inputFocus.requestFocus();
                  break;
                case 'edit_image':
                  widget.onPickPhotos?.call();
                  break;
                case 'voice_mode':
                  widget.inputFocus.unfocus();
                  setState(() => _isLiveCall = true);
                  break;
                case 'inspect_site':
                  widget.inputController.text = 'Inspect site: ';
                  widget.inputFocus.requestFocus();
                  break;
                case 'sandbox_vps':
                  widget.inputController.text = 'Run command in sandbox VPS: ';
                  widget.inputFocus.requestFocus();
                  break;
              }
            },
          )
        : null;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showEnvChip && workspaceBound)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.sm,
              AppSpacing.xxs,
              AppSpacing.sm,
              0,
            ),
            child: EnvironmentStatusChip(
              onTap: () => WorkspaceNavigation.openEnvironmentPage(context),
            ),
          ),
        if (quickChips != null) quickChips,
        Flexible(child: bar),
      ],
    );
  }

  bool _isPromptSelectionActive(
    BuildContext context,
    Assistant? assistant,
    PromptSelectionKind kind,
  ) {
    final scoped = assistant?.allowConversationPromptInjection == true;
    if (scoped && widget.conversationId == null) return false;
    final ids = promptSelectionIds(
      context,
      kind: kind,
      assistantId: assistant?.id,
      conversationId: scoped ? widget.conversationId : null,
    ).toSet();
    return kind == PromptSelectionKind.worldBook
        ? context.watch<WorldBookProvider>().books.any(
            (book) => book.enabled && ids.contains(book.id),
          )
        : context.watch<InstructionInjectionProvider>().items.any(
            (item) => ids.contains(item.id),
          );
  }

  bool _isSkillsActive(BuildContext context, Assistant? assistant) {
    final skillIds = context.select<ChatService?, List<String>?>((chat) {
      final extras = chat?.getConversation(widget.conversationId ?? '')?.extras;
      return SkillsBinding.fromExtras(extras ?? const {}).skillIds;
    });
    return context.select<SkillsService?, bool>(
      (skills) =>
          skills
              ?.resolveForAssistant(assistant, conversationOverride: skillIds)
              .isNotEmpty ??
          false,
    );
  }

  bool _isWorkspaceBound(BuildContext context) {
    try {
      return context.select<ChatService, bool>((chat) {
        final id = widget.conversationId;
        if (id == null) return false;
        final conversation = chat.getConversation(id);
        if (conversation == null) return false;
        return WorkspaceBinding.fromExtras(conversation.extras).isBound;
      });
    } catch (_) {
      return false;
    }
  }

  bool _isDesktopPlatform(BuildContext context) {
    final platform = Theme.of(context).platform;
    return platform == TargetPlatform.macOS ||
        platform == TargetPlatform.windows ||
        platform == TargetPlatform.linux;
  }

  void _enforceModelCapabilities(
    BuildContext context,
    SettingsProvider settings,
    AssistantProvider ap,
    Assistant? a,
    String? pk,
    String? mid,
  ) {
    if (pk == null || mid == null) return;

    final supportsTools = widget.isToolModel(pk, mid);
    if (!supportsTools && (a?.mcpServerIds.isNotEmpty ?? false)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final aa = ap.currentAssistant;
        if (aa != null && aa.mcpServerIds.isNotEmpty) {
          ap.updateAssistant(aa.copyWith(mcpServerIds: const <String>[]));
        }
      });
    }
  }

  ReasoningRequest _selectedReasoning(
    SettingsProvider settings,
    Assistant? assistant,
    String? providerKey,
    String? modelId,
  ) {
    if (providerKey == null || modelId == null) {
      return assistant?.reasoning ?? ReasoningRequest.auto;
    }
    return selectReasoningRequest(
      settings: settings,
      config: settings.getProviderConfig(providerKey),
      modelId: modelId,
      assistant: assistant,
    );
  }

  bool _isToolsActive(BuildContext context, Assistant? a, bool workspaceBound) {
    if (workspaceBound) return true;
    if ((a?.localToolIds ?? const <String>[]).isNotEmpty) return true;
    final connected = context.watch<McpProvider>().connectedServers;
    final selected =
        a?.allowConversationMcp == true && widget.conversationId != null
        ? context.select<ChatService, List<String>>(
            (chat) => ConversationMcpSettings.effectiveServerIds(
              a,
              chat.getConversation(widget.conversationId!),
            ),
          )
        : a?.mcpServerIds ?? const <String>[];
    if (selected.isEmpty || connected.isEmpty) return false;
    return connected.any((s) => selected.contains(s.id));
  }

  bool _hasQuickPhrases(BuildContext context, Assistant? a) {
    final quickPhraseProvider = context.watch<QuickPhraseProvider>();
    final globalCount = quickPhraseProvider.globalPhrases.length;
    final assistantCount = a != null
        ? quickPhraseProvider.getForAssistant(a.id).length
        : 0;
    return (globalCount + assistantCount) > 0;
  }
}
