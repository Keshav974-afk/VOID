import 'dart:io';

import 'package:Kelivo/core/services/document/document_tool_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('kelivo_doc_tool_test_');
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  test('create_pdf generates a valid multi-section styled PDF file', () async {
    final outPath = p.join(tempDir.path, 'executive_report.pdf');
    final raw = await DocumentToolService.execute({
      'action': 'create_pdf',
      'title': 'Q4 Executive Performance Report',
      'subtitle': 'Prepared by Kelivo Analytics • 2026',
      'theme': 'emerald',
      'output_path': outPath,
      'content': '''
# 1. Executive Summary
Revenue grew by **34% YoY** across all regions.

> Key Takeaway: Enterprise adoption exceeded targets by 18%.

## 2. Regional Breakdown
| Region | Q3 Revenue | Q4 Revenue | Growth |
| --- | --- | --- | --- |
| North America | \$4.2M | \$5.8M | +38% |
| Europe | \$2.9M | \$3.7M | +27% |
| APAC | \$1.8M | \$2.5M | +39% |

### Action Items
- Expand enterprise sales team in APAC
- Launch v2.0 self-serve onboarding
''',
    });

    final result = DocumentToolResult.tryParse(raw);
    expect(result, isNotNull);
    expect(result!.status, 'success');
    expect(result.outputPath, outPath);
    expect(result.pageCount, greaterThanOrEqualTo(1));
    expect(File(outPath).existsSync(), isTrue);
    expect(File(outPath).lengthSync(), greaterThan(500));
  });

  test(
    'create_docx generates a valid Word (.docx) file and extracts text back',
    () async {
      final outPath = p.join(tempDir.path, 'proposal.docx');
      final raw = await DocumentToolService.execute({
        'action': 'create_docx',
        'title': 'Project Architecture Specification',
        'subtitle': 'Version 1.0',
        'output_path': outPath,
        'content': '''
# Overview
This document outlines the cross-platform architecture.

## Milestones
| Milestone | Owner | Status |
| --- | --- | --- |
| Core Engine | Alice | Complete |
| UI Polish | Bob | In Progress |

- Zero hardcoded secrets
- Full offline support
''',
      });

      final result = DocumentToolResult.tryParse(raw);
      expect(result, isNotNull);
      expect(result!.status, 'success');
      expect(File(outPath).existsSync(), isTrue);

      final extractedRaw = await DocumentToolService.execute({
        'action': 'extract_text',
        'file_path': outPath,
      });
      final extracted = DocumentToolResult.tryParse(extractedRaw);
      expect(extracted, isNotNull);
      expect(extracted!.status, 'success');
      expect(extracted.text, contains('Project Architecture Specification'));
      expect(extracted.text, contains('Core Engine'));
      expect(extracted.text, contains('Zero hardcoded secrets'));
    },
  );

  test(
    'create_xlsx generates a valid Excel (.xlsx) workbook and extracts table back',
    () async {
      final outPath = p.join(tempDir.path, 'budget.xlsx');
      final raw = await DocumentToolService.execute({
        'action': 'create_xlsx',
        'title': 'Annual Budget',
        'output_path': outPath,
        'headers': ['Department', 'Allocated', 'Spent'],
        'rows': [
          ['Engineering', 500000, 480000],
          ['Design', 150000, 142000],
          ['Marketing', 200000, 195000],
        ],
      });

      final result = DocumentToolResult.tryParse(raw);
      expect(result, isNotNull);
      expect(result!.status, 'success');
      expect(File(outPath).existsSync(), isTrue);

      final extractedRaw = await DocumentToolService.execute({
        'action': 'extract_text',
        'file_path': outPath,
      });
      final extracted = DocumentToolResult.tryParse(extractedRaw);
      expect(extracted, isNotNull);
      expect(extracted!.status, 'success');
      expect(extracted.text, contains('Department'));
      expect(extracted.text, contains('Engineering'));
      expect(extracted.text, contains('500000'));
    },
  );

  test(
    'create_pptx generates a valid PowerPoint (.pptx) presentation and extracts slides',
    () async {
      final outPath = p.join(tempDir.path, 'pitch_deck.pptx');
      final raw = await DocumentToolService.execute({
        'action': 'create_pptx',
        'title': 'Kelivo AI Next-Gen Launch',
        'output_path': outPath,
        'slides': [
          {
            'title': 'Kelivo AI Next-Gen Launch',
            'bullets': [
              'Universal Cross-Platform Assistant',
              'Desktop & Mobile Control',
            ],
          },
          {
            'title': 'Document Studio',
            'bullets': ['Attractive PDFs', 'Native Word, Excel & PowerPoint'],
          },
        ],
      });

      final result = DocumentToolResult.tryParse(raw);
      expect(result, isNotNull);
      expect(result!.status, 'success');
      expect(result.pageCount, 2);
      expect(File(outPath).existsSync(), isTrue);

      final extractedRaw = await DocumentToolService.execute({
        'action': 'extract_text',
        'file_path': outPath,
      });
      final extracted = DocumentToolResult.tryParse(extractedRaw);
      expect(extracted, isNotNull);
      expect(extracted!.status, 'success');
      expect(extracted.text, contains('Slide 1'));
      expect(extracted.text, contains('Universal Cross-Platform Assistant'));
      expect(extracted.text, contains('Slide 2'));
      expect(extracted.text, contains('Native Word, Excel & PowerPoint'));
    },
  );
}
