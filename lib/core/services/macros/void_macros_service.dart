import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class VoidMacroRecipe {
  const VoidMacroRecipe({
    required this.id,
    required this.title,
    required this.description,
    required this.category,
    required this.steps,
    required this.createdAt,
    this.isBuiltIn = false,
  });

  final String id;
  final String title;
  final String description;
  final String category;
  final List<String> steps;
  final DateTime createdAt;
  final bool isBuiltIn;

  String buildExecutionPrompt({String? customInput}) {
    final buffer = StringBuffer()
      ..writeln('### ⚡ VOID Autonomous Agent Macro: **$title**')
      ..writeln(description)
      ..writeln(
        '\nExecute the following workflow steps autonomously and thoroughly:',
      );
    for (var i = 0; i < steps.length; i++) {
      buffer.writeln('${i + 1}. ${steps[i]}');
    }
    if (customInput != null && customInput.trim().isNotEmpty) {
      buffer.writeln('\n**Target / Context**: ${customInput.trim()}');
    }
    buffer.writeln(
      '\nUse available local tools (Browser, Search, Screen/Desktop/Phone Control, Connectors, or Code) as needed and present a clear, structured final result.',
    );
    return buffer.toString();
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'description': description,
    'category': category,
    'steps': steps,
    'createdAt': createdAt.toIso8601String(),
    'isBuiltIn': isBuiltIn,
  };

  factory VoidMacroRecipe.fromJson(Map<String, dynamic> json) {
    return VoidMacroRecipe(
      id: (json['id'] ?? '').toString(),
      title: (json['title'] ?? 'Untitled Macro').toString(),
      description: (json['description'] ?? '').toString(),
      category: (json['category'] ?? 'Automation').toString(),
      steps:
          (json['steps'] as List?)?.map((e) => e.toString()).toList() ??
          const [],
      createdAt:
          DateTime.tryParse((json['createdAt'] ?? '').toString()) ??
          DateTime.now(),
      isBuiltIn: json['isBuiltIn'] == true,
    );
  }
}

class VoidMacrosService extends ChangeNotifier {
  VoidMacrosService._();
  static final VoidMacrosService instance = VoidMacrosService._();

  static const String _prefsKey = 'void_agent_macros_v1';

  static final List<VoidMacroRecipe> _builtInMacros = [
    VoidMacroRecipe(
      id: 'builtin_morning_brief',
      title: 'Executive Morning Briefing',
      description:
          'Gathers current date/time, checks weather & top tech/world headlines, and compiles an actionable daily brief.',
      category: 'Productivity',
      steps: const [
        'Check current local time, date, and weather conditions if available.',
        'Search for the top 5 technology, AI, and global market developments today.',
        'Review any upcoming reminders or calendar items if accessible.',
        'Synthesize a concise, high-signal 60-second Executive Briefing with priority action items.',
      ],
      createdAt: DateTime(2026, 1, 1),
      isBuiltIn: true,
    ),
    VoidMacroRecipe(
      id: 'builtin_deep_web_research',
      title: 'Deep Multi-Source Web Research',
      description:
          'Uses Browser & Search tools to investigate a topic across multiple sources, cross-check claims, and produce a cited report.',
      category: 'Research',
      steps: const [
        'Break the target topic into 3 key investigative questions.',
        'Search and browse authoritative sources to gather primary data and benchmarks.',
        'Cross-verify conflicting claims and extract concrete numbers or code examples.',
        'Deliver a comprehensive Markdown report with Executive Summary, Comparison Table, and Citations.',
      ],
      createdAt: DateTime(2026, 1, 1),
      isBuiltIn: true,
    ),
    VoidMacroRecipe(
      id: 'builtin_screen_bug_audit',
      title: 'Screen & Workspace Bug Hunter',
      description:
          'Captures or inspects the current screen/workspace, diagnoses errors or UI issues, and provides an immediate fix.',
      category: 'Developer',
      steps: const [
        'Inspect the active screen, terminal output, or attached error context.',
        'Identify the root cause of any visible exception, layout issue, or bottleneck.',
        'Formulate the cleanest, production-ready code fix with zero regressions.',
        'Provide step-by-step verification instructions.',
      ],
      createdAt: DateTime(2026, 1, 1),
      isBuiltIn: true,
    ),
    VoidMacroRecipe(
      id: 'builtin_competitor_teardown',
      title: 'Product & Repo Architecture Teardown',
      description:
          'Analyzes a website, product, or GitHub repository and maps out its stack, strengths, weaknesses, and opportunities.',
      category: 'Strategy',
      steps: const [
        'Inspect the target URL, product, or repository structure.',
        'Analyze core features, UX flows, and technical architecture.',
        'Identify 3 key differentiators and 3 exploitable gaps.',
        'Output an actionable product & engineering roadmap table.',
      ],
      createdAt: DateTime(2026, 1, 1),
      isBuiltIn: true,
    ),
  ];

  List<VoidMacroRecipe> _customMacros = [];
  bool _loaded = false;

  List<VoidMacroRecipe> get macros => [..._customMacros, ..._builtInMacros];

  Future<void> ensureLoaded() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw != null && raw.isNotEmpty) {
      try {
        final list = jsonDecode(raw) as List;
        _customMacros = list
            .whereType<Map>()
            .map((m) => VoidMacroRecipe.fromJson(Map<String, dynamic>.from(m)))
            .toList();
      } catch (_) {
        _customMacros = [];
      }
    }
    _loaded = true;
    notifyListeners();
  }

  Future<VoidMacroRecipe> addMacro({
    required String title,
    required String description,
    String category = 'Custom',
    required List<String> steps,
  }) async {
    await ensureLoaded();
    final macro = VoidMacroRecipe(
      id: 'macro_${DateTime.now().microsecondsSinceEpoch}',
      title: title.trim().isEmpty ? 'Custom Agent Macro' : title.trim(),
      description: description.trim().isEmpty
          ? 'Recorded multi-step VOID agent workflow.'
          : description.trim(),
      category: category,
      steps: steps.where((s) => s.trim().isNotEmpty).toList(),
      createdAt: DateTime.now(),
      isBuiltIn: false,
    );
    _customMacros = [macro, ..._customMacros];
    await _persist();
    notifyListeners();
    return macro;
  }

  Future<void> deleteMacro(String id) async {
    await ensureLoaded();
    _customMacros = _customMacros.where((m) => m.id != id).toList();
    await _persist();
    notifyListeners();
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _prefsKey,
      jsonEncode(_customMacros.map((m) => m.toJson()).toList()),
    );
  }
}
