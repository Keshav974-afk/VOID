import 'package:Kelivo/core/services/conversation_tool_permissions.dart';
import 'package:Kelivo/core/models/tool_permission_mode.dart';
import 'package:Kelivo/utils/mcp_structured_image.dart';
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';
import '../../../core/models/assistant.dart';
import '../../../core/models/model_spec.dart';
import '../../../core/models/reasoning_request.dart';
import '../../../core/providers/assistant_provider.dart';
import '../../../core/providers/environment_provider.dart';
import '../../../core/providers/mcp_provider.dart';
import '../../../core/providers/memory_provider.dart';
import '../../../core/providers/memory_provider_v2.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../core/providers/tts_provider.dart';
import '../../../core/services/api/chat_api_service.dart';
import '../../../core/services/api/builtin_tools.dart' as native_tools;
import '../../../core/services/api/json_schema_utils.dart';
import '../../../core/services/model_spec/model_spec_resolver.dart';
import '../../../core/services/chat/chat_service.dart';
import '../../../core/services/browser/browser_tools_service.dart';
import '../../../core/services/composio/composio_service.dart';
import '../../../core/services/mcp/mcp_tool_service.dart';
import '../../../core/services/memory/memory_pipeline.dart';
import '../../../core/services/memory/memory_tools.dart';
import '../../../core/services/search/search_tool_service.dart';
import '../../../core/services/search/web_fetch_service.dart';
import '../../../core/services/search/web_fetch_tool_service.dart';
import '../../../core/services/tools/tool_schema_overrides.dart';
import '../../../core/services/skills/skills_service.dart';
import '../../../core/services/workspace/tool_run_registry.dart';
import '../../../core/services/workspace/workspace_runtime.dart';
import '../../../core/services/workspace/workspace_tools_service.dart';
import '../../../core/providers/workspace_provider.dart';
import 'ask_user_interaction_service.dart';
import 'built_in_tool_names.dart';
import 'local_tools_service.dart';
import 'tool_approval_service.dart';

/// 工具调用处理服务
///
/// 处理各类工具调用：
/// - MCP 工具
/// - Memory 工具 (§10)
/// - Search 工具
class ToolHandlerService {
  ToolHandlerService({required this.contextProvider});

  /// Build context (used for accessing providers)
  final BuildContext contextProvider;

  WorkspaceToolsService _workspaceTools() {
    try {
      final chat = contextProvider.read<ChatService>();
      final workspaces = contextProvider.read<WorkspaceProvider>();
      Future<void> Function(String skillId)? onSkillRead;
      Future<void> Function()? onShellCompleted;
      try {
        final skills = contextProvider.read<SkillsService>();
        onSkillRead = skills.incrementUseCount;
        onShellCompleted = skills.rescan;
      } catch (_) {}
      return WorkspaceToolsService(
        registry: contextProvider.read<ToolRunRegistry>(),
        runtimeProvider: contextProvider.read<WorkspaceRuntimeProvider>(),
        updateConversationExtras: chat.updateConversationExtras,
        readPermissionState: ConversationToolPermissions.forChat(chat).read,
        permissionChanges: chat,
        touchLastUsed: workspaces.touchLastUsed,
        onSkillRead: onSkillRead,
        onShellCompleted: onShellCompleted,
        loadEnvironment: contextProvider
            .read<EnvironmentProvider?>()
            ?.loadExecutionConfig,
        isToolEnabled: (id, name) =>
            workspaces.byId(id)?.isToolEnabled(name) ?? false,
      );
    } catch (_) {
      return WorkspaceToolsService();
    }
  }

  // ============================================================================
  // Tool Schema Sanitization
  // ============================================================================

  /// Sanitize/translate JSON Schema to each provider's accepted subset.
  ///
  /// Different providers (Google, OpenAI, Claude) have different requirements
  /// for tool parameter schemas. This method normalizes schemas to work across
  /// all providers.
  static Map<String, dynamic> sanitizeToolParametersForProvider(
    Map<String, dynamic> schema,
    ProviderKind kind,
  ) {
    Map<String, dynamic> clone = _deepCloneMap(schema);
    // Inline local references before translating provider-specific schema fields.
    clone = resolveJsonSchemaRefs(
      clone,
      preserveJsonSchema: kind != ProviderKind.google,
    );
    if (kind != ProviderKind.google) return clone;
    return _sanitizeGoogleNode(clone) as Map<String, dynamic>;
  }

  static dynamic _sanitizeGoogleNode(dynamic node) {
    if (node is List) {
      return node.map(_sanitizeGoogleNode).toList();
    }
    if (node is! Map) return node;

    final m = Map<String, dynamic>.from(node);
    // Remove $schema as it's not needed for tool definitions
    m.remove(r'$schema');

    // Google's native Schema does not have const.
    if (m.containsKey('const')) {
      final v = m['const'];
      if (v is String || v is num || v is bool) {
        m['enum'] = [v];
        // Keep the declared type in sync so a non-string const is not mistaken
        // for a string enum downstream.
        if (m['type'] == null) {
          if (v is bool) {
            m['type'] = 'boolean';
          } else if (v is int) {
            m['type'] = 'integer';
          } else if (v is num) {
            m['type'] = 'number';
          } else {
            m['type'] = 'string';
          }
        }
      }
      m.remove('const');
    }

    // Keep Google's existing conversion to the native Schema subset.
    for (final key in [
      'anyOf',
      'oneOf',
      'allOf',
      'any_of',
      'one_of',
      'all_of',
    ]) {
      final variants = m[key];
      if (variants is! List) continue;
      if (variants.isNotEmpty) {
        final first = variants.first;
        final flattened = _sanitizeGoogleNode(first);
        m.remove(key);
        if (flattened is Map<String, dynamic>) {
          m
            ..remove('type')
            ..remove('properties')
            ..remove('items');
          m.addAll(flattened);
        }
      }
    }

    // Google's native Schema needs a single type.
    final t = m['type'];
    if (t is List && t.isNotEmpty) {
      m['type'] = t.first.toString();
    }

    // Keep Google's existing conversion of tuple-form items.
    final items = m['items'];
    if (items is List && items.isNotEmpty) {
      m['items'] = items.first;
    }
    if (m['items'] is Map || m['items'] is List) {
      m['items'] = _sanitizeGoogleNode(m['items']);
    }

    if (m['properties'] is Map) {
      final props = Map<String, dynamic>.from(m['properties']);
      final norm = <String, dynamic>{};
      props.forEach((k, v) {
        norm[k] = _sanitizeGoogleNode(v);
      });
      m['properties'] = norm;
    }

    const allowed = {
      'type',
      'description',
      'properties',
      'required',
      'items',
      'enum',
    };
    m.removeWhere((k, v) => !allowed.contains(k));
    return m;
  }

  static Map<String, dynamic> _deepCloneMap(Map<String, dynamic> input) {
    return jsonDecode(jsonEncode(input)) as Map<String, dynamic>;
  }

  static String _toolError({
    required String error,
    required String message,
    required String tool,
    String? instruction,
  }) {
    return jsonEncode({
      'type': 'tool_error',
      'error': error,
      'message': message,
      'tool': tool,
      if (instruction != null) 'instruction': instruction,
    });
  }

  // ============================================================================
  // Tool Definitions Builder
  // ============================================================================

  McpToolRouteSnapshot captureMcpToolRoutes(
    Assistant? assistant, {
    String? conversationId,
  }) {
    return contextProvider.read<McpToolService>().captureRoutesForAssistant(
      contextProvider.read<McpProvider>(),
      contextProvider.read<AssistantProvider>(),
      assistantId: assistant?.id,
      conversation: conversationId == null
          ? null
          : contextProvider.read<ChatService>().getConversation(conversationId),
      reservedNames: BuiltInToolNames.all,
    );
  }

  /// Build tool definitions for API call.
  ///
  /// Returns a list of tool definitions including:
  /// - Search tool (if enabled and model supports tools)
  /// - Memory tools (if assistant has memory / past-recall enabled)
  /// - MCP tools (from the effective conversation or assistant selection)
  /// Whether the chat being generated is a throwaway one.
  ///
  /// Scheduled sends can target a different conversation from the visible one.
  bool _isTemporaryConversation(String? conversationId) {
    try {
      final chatService = contextProvider.read<ChatService>();
      return chatService.isTemporaryConversation(
        conversationId ?? chatService.currentConversationId,
      );
    } catch (_) {
      return false;
    }
  }

  List<Map<String, dynamic>> buildToolDefinitions(
    SettingsProvider settings,
    Assistant? assistant,
    String providerKey,
    String modelId,
    bool hasBuiltInSearch, {
    required bool Function(String providerKey, String modelId) isToolModel,
    McpToolRouteSnapshot? mcpRouteSnapshot,
    WorkspaceToolContext? workspaceContext,
    String? conversationId,
  }) {
    final List<Map<String, dynamic>> toolDefs = <Map<String, dynamic>>[];
    final supportsTools = isToolModel(providerKey, modelId);

    // Search tool (skip when Gemini built-in search is active)
    if (assistant?.searchEnabled == true &&
        !hasBuiltInSearch &&
        supportsTools) {
      toolDefs.add(SearchToolService.getToolDefinition());
      if (settings.webFetchMode != WebFetchMode.off &&
          !native_tools.BuiltInToolsHelper.isBuiltInFetchEnabled(
            cfg: settings.getProviderConfig(providerKey),
            modelId: modelId,
          )) {
        toolDefs.add(WebFetchToolService.getToolDefinition());
      }
    }

    // Memory tools (§10.1)
    if (settings.legacyMemoryMode) {
      if (assistant?.enableMemory == true && supportsTools) {
        toolDefs.addAll(
          MemoryTools.legacyDefinitions(settings.resolvedMemoryPromptLang),
        );
      }
    } else if (supportsTools && assistant != null) {
      toolDefs.addAll(
        MemoryTools.buildDefinitions(
          lang: settings.resolvedMemoryPromptLang,
          writeScope: assistant.memoryWriteScope,
          enableMemory: assistant.enableMemory,
          allowPastConversationRecall: assistant.allowPastConversationRecall,
          allowMemoryWrites: !_isTemporaryConversation(conversationId),
        ),
      );
    }

    // Local tools
    toolDefs.addAll(
      LocalToolsService.buildToolDefinitions(
        assistant: assistant,
        supportsTools: supportsTools,
      ).where(
        (definition) =>
            (definition['function'] as Map)['name'] !=
                BrowserToolsService.toolName ||
            conversationId != null,
      ),
    );

    // MCP tools
    final mcpTools = _buildMcpToolDefinitions(
      settings: settings,
      assistant: assistant,
      providerKey: providerKey,
      supportsTools: supportsTools,
      mcpRouteSnapshot: mcpRouteSnapshot,
      conversationId: conversationId,
    );
    toolDefs.addAll(mcpTools);

    if (supportsTools && workspaceContext != null) {
      final canImageInput = ModelSpecResolver.instance
          .spec(settings.getProviderConfig(providerKey), modelId)
          .input
          .contains(Modality.image);
      toolDefs.addAll(
        _workspaceTools()
            .buildToolDefinitions(workspaceContext)
            .where(
              (definition) =>
                  canImageInput ||
                  (definition['function'] as Map)['name'] != 'view_image',
            ),
      );
    }

    final overrides = settings.toolSchemaOverrides;
    if (overrides.isEmpty) return toolDefs;
    return ToolSchemaOverrides.apply(toolDefs, overrides);
  }

  /// Build MCP tool definitions from connected servers.
  List<Map<String, dynamic>> _buildMcpToolDefinitions({
    required SettingsProvider settings,
    required Assistant? assistant,
    required String providerKey,
    required bool supportsTools,
    McpToolRouteSnapshot? mcpRouteSnapshot,
    String? conversationId,
  }) {
    if (!supportsTools) return [];

    final mcp = contextProvider.read<McpProvider>();
    final toolSvc = contextProvider.read<McpToolService>();
    final tools = toolSvc.listAvailableToolsForAssistant(
      mcp,
      contextProvider.read<AssistantProvider>(),
      assistant?.id,
      conversation: conversationId == null
          ? null
          : contextProvider.read<ChatService>().getConversation(conversationId),
      routeSnapshot: mcpRouteSnapshot,
      reservedNames: BuiltInToolNames.all,
    );

    if (tools.isEmpty) return [];

    final providerCfg = settings.getProviderConfig(providerKey);
    final providerKind = ProviderConfig.classify(
      providerCfg.id,
      explicitType: providerCfg.providerType,
    );

    return tools.map((t) {
      Map<String, dynamic> baseSchema;
      if (t.schema != null && t.schema!.isNotEmpty) {
        baseSchema = Map<String, dynamic>.from(t.schema!);
      } else {
        final props = <String, dynamic>{
          for (final p in t.params) p.name: {'type': (p.type ?? 'string')},
        };
        final required = [
          for (final p in t.params.where((e) => e.required)) p.name,
        ];
        baseSchema = {
          'type': 'object',
          'properties': props,
          if (required.isNotEmpty) 'required': required,
        };
      }
      final sanitized = sanitizeToolParametersForProvider(
        baseSchema,
        providerKind,
      );
      return {
        'type': 'function',
        'function': {
          'name': t.name,
          if ((t.description ?? '').isNotEmpty) 'description': t.description,
          'parameters': sanitized,
        },
      };
    }).toList();
  }

  // ============================================================================
  // Tool Call Handler
  // ============================================================================

  /// Build tool call handler function.
  ///
  /// Returns a function that handles tool calls by name and arguments.
  /// Supports:
  /// - Search tool calls
  /// - Memory tool calls (§10)
  /// - MCP tool calls
  ToolCallHandler? buildToolCallHandler(
    SettingsProvider settings,
    Assistant? assistant, {
    ToolApprovalService? approvalService,
    AskUserInteractionService? askUserService,
    String? conversationId,
    McpToolRouteSnapshot? mcpRouteSnapshot,
    WorkspaceToolContext? workspaceContext,
  }) {
    final mcp = contextProvider.read<McpProvider>();
    final toolSvc = contextProvider.read<McpToolService>();
    // Capture AssistantProvider reference before async gap to avoid
    // use_build_context_synchronously warning
    final assistantProvider = contextProvider.read<AssistantProvider>();
    ChatService? permissionChat;
    try {
      permissionChat = contextProvider.read<ChatService>();
    } catch (_) {}
    final routes =
        mcpRouteSnapshot ??
        toolSvc.captureRoutesForAssistant(
          mcp,
          assistantProvider,
          assistantId: assistant?.id,
          conversation: conversationId == null
              ? null
              : permissionChat?.getConversation(conversationId),
          reservedNames: BuiltInToolNames.all,
        );

    String approvalIdFor(String name, String? toolCallId) {
      final trimmed = toolCallId?.trim();
      if (trimmed != null && trimmed.isNotEmpty) return trimmed;
      return '${name}_${DateTime.now().microsecondsSinceEpoch}';
    }

    ToolCallPermission permissionFor(String name, String? toolCallId) =>
        ToolCallPermission(
          toolName: name,
          toolCallId: approvalIdFor(name, toolCallId),
          conversationId: conversationId,
          assistantId: assistant?.id,
          approvals: approvalService,
          stateChanges: permissionChat,
          readState: () => permissionChat != null && conversationId != null
              ? ConversationToolPermissions.forChat(
                  permissionChat,
                ).read(conversationId)
              : ToolPermissionState(assistantId: assistant?.id),
        );
    Future<Object?> approveAndExecuteMcp(
      String name,
      Map<String, dynamic> args,
      ToolCallPermission permission,
    ) async {
      void checkEnabled() {
        if (!toolSvc.isToolEnabledForAssistant(
          mcp,
          assistantProvider,
          assistantId: assistant?.id,
          conversation: conversationId == null
              ? null
              : permissionChat?.getConversation(conversationId),
          toolName: name,
          routeSnapshot: routes,
        )) {
          throw const ToolPermissionException(
            'tool_disabled',
            'This MCP tool is disabled',
          );
        }
      }

      checkEnabled();
      await permission.authorize(
        needed: toolSvc.toolNeedsApprovalForAssistant(
          mcp,
          assistantProvider,
          assistantId: assistant?.id,
          conversation: conversationId == null
              ? null
              : permissionChat?.getConversation(conversationId),
          toolName: name,
          routeSnapshot: routes,
          reservedNames: BuiltInToolNames.all,
        ),
        arguments: args,
      );
      checkEnabled();
      return toolSvc.callToolForAssistant(
        mcp,
        assistantProvider,
        assistantId: assistant?.id,
        conversation: conversationId == null
            ? null
            : permissionChat?.getConversation(conversationId),
        toolName: name,
        arguments: args,
        routeSnapshot: routes,
        reservedNames: BuiltInToolNames.all,
      );
    }

    final workspaceTools = workspaceContext == null ? null : _workspaceTools();

    return (name, args, {toolCallId}) async {
      final permission = permissionFor(name, toolCallId);
      Future<Object?> execute() async {
        try {
          if (name == BrowserToolsService.toolName) {
            final current = assistant == null
                ? null
                : assistantProvider.getById(assistant.id);
            if (current == null ||
                !current.localToolIds.contains(LocalToolNames.browser) ||
                conversationId == null) {
              return _toolError(
                error: 'permission_denied',
                message:
                    'Browser control is disabled for this assistant or conversation.',
                tool: name,
              );
            }
            return await BrowserToolsService().handle(
              conversationId,
              args,
              capturePreview: settings.showBrowserPageCards,
              temporary: _isTemporaryConversation(conversationId),
            );
          }
          if (workspaceContext != null &&
              workspaceTools != null &&
              WorkspaceToolsService.toolNames.contains(name)) {
            return await workspaceTools.handle(
              workspaceContext,
              name,
              args,
              toolCallId: toolCallId ?? '',
              approvalService: approvalService,
              conversationId: conversationId,
            );
          }

          if (routes.containsExposedName(name)) {
            return await approveAndExecuteMcp(name, args, permission);
          }

          // Search tool
          if (name == SearchToolService.toolName &&
              assistant?.searchEnabled == true) {
            final q = (args['query'] ?? '').toString();
            return await SearchToolService.executeSearch(q, settings);
          }
          if (name == WebFetchToolService.toolName &&
              assistant?.searchEnabled == true) {
            return await WebFetchToolService.executeFetch(args, settings);
          }

          // Memory tools
          final memoryResult = await _handleMemoryToolCall(
            name,
            args,
            assistant,
            conversationId: conversationId,
          );
          if (memoryResult != null) {
            return memoryResult;
          }

          // Full access skips only the ordinary execution prompt.
          if (LocalToolNames.requiresUserApproval.contains(name)) {
            final current = assistant == null
                ? null
                : assistantProvider.getById(assistant.id);
            if (current == null || !current.localToolIds.contains(name)) {
              return _toolError(
                error: 'tool_disabled',
                message: 'This tool is disabled',
                tool: name,
              );
            }
            await permission.authorize(needed: true, arguments: args);
            final latest = assistantProvider.getById(current.id);
            if (latest == null || !latest.localToolIds.contains(name)) {
              return _toolError(
                error: 'tool_disabled',
                message: 'This tool is disabled',
                tool: name,
              );
            }
          }

          // Re-read phone-control permission on every call so disabling it also
          // stops a tool loop that was built with an older assistant snapshot.
          if (name == LocalToolNames.phoneControl) {
            final current = assistant == null
                ? null
                : assistantProvider.getById(assistant.id);
            if (current == null || !current.localToolIds.contains(name)) {
              return _toolError(
                error: 'permission_denied',
                message: 'Phone control is disabled for this assistant.',
                tool: name,
              );
            }
          }

          // Local tools
          final localResult = await LocalToolsService.tryHandleToolCall(
            name,
            args,
            assistant,
            onSpeakText: (text) async {
              final tts = contextProvider.read<TtsProvider>();
              if (!tts.isAvailable) {
                throw StateError('Text-to-speech is unavailable.');
              }
              unawaited(
                tts.speak(text).catchError((Object error, StackTrace stack) {
                  FlutterError.reportError(
                    FlutterErrorDetails(
                      exception: error,
                      stack: stack,
                      library: 'Kelivo local tools',
                      context: ErrorDescription('while playing text-to-speech'),
                    ),
                  );
                }),
              );
            },
          );
          if (localResult != null) {
            return localResult;
          }

          final isManageMcp =
              name == LocalToolNames.manageMcpServers ||
              name == 'manage_mcp_servers' ||
              name == 'manage_mcp' ||
              name == 'mcp_servers' ||
              name == 'create_mcp' ||
              name == 'manage_mcp_server';
          if (isManageMcp) {
            return await _handleManageMcpServers(mcp, args);
          }

          final isManageProviders =
              name == LocalToolNames.manageProviders ||
              name == 'manage_providers' ||
              name == 'manage_provider' ||
              name == 'providers' ||
              name == 'llm_providers' ||
              name == 'add_provider';
          if (isManageProviders) {
            return await _handleManageProviders(settings, args);
          }

          final isConfigureSettings =
              name == LocalToolNames.configureSettings ||
              name == 'configure_settings' ||
              name == 'settings_config' ||
              name == 'app_settings' ||
              name == 'manage_settings' ||
              name == 'settings';
          if (isConfigureSettings) {
            return await _handleConfigureSettings(settings, mcp, args);
          }

          final isAskUser = LocalToolsService.isAskUserTool(name);
          if (isAskUser) {
            if (askUserService == null) {
              return _toolError(
                error: 'ask_user_unavailable',
                message: 'Ask user interaction service is unavailable.',
                tool: name,
              );
            }
            try {
              final result = await askUserService.requestAnswer(
                toolCallId: (toolCallId?.trim().isNotEmpty == true)
                    ? toolCallId!.trim()
                    : '${name}_${DateTime.now().microsecondsSinceEpoch}',
                arguments: args,
                conversationId: conversationId,
              );
              return result.toJsonString();
            } on AskUserInvalidRequestException catch (e) {
              return _toolError(
                error: 'invalid_ask_user_request',
                message: e.message,
                tool: name,
              );
            }
          }

          return await approveAndExecuteMcp(name, args, permission);
        } on ToolPermissionException catch (e) {
          permission.byFullAccess = false;
          return ClientToolResult(
            _toolError(error: e.code, message: e.message, tool: name),
            metadata: {'toolPermissionError': e.code},
          );
        } catch (e) {
          // Catch unexpected exceptions and return error JSON to LLM
          // This prevents tool failures from terminating the chat flow
          return _toolError(
            error: 'execution_error',
            message: e.toString(),
            tool: name,
            instruction:
                'The tool execution failed unexpectedly. You may try again with different parameters or inform the user about the issue.',
          );
        }
      }

      final result = await execute();
      if (!permission.byFullAccess) return result;
      final client = ClientToolResult.fromHandler(result);
      return ClientToolResult(
        client.content,
        metadata: {...?client.metadata, 'toolPermission': 'fullAccess'},
      );
    };
  }

  /// Handle memory tool calls (§10).
  ///
  /// Returns null if the tool is not a memory tool or the relevant gate is off.
  Future<String?> _handleMemoryToolCall(
    String name,
    Map<String, dynamic> args,
    Assistant? assistant, {
    String? conversationId,
  }) async {
    final settings = contextProvider.read<SettingsProvider>();
    if (settings.legacyMemoryMode) {
      if (MemoryTools.allToolNames.contains(name)) return null;
      return _handleLegacyMemoryToolCall(name, args, assistant);
    }

    if (assistant == null) return null;
    if (!MemoryTools.allToolNames.contains(name)) return null;

    final memoryV2 = contextProvider.read<MemoryProviderV2>();
    ChatService? chatService;
    try {
      chatService = contextProvider.read<ChatService>();
    } catch (_) {
      chatService = null;
    }

    MemoryPipelineService? pipeline;
    try {
      pipeline = contextProvider.read<MemoryPipelineService>();
    } catch (_) {
      pipeline = null;
    }

    Future<String> Function(String prompt)? memoryLlmCall;
    final provKey = settings.memoryModelProvider;
    final mdlId = settings.memoryModelId;
    if (provKey != null && mdlId != null) {
      final cfg = settings.getProviderConfig(provKey);
      final reasoning = settings.memoryModelThinkingEnabled
          ? (assistant.reasoning ?? ReasoningRequest.auto)
          : ReasoningRequest.off;
      memoryLlmCall = (prompt) => ChatApiService.generateText(
        conversationId: conversationId,
        config: cfg,
        modelId: mdlId,
        prompt: prompt,
        reasoning: reasoning,
      );
    }

    final temporary =
        chatService?.isTemporaryConversation(conversationId) ?? false;
    return MemoryTools.handle(
      name: name,
      args: args,
      assistant: assistant,
      repository: memoryV2.repository,
      chatRepository: memoryV2.chatRepository,
      chatService: chatService,
      conversationId: conversationId,
      // Reload without changing which assistants the open memory UI is showing.
      onMutated: memoryV2.reloadCurrentScope,
      smartAdd: pipeline?.smartAdd,
      promptLang: settings.resolvedMemoryPromptLang,
      memoryLlmCall: memoryLlmCall,
      smartAddPromptZh: settings.memorySmartAddPromptZh,
      smartAddPromptEn: settings.memorySmartAddPromptEn,
      // Temporary chats are discarded on exit; their tool traces must not linger.
      traceRecorder: temporary ? null : pipeline?.traceRecorder,
      conversationTitle: conversationId == null
          ? null
          : chatService?.getConversation(conversationId)?.title,
    );
  }

  /// Handle legacy create/edit/delete_memory calls via [MemoryProvider].
  ///
  /// Returns null if memory is disabled or [name] is not a legacy memory tool.
  Future<String?> _handleLegacyMemoryToolCall(
    String name,
    Map<String, dynamic> args,
    Assistant? assistant,
  ) async {
    if (assistant?.enableMemory != true) return null;
    if (name != 'create_memory' &&
        name != 'edit_memory' &&
        name != 'delete_memory') {
      return null;
    }

    try {
      final mp = contextProvider.read<MemoryProvider>();

      if (name == 'create_memory') {
        final content = (args['content'] ?? '').toString();
        if (content.isEmpty) {
          return _toolError(
            error: 'invalid_memory_content',
            message: 'Memory content must not be empty.',
            tool: name,
          );
        }
        final m = await mp.add(assistantId: assistant!.id, content: content);
        return m.content;
      } else if (name == 'edit_memory') {
        final id = (args['id'] as num?)?.toInt() ?? -1;
        final content = (args['content'] ?? '').toString();
        if (id <= 0) {
          return _toolError(
            error: 'invalid_memory_id',
            message: 'Memory id must be a positive integer.',
            tool: name,
          );
        }
        if (content.isEmpty) {
          return _toolError(
            error: 'invalid_memory_content',
            message: 'Memory content must not be empty.',
            tool: name,
          );
        }
        final m = await mp.update(id: id, content: content);
        if (m == null) {
          return _toolError(
            error: 'memory_not_found',
            message: 'No memory record was found for id $id.',
            tool: name,
            instruction:
                'Use the available memory records shown in context, or create a new memory instead of editing a missing one.',
          );
        }
        return m.content;
      } else if (name == 'delete_memory') {
        final id = (args['id'] as num?)?.toInt() ?? -1;
        if (id <= 0) {
          return _toolError(
            error: 'invalid_memory_id',
            message: 'Memory id must be a positive integer.',
            tool: name,
          );
        }
        final ok = await mp.delete(id: id);
        if (!ok) {
          return _toolError(
            error: 'memory_not_found',
            message: 'No memory record was found for id $id.',
            tool: name,
            instruction:
                'Use the available memory records shown in context, or skip deleting a missing memory.',
          );
        }
        return 'deleted';
      }
    } catch (e) {
      return _toolError(
        error: 'memory_execution_error',
        message: e.toString(),
        tool: name,
        instruction:
            'The memory tool failed. Retry only after correcting the parameters, or inform the user about the issue.',
      );
    }

    return null;
  }

  static Future<String> _handleManageMcpServers(
    McpProvider mcp,
    Map<String, dynamic> args,
  ) async {
    final action = (args['action'] ?? 'list').toString().toLowerCase().trim();
    switch (action) {
      case 'list':
        final list = mcp.servers.map((s) {
          return {
            'id': s.id,
            'name': s.name,
            'transport': s.transport.name,
            'enabled': s.enabled,
            'url': s.url,
            'status': mcp.statusFor(s.id).name,
            if (s.command != null) 'command': s.command,
            if (s.headers.isNotEmpty) 'headers': s.headers.keys.toList(),
          };
        }).toList();
        return jsonEncode({'status': 'success', 'servers': list});

      case 'add':
        final name = (args['name'] ?? '').toString().trim();
        final rawTransport = (args['transport'] ?? 'http')
            .toString()
            .toLowerCase()
            .trim();
        final url = (args['url'] ?? '').toString().trim();
        final command = (args['command'] ?? '').toString().trim();
        final enabled = args['enabled'] is bool
            ? (args['enabled'] as bool)
            : true;
        final rawHeaders = args['headers'];
        final headers = <String, String>{};
        if (rawHeaders is Map) {
          for (final entry in rawHeaders.entries) {
            headers[entry.key.toString()] = entry.value.toString();
          }
        }
        final rawArgs = args['args'];
        final cmdArgs = rawArgs is List
            ? rawArgs.map((e) => e.toString()).toList()
            : const <String>[];
        final rawEnv = args['env'];
        final env = <String, String>{};
        if (rawEnv is Map) {
          for (final entry in rawEnv.entries) {
            env[entry.key.toString()] = entry.value.toString();
          }
        }

        final transport = switch (rawTransport) {
          'sse' => McpTransportType.sse,
          'stdio' => McpTransportType.stdio,
          _ => McpTransportType.http,
        };

        if (transport != McpTransportType.stdio && url.isEmpty) {
          return jsonEncode({
            'status': 'error',
            'message': 'URL is required for HTTP or SSE transport.',
          });
        }
        if (transport == McpTransportType.stdio && command.isEmpty) {
          return jsonEncode({
            'status': 'error',
            'message': 'Command is required for stdio transport.',
          });
        }

        final serverName = name.isNotEmpty
            ? name
            : (url.isNotEmpty
                  ? Uri.tryParse(url)?.host ?? 'MCP Server'
                  : command);
        final id = await mcp.addServer(
          enabled: enabled,
          name: serverName,
          transport: transport,
          url: url,
          headers: headers,
          command: command.isNotEmpty ? command : null,
          args: cmdArgs,
          env: env,
        );

        return jsonEncode({
          'status': 'success',
          'message': 'MCP server "$serverName" added successfully.',
          'id': id,
          'enabled': enabled,
        });

      case 'update':
        final id = (args['id'] ?? '').toString().trim();
        final name = (args['name'] ?? '').toString().trim();
        McpServerConfig? server;
        if (id.isNotEmpty) {
          server = mcp.getById(id);
        }
        if (server == null && name.isNotEmpty) {
          server = mcp.servers
              .where((s) => s.name.toLowerCase() == name.toLowerCase())
              .firstOrNull;
        }
        if (server == null) {
          return jsonEncode({
            'status': 'error',
            'message':
                'MCP server not found. Provide a valid server id or name.',
          });
        }

        final rawTransport = args['transport']?.toString().toLowerCase().trim();
        final transport = rawTransport == null
            ? server.transport
            : switch (rawTransport) {
                'sse' => McpTransportType.sse,
                'stdio' => McpTransportType.stdio,
                _ => McpTransportType.http,
              };

        Map<String, String>? headers;
        if (args['headers'] is Map) {
          headers = (args['headers'] as Map).map(
            (k, v) => MapEntry(k.toString(), v.toString()),
          );
        }

        final updated = server.copyWith(
          name: name.isNotEmpty ? name : server.name,
          url: args['url'] != null ? args['url'].toString().trim() : server.url,
          enabled: args['enabled'] is bool
              ? (args['enabled'] as bool)
              : server.enabled,
          transport: transport,
          headers: headers ?? server.headers,
        );
        await mcp.updateServer(updated);

        return jsonEncode({
          'status': 'success',
          'message': 'MCP server "${updated.name}" updated successfully.',
          'id': updated.id,
        });

      case 'remove':
      case 'delete':
        final id = (args['id'] ?? '').toString().trim();
        final name = (args['name'] ?? '').toString().trim();
        String? targetId;
        if (id.isNotEmpty && mcp.getById(id) != null) {
          targetId = id;
        } else if (name.isNotEmpty) {
          targetId = mcp.servers
              .where((s) => s.name.toLowerCase() == name.toLowerCase())
              .firstOrNull
              ?.id;
        }
        if (targetId == null) {
          return jsonEncode({
            'status': 'error',
            'message': 'MCP server not found to remove.',
          });
        }
        await mcp.removeServer(targetId);
        return jsonEncode({
          'status': 'success',
          'message': 'MCP server removed successfully.',
          'id': targetId,
        });

      case 'connect':
        final id = (args['id'] ?? '').toString().trim();
        final name = (args['name'] ?? '').toString().trim();
        final target = id.isNotEmpty
            ? mcp.getById(id)
            : mcp.servers
                  .where((s) => s.name.toLowerCase() == name.toLowerCase())
                  .firstOrNull;
        if (target == null) {
          return jsonEncode({
            'status': 'error',
            'message': 'MCP server not found.',
          });
        }
        if (!target.enabled) {
          await mcp.updateServer(target.copyWith(enabled: true));
        }
        await mcp.connect(target.id);
        return jsonEncode({
          'status': 'success',
          'message': 'Connected to MCP server "${target.name}".',
          'id': target.id,
        });

      case 'disconnect':
        final id = (args['id'] ?? '').toString().trim();
        final name = (args['name'] ?? '').toString().trim();
        final target = id.isNotEmpty
            ? mcp.getById(id)
            : mcp.servers
                  .where((s) => s.name.toLowerCase() == name.toLowerCase())
                  .firstOrNull;
        if (target == null) {
          return jsonEncode({
            'status': 'error',
            'message': 'MCP server not found.',
          });
        }
        await mcp.disconnect(target.id);
        return jsonEncode({
          'status': 'success',
          'message': 'Disconnected from MCP server "${target.name}".',
          'id': target.id,
        });

      default:
        return jsonEncode({
          'status': 'error',
          'message':
              'Unsupported action: $action. Use list, add, update, remove, connect, or disconnect.',
        });
    }
  }

  static Future<String> _handleManageProviders(
    SettingsProvider settings,
    Map<String, dynamic> args,
  ) async {
    final action = (args['action'] ?? 'list').toString().toLowerCase().trim();
    final providerKey = (args['provider'] ?? args['id'] ?? '')
        .toString()
        .toLowerCase()
        .trim();

    switch (action) {
      case 'list':
        final configs = settings.providerConfigs;
        final list = configs.entries.map((e) {
          return {
            'provider': e.key,
            'name': e.value.name,
            'enabled': e.value.enabled,
            'baseUrl': e.value.baseUrl,
            'hasApiKey': e.value.apiKey.isNotEmpty,
            'modelsCount': e.value.models.length,
            'enabledModels': e.value.enabledModels.toList(),
          };
        }).toList();
        return jsonEncode({'status': 'success', 'providers': list});

      case 'get':
        if (providerKey.isEmpty) {
          return jsonEncode({
            'status': 'error',
            'message': 'Please provide provider name/key.',
          });
        }
        final cfg = settings.getProviderConfig(providerKey);
        return jsonEncode({
          'status': 'success',
          'provider': cfg.id,
          'name': cfg.name,
          'enabled': cfg.enabled,
          'baseUrl': cfg.baseUrl,
          'hasApiKey': cfg.apiKey.isNotEmpty,
          'models': cfg.models,
          'enabledModels': cfg.enabledModels.toList(),
        });

      case 'add':
      case 'update':
        if (providerKey.isEmpty) {
          return jsonEncode({
            'status': 'error',
            'message':
                'Provider identifier is required (e.g. "openai", "anthropic", "google", "deepseek", "xai", "groq", "openrouter", "ollama").',
          });
        }
        final existing = settings.getProviderConfig(providerKey);
        final apiKey = args['api_key']?.toString().trim();
        final baseUrl = args['base_url']?.toString().trim();
        final name = args['name']?.toString().trim();
        final enabled = args['enabled'] is bool
            ? (args['enabled'] as bool)
            : true;
        List<String>? models;
        if (args['models'] is List) {
          models = (args['models'] as List)
              .map((e) => e.toString().trim())
              .where((s) => s.isNotEmpty)
              .toList();
        }

        final updated = existing.copyWith(
          name: (name != null && name.isNotEmpty) ? name : existing.name,
          apiKey: apiKey ?? existing.apiKey,
          baseUrl: (baseUrl != null && baseUrl.isNotEmpty)
              ? baseUrl
              : existing.baseUrl,
          enabled: enabled,
          models: (models != null && models.isNotEmpty)
              ? models
              : existing.models,
        );

        await settings.setProviderConfig(providerKey, updated);

        return jsonEncode({
          'status': 'success',
          'message': 'Provider "$providerKey" configured successfully.',
          'provider': providerKey,
          'enabled': updated.enabled,
          'baseUrl': updated.baseUrl,
          'hasApiKey': updated.apiKey.isNotEmpty,
        });

      case 'remove':
      case 'disable':
        if (providerKey.isEmpty) {
          return jsonEncode({
            'status': 'error',
            'message': 'Provider key is required.',
          });
        }
        final existing = settings.getProviderConfig(providerKey);
        await settings.setProviderConfig(
          providerKey,
          existing.copyWith(enabled: false),
        );
        return jsonEncode({
          'status': 'success',
          'message': 'Provider "$providerKey" disabled successfully.',
          'provider': providerKey,
        });

      default:
        return jsonEncode({
          'status': 'error',
          'message':
              'Unsupported action: $action. Use list, get, add, update, or remove.',
        });
    }
  }

  static Future<String> _handleConfigureSettings(
    SettingsProvider settings,
    McpProvider mcp,
    Map<String, dynamic> args,
  ) async {
    final action = (args['action'] ?? 'get').toString().toLowerCase().trim();
    switch (action) {
      case 'get':
        final composioKey = await ComposioService.instance.getStoredApiKey();
        return jsonEncode({
          'status': 'success',
          'themeMode': settings.themeMode.name,
          'searchEnabled': settings.searchEnabled,
          'hasComposioKey': composioKey != null && composioKey.isNotEmpty,
          'composioKeyType': composioKey == null
              ? 'none'
              : (composioKey.startsWith('ck_')
                    ? 'consumer_mcp'
                    : 'project_api'),
          'ttsSelected': settings.ttsServiceSelected,
          'searchSelected': settings.searchServiceSelected,
        });

      case 'update':
        final updates = <String>[];
        // 1. Composio API key
        if (args['composio_api_key'] != null) {
          final rawKey = args['composio_api_key'].toString().trim();
          if (rawKey.isNotEmpty) {
            await ComposioService.instance.setStoredApiKey(rawKey);
            final val = await ComposioService.instance.validateKey(rawKey);
            if (val.isValid && rawKey.startsWith('ck_')) {
              // Auto-configure Composio MCP server
              final existing = mcp.servers
                  .where(
                    (s) =>
                        s.name.toLowerCase() == 'composio' ||
                        s.id == 'composio',
                  )
                  .firstOrNull;
              if (existing != null) {
                await mcp.updateServer(
                  existing.copyWith(
                    enabled: true,
                    url: 'https://connect.composio.dev/mcp',
                    transport: McpTransportType.http,
                    headers: {'x-consumer-api-key': rawKey},
                  ),
                );
                unawaited(mcp.connect(existing.id));
              } else {
                final id = await mcp.addServer(
                  enabled: true,
                  name: 'Composio',
                  transport: McpTransportType.http,
                  url: 'https://connect.composio.dev/mcp',
                  headers: {'x-consumer-api-key': rawKey},
                );
                unawaited(mcp.connect(id));
              }
              updates.add('Composio key validated & MCP server connected');
            } else if (val.isValid) {
              updates.add('Composio project key saved and validated');
            } else {
              updates.add('Composio key saved with notice: ${val.error}');
            }
          } else {
            await ComposioService.instance.setStoredApiKey('');
            updates.add('Composio key removed');
          }
        }

        // 2. Theme mode
        if (args['theme_mode'] != null) {
          final modeStr = args['theme_mode'].toString().toLowerCase().trim();
          final mode = switch (modeStr) {
            'light' => ThemeMode.light,
            'dark' => ThemeMode.dark,
            _ => ThemeMode.system,
          };
          await settings.setThemeMode(mode);
          updates.add('Theme mode set to $modeStr');
        }

        // 3. Search provider
        if (args['search_provider'] != null) {
          final providerName = args['search_provider']
              .toString()
              .toLowerCase()
              .trim();
          final idx = settings.searchServices.indexWhere(
            (s) => s.id.toLowerCase().contains(providerName),
          );
          if (idx >= 0) {
            await settings.setSearchServiceSelected(idx);
            await settings.setSearchEnabled(true);
            updates.add(
              'Search provider set to ${settings.searchServices[idx].id}',
            );
          }
        }

        // 4. TTS Service
        if (args['tts_service'] != null) {
          final ttsName = args['tts_service'].toString().toLowerCase().trim();
          final idx = settings.ttsServices.indexWhere(
            (s) =>
                s.name.toLowerCase().contains(ttsName) ||
                s.id.toLowerCase().contains(ttsName),
          );
          if (idx >= 0) {
            await settings.setTtsServiceSelected(idx);
            updates.add('TTS service set to ${settings.ttsServices[idx].name}');
          }
        }

        return jsonEncode({
          'status': 'success',
          'message': updates.isNotEmpty
              ? updates.join('; ')
              : 'No settings changed.',
        });

      default:
        return jsonEncode({
          'status': 'error',
          'message': 'Unsupported action: $action. Use get or update.',
        });
    }
  }
}
