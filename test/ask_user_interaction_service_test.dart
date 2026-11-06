import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:Kelivo/features/home/services/ask_user_interaction_service.dart';

void main() {
  group('AskUserInteractionService', () {
    test(
      'normalizes questions and completes with structured answers',
      () async {
        final service = AskUserInteractionService();
        final future = service.requestAnswer(
          toolCallId: 'call_1',
          arguments: const {
            'questions': [
              {
                'id': 'scope',
                'question': 'Choose scope?',
                'type': 'single',
                'options': ['Minimal', 'Complete'],
              },
              {
                'id': 'scope',
                'question': 'Add what?',
                'type': 'multi',
                'options': ['UI', 'Tests', ''],
              },
              {'question': 'Fallback choice?', 'type': 'unknown'},
            ],
          },
        );

        expect(service.pendingRequests.keys, contains('call_1'));
        final request = service.pendingRequests['call_1']!;
        expect(request.questions.map((question) => question.id), const [
          'scope',
          'q2',
          'q3',
        ]);
        expect(request.questions[0].kind, AskUserQuestionKind.single);
        expect(request.questions[1].kind, AskUserQuestionKind.multi);
        expect(request.questions[1].options, const ['UI', 'Tests']);
        expect(request.questions[2].kind, AskUserQuestionKind.single);

        service.answer('call_1', {
          'scope': const AskUserAnswerValue.single(
            value: 'Complete',
            custom: false,
          ),
          'q2': const AskUserAnswerValue.multi(
            value: ['UI', 'Tests'],
            custom: false,
          ),
          'q3': const AskUserAnswerValue.skipped(
            kind: AskUserQuestionKind.single,
          ),
        });

        final result = await future;
        expect(service.pendingRequests, isEmpty);
        final payload =
            jsonDecode(result.toJsonString()) as Map<String, dynamic>;
        expect(payload['type'], 'ask_user_answer');
        expect(payload['answers']['scope']['value'], 'Complete');
        expect(payload['answers']['q2']['value'], const ['UI', 'Tests']);
        expect(payload['answers']['q3']['skipped'], isTrue);
      },
    );

    test('throws for empty questions before creating pending request', () {
      final service = AskUserInteractionService();

      expect(
        () => service.requestAnswer(
          toolCallId: 'call_1',
          arguments: const {'questions': []},
        ),
        throwsA(isA<AskUserInvalidRequestException>()),
      );
      expect(service.pendingRequests, isEmpty);
    });

    test(
      'cancelAll completes pending requests with cancelled result',
      () async {
        final service = AskUserInteractionService();
        final future = service.requestAnswer(
          toolCallId: 'call_1',
          arguments: const {
            'questions': [
              {'id': 'notes', 'question': 'Any notes?', 'type': 'single'},
            ],
          },
        );

        service.cancelAll();

        final result = await future.timeout(const Duration(seconds: 1));
        expect(service.pendingRequests, isEmpty);
        final payload =
            jsonDecode(result.toJsonString()) as Map<String, dynamic>;
        expect(payload['type'], 'tool_error');
        expect(payload['error'], 'cancelled');
        expect(payload['tool'], 'ask_user_input_v0');
      },
    );

    test('keeps choice questions even when options are sparse', () async {
      final service = AskUserInteractionService();
      unawaited(
        service.requestAnswer(
          toolCallId: 'call_1',
          arguments: const {
            'questions': [
              {
                'id': 'scope',
                'question': 'Choose scope?',
                'type': 'single',
                'options': ['Only one'],
              },
            ],
          },
        ),
      );

      expect(
        service.pendingRequests['call_1']!.questions.single.kind,
        AskUserQuestionKind.single,
      );
      service.cancelAll();
    });

    test('normalizes top-level single question and options', () {
      final questions = AskUserInteractionService.normalizeQuestions(const {
        'question': 'Which database do you prefer?',
        'options': ['Drift', 'Isar', 'Hive'],
      });
      expect(questions.length, 1);
      expect(questions.first.question, 'Which database do you prefer?');
      expect(questions.first.options, const ['Drift', 'Isar', 'Hive']);
      expect(questions.first.kind, AskUserQuestionKind.single);
    });

    test('normalizes prompt and choices with multi select', () {
      final questions = AskUserInteractionService.normalizeQuestions(const {
        'prompt': 'Select features to enable:',
        'choices': ['TTS', 'MCP', 'Search'],
        'is_multi_select': true,
      });
      expect(questions.length, 1);
      expect(questions.first.question, 'Select features to enable:');
      expect(questions.first.options, const ['TTS', 'MCP', 'Search']);
      expect(questions.first.kind, AskUserQuestionKind.multi);
    });

    test('normalizes list of question strings', () {
      final questions = AskUserInteractionService.normalizeQuestions(const {
        'questions': ['What is your project name?', 'Select a license'],
      });
      expect(questions.length, 2);
      expect(questions[0].question, 'What is your project name?');
      expect(questions[0].id, 'q1');
      expect(questions[1].question, 'Select a license');
      expect(questions[1].id, 'q2');
    });

    test('normalizes map-based options with labels and supports up to 8', () {
      final questions = AskUserInteractionService.normalizeQuestions(const {
        'questions': [
          {
            'question': 'Pick a number',
            'options': [
              {'label': 'One', 'value': 1},
              {'label': 'Two', 'value': 2},
              {'label': 'Three', 'value': 3},
              {'label': 'Four', 'value': 4},
              {'label': 'Five', 'value': 5},
              {'label': 'Six', 'value': 6},
              {'label': 'Seven', 'value': 7},
              {'label': 'Eight', 'value': 8},
              {'label': 'Nine', 'value': 9},
            ],
          },
        ],
      });
      expect(questions.single.options.length, 8);
      expect(questions.single.options.first, 'One');
      expect(questions.single.options.last, 'Eight');
    });

    test('requestFor and flexible answer resolution', () async {
      final service = AskUserInteractionService();
      final future = service.requestAnswer(
        toolCallId: 'ask_user_input_v0_12345',
        arguments: const {
          'question': 'Do you want to proceed?',
          'options': ['Yes', 'No'],
        },
        conversationId: 'conv_abc',
      );

      // Find by exact
      expect(
        service.requestFor(toolCallId: 'ask_user_input_v0_12345')?.toolCallId,
        'ask_user_input_v0_12345',
      );

      // Find by substring
      expect(
        service.requestFor(toolCallId: '12345')?.toolCallId,
        'ask_user_input_v0_12345',
      );

      // Find by conversationId
      expect(
        service.requestFor(conversationId: 'conv_abc')?.toolCallId,
        'ask_user_input_v0_12345',
      );

      // Complete via substring ID or conversationId
      service.answer('12345', {
        'q1': const AskUserAnswerValue.single(value: 'Yes', custom: false),
      }, conversationId: 'conv_abc');

      final res = await future;
      expect(service.pendingRequests, isEmpty);
      final payload = jsonDecode(res.toJsonString()) as Map<String, dynamic>;
      expect(payload['answers']['q1']['value'], 'Yes');
    });
  });
}
