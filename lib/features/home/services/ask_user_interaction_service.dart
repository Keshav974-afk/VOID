import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

class AskUserToolNames {
  const AskUserToolNames._();

  static const String askUser = 'ask_user_input_v0';
}

enum AskUserQuestionKind { single, multi }

class AskUserInvalidRequestException implements Exception {
  const AskUserInvalidRequestException(this.message);

  final String message;

  @override
  String toString() => message;
}

class AskUserQuestion {
  const AskUserQuestion({
    required this.id,
    required this.question,
    required this.kind,
    this.options = const <String>[],
  });

  final String id;
  final String question;
  final AskUserQuestionKind kind;
  final List<String> options;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'question': question,
      'type': kind.name,
      if (options.isNotEmpty) 'options': options,
    };
  }
}

class AskUserAnswerValue {
  const AskUserAnswerValue._({
    required this.kind,
    required this.value,
    required this.custom,
    this.skipped = false,
  });

  const AskUserAnswerValue.single({required String value, required bool custom})
    : this._(kind: AskUserQuestionKind.single, value: value, custom: custom);

  const AskUserAnswerValue.multi({
    required List<String> value,
    required bool custom,
  }) : this._(kind: AskUserQuestionKind.multi, value: value, custom: custom);

  const AskUserAnswerValue.skipped({required AskUserQuestionKind kind})
    : this._(kind: kind, value: '', custom: false, skipped: true);

  final AskUserQuestionKind kind;
  final Object value;
  final bool custom;
  final bool skipped;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'type': kind.name,
      'value': value,
      'custom': custom,
      'skipped': skipped,
    };
  }
}

class AskUserResult {
  const AskUserResult.answer(this.answers)
    : error = null,
      message = null,
      tool = AskUserToolNames.askUser;
  const AskUserResult.error({
    required this.error,
    required this.message,
    this.tool = AskUserToolNames.askUser,
  }) : answers = const <String, AskUserAnswerValue>{};

  final Map<String, AskUserAnswerValue> answers;
  final String? error;
  final String? message;
  final String tool;

  String toJsonString() {
    if (error != null) {
      return jsonEncode(<String, dynamic>{
        'type': 'tool_error',
        'error': error,
        'message': message ?? '',
        'tool': tool,
      });
    }

    return jsonEncode(<String, dynamic>{
      'type': 'ask_user_answer',
      'answers': answers.map(
        (key, value) => MapEntry<String, dynamic>(key, value.toJson()),
      ),
    });
  }
}

class AskUserRequest {
  AskUserRequest({
    required this.toolCallId,
    required this.questions,
    this.conversationId,
    required this._completer,
  });

  final String toolCallId;
  final List<AskUserQuestion> questions;
  final String? conversationId;
  final Completer<AskUserResult> _completer;
}

class AskUserInteractionService extends ChangeNotifier {
  final Map<String, AskUserRequest> _pending = <String, AskUserRequest>{};

  Map<String, AskUserRequest> get pendingRequests => Map.unmodifiable(_pending);

  bool isPending(String toolCallId) => _pending.containsKey(toolCallId);

  AskUserRequest? requestFor({String? toolCallId, String? conversationId}) {
    if (toolCallId != null && toolCallId.trim().isNotEmpty) {
      final id = toolCallId.trim();
      if (_pending.containsKey(id)) return _pending[id];
      for (final req in _pending.values) {
        if (req.toolCallId == id ||
            req.toolCallId.contains(id) ||
            id.contains(req.toolCallId)) {
          return req;
        }
      }
    }
    if (conversationId != null && conversationId.trim().isNotEmpty) {
      for (final req in _pending.values) {
        if (req.conversationId == conversationId) return req;
      }
    }
    if (_pending.isNotEmpty) {
      return _pending.values.last;
    }
    return null;
  }

  Future<AskUserResult> requestAnswer({
    required String toolCallId,
    required Map<String, dynamic> arguments,
    String? conversationId,
  }) {
    final questions = normalizeQuestions(arguments);
    if (questions.isEmpty) {
      throw const AskUserInvalidRequestException(
        'questions must contain at least one question',
      );
    }

    final completer = Completer<AskUserResult>();
    final key = toolCallId.trim().isEmpty
        ? 'ask_user_input_v0_${DateTime.now().microsecondsSinceEpoch}'
        : toolCallId.trim();
    _pending[key] = AskUserRequest(
      toolCallId: key,
      questions: questions,
      conversationId: conversationId,
      completer: completer,
    );
    notifyListeners();
    return completer.future;
  }

  void answer(
    String toolCallId,
    Map<String, AskUserAnswerValue> answers, {
    String? conversationId,
  }) {
    var request = _pending.remove(toolCallId);
    if (request == null) {
      request = requestFor(
        toolCallId: toolCallId,
        conversationId: conversationId,
      );
      if (request != null) {
        _pending.remove(request.toolCallId);
      }
    }
    if (request == null && _pending.isNotEmpty) {
      final firstKey = _pending.keys.first;
      request = _pending.remove(firstKey);
    }
    if (request != null && !request._completer.isCompleted) {
      request._completer.complete(AskUserResult.answer(answers));
    }
    notifyListeners();
  }

  void cancelAll() {
    for (final request in _pending.values) {
      if (!request._completer.isCompleted) {
        request._completer.complete(
          const AskUserResult.error(
            error: 'cancelled',
            message: 'Ask user request was cancelled.',
          ),
        );
      }
    }
    _pending.clear();
    notifyListeners();
  }

  /// Cancel pending requests that belong to [conversationId]. Requests with
  /// no recorded conversation are cancelled too (fail-safe against leaking a
  /// blocked tool handler), but requests owned by other conversations keep
  /// waiting so cancelling one conversation cannot break another's stream.
  void cancelForConversation(String conversationId) {
    final toCancel = _pending.values
        .where(
          (request) =>
              request.conversationId == null ||
              request.conversationId == conversationId,
        )
        .toList();
    if (toCancel.isEmpty) return;
    for (final request in toCancel) {
      _pending.remove(request.toolCallId);
      if (!request._completer.isCompleted) {
        request._completer.complete(
          const AskUserResult.error(
            error: 'cancelled',
            message: 'Ask user request was cancelled.',
          ),
        );
      }
    }
    notifyListeners();
  }

  static List<AskUserQuestion> normalizeQuestions(
    Map<String, dynamic> arguments,
  ) {
    Map<String, dynamic> args = arguments;
    if (args.containsKey('input') && args['input'] is Map) {
      args = (args['input'] as Map).cast<String, dynamic>();
    } else if (args.containsKey('parameters') && args['parameters'] is Map) {
      args = (args['parameters'] as Map).cast<String, dynamic>();
    } else if (args.containsKey('args') && args['args'] is Map) {
      args = (args['args'] as Map).cast<String, dynamic>();
    }

    final questions = <AskUserQuestion>[];
    final usedIds = <String>{};

    void addQuestion({
      required String? id,
      required String question,
      AskUserQuestionKind kind = AskUserQuestionKind.single,
      List<String> options = const <String>[],
    }) {
      final cleanQuestion = question.trim();
      if (cleanQuestion.isEmpty) return;

      var cleanId = (id ?? '').trim();
      if (cleanId.isEmpty || usedIds.contains(cleanId)) {
        cleanId = 'q${questions.length + 1}';
      }
      while (usedIds.contains(cleanId)) {
        cleanId = 'q${questions.length + 1}_${usedIds.length + 1}';
      }
      usedIds.add(cleanId);

      questions.add(
        AskUserQuestion(
          id: cleanId,
          question: cleanQuestion,
          kind: kind,
          options: options,
        ),
      );
    }

    var rawQuestions = args['questions'];
    if (rawQuestions is String) {
      final trimmed = rawQuestions.trim();
      if ((trimmed.startsWith('[') && trimmed.endsWith(']')) ||
          (trimmed.startsWith('{') && trimmed.endsWith('}'))) {
        try {
          rawQuestions = jsonDecode(trimmed);
        } catch (_) {}
      }
    }
    if (rawQuestions is Map) {
      rawQuestions = [rawQuestions];
    }

    // 1. If arguments['questions'] is a List
    if (rawQuestions is List && rawQuestions.isNotEmpty) {
      for (final raw in rawQuestions.take(6)) {
        if (raw is Map) {
          final map = raw.cast<String, dynamic>();
          final qText =
              (map['question'] ??
                      map['prompt'] ??
                      map['query'] ??
                      map['text'] ??
                      map['title'] ??
                      map['message'] ??
                      map['label'] ??
                      '')
                  .toString();
          final qId = (map['id'] ?? map['name'] ?? map['key'])?.toString();
          final isMulti =
              map['is_multi_select'] == true ||
              map['multi_select'] == true ||
              map['multiple'] == true ||
              _kindFromString((map['type'] ?? '').toString()) ==
                  AskUserQuestionKind.multi;
          final options = _normalizeOptions(
            map['options'] ??
                map['choices'] ??
                map['items'] ??
                map['suggestions'] ??
                map['values'] ??
                args['options'] ??
                args['choices'],
          );
          addQuestion(
            id: qId,
            question: qText,
            kind: isMulti
                ? AskUserQuestionKind.multi
                : AskUserQuestionKind.single,
            options: options,
          );
        } else if (raw is String && raw.trim().isNotEmpty) {
          final trimmed = raw.trim();
          if (trimmed.startsWith('{') && trimmed.endsWith('}')) {
            try {
              final decoded = jsonDecode(trimmed);
              if (decoded is Map) {
                final map = decoded.cast<String, dynamic>();
                final qText =
                    (map['question'] ?? map['prompt'] ?? map['text'] ?? '')
                        .toString();
                final qId = (map['id'] ?? map['name'])?.toString();
                final isMulti =
                    map['is_multi_select'] == true ||
                    map['multi_select'] == true;
                final options = _normalizeOptions(
                  map['options'] ?? map['choices'],
                );
                addQuestion(
                  id: qId,
                  question: qText,
                  kind: isMulti
                      ? AskUserQuestionKind.multi
                      : AskUserQuestionKind.single,
                  options: options,
                );
                continue;
              }
            } catch (_) {}
          }
          final topLevelOptions = _normalizeOptions(
            args['options'] ??
                args['choices'] ??
                args['items'] ??
                args['suggestions'] ??
                args['values'],
          );
          final isMulti =
              args['is_multi_select'] == true ||
              args['multi_select'] == true ||
              args['multiple'] == true;
          addQuestion(
            id: null,
            question: raw,
            kind: isMulti
                ? AskUserQuestionKind.multi
                : AskUserQuestionKind.single,
            options: topLevelOptions,
          );
        }
      }
    }

    // 2. If no questions extracted yet, check top-level single question keys
    if (questions.isEmpty) {
      final singleText =
          (args['question'] ??
                  (rawQuestions is String ? rawQuestions : null) ??
                  args['prompt'] ??
                  args['query'] ??
                  args['text'] ??
                  args['message'] ??
                  args['title'] ??
                  args['input'] ??
                  args['content'] ??
                  '')
              .toString()
              .trim();
      if (singleText.isNotEmpty) {
        final isMulti =
            args['is_multi_select'] == true ||
            args['multi_select'] == true ||
            args['multiple'] == true ||
            _kindFromString((args['type'] ?? '').toString()) ==
                AskUserQuestionKind.multi;
        final options = _normalizeOptions(
          args['options'] ??
              args['choices'] ??
              args['items'] ??
              args['suggestions'] ??
              args['values'],
        );
        addQuestion(
          id: (args['id'] ?? 'q1').toString(),
          question: singleText,
          kind: isMulti
              ? AskUserQuestionKind.multi
              : AskUserQuestionKind.single,
          options: options,
        );
      }
    }

    // 3. Fallback: inspect arguments for any question-like string parameter
    if (questions.isEmpty) {
      for (final entry in args.entries) {
        if (entry.value is String) {
          final str = (entry.value as String).trim();
          if (str.isNotEmpty && (str.endsWith('?') || str.length > 5)) {
            addQuestion(id: 'q1', question: str);
            break;
          }
        }
      }
    }

    return questions;
  }

  static AskUserQuestionKind _kindFromString(String value) {
    final lower = value.trim().toLowerCase();
    if (lower == 'multi' ||
        lower == 'multi_select' ||
        lower == 'multiple' ||
        lower == 'checkbox') {
      return AskUserQuestionKind.multi;
    }
    return AskUserQuestionKind.single;
  }

  static List<String> _normalizeOptions(dynamic rawOptions) {
    var source = rawOptions;
    if (source is String) {
      final trimmed = source.trim();
      if (trimmed.startsWith('[') && trimmed.endsWith(']')) {
        try {
          source = jsonDecode(trimmed);
        } catch (_) {}
      }
    }
    if (source is! List) return const <String>[];
    final out = <String>[];
    for (final raw in source) {
      String text = '';
      if (raw is Map) {
        text =
            (raw['label'] ??
                    raw['value'] ??
                    raw['text'] ??
                    raw['title'] ??
                    raw['name'] ??
                    '')
                .toString()
                .trim();
      } else {
        text = raw.toString().trim();
      }
      if (text.isEmpty || out.contains(text)) continue;
      out.add(text);
      if (out.length >= 8) break;
    }
    return out;
  }
}
