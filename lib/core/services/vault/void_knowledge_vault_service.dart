import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class VaultDocument {
  const VaultDocument({
    required this.id,
    required this.title,
    required this.content,
    required this.sourcePath,
    required this.addedAt,
    this.tags = const [],
  });

  final String id;
  final String title;
  final String content;
  final String? sourcePath;
  final DateTime addedAt;
  final List<String> tags;

  int get wordCount =>
      content.trim().isEmpty ? 0 : content.trim().split(RegExp(r'\s+')).length;

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'content': content,
    'sourcePath': sourcePath,
    'addedAt': addedAt.toIso8601String(),
    'tags': tags,
  };

  factory VaultDocument.fromJson(Map<String, dynamic> json) {
    return VaultDocument(
      id: (json['id'] ?? '').toString(),
      title: (json['title'] ?? 'Untitled').toString(),
      content: (json['content'] ?? '').toString(),
      sourcePath: json['sourcePath']?.toString(),
      addedAt:
          DateTime.tryParse((json['addedAt'] ?? '').toString()) ??
          DateTime.now(),
      tags:
          (json['tags'] as List?)?.map((e) => e.toString()).toList() ??
          const [],
    );
  }
}

class VaultChunkHit {
  const VaultChunkHit({
    required this.document,
    required this.excerpt,
    required this.score,
  });

  final VaultDocument document;
  final String excerpt;
  final double score;
}

/// Local Knowledge Vault (Private On-Device RAG).
/// Indexes user documents and notes locally and retrieves relevant passages
/// with BM25-style lexical + phrase scoring.
class VoidKnowledgeVaultService extends ChangeNotifier {
  VoidKnowledgeVaultService._();
  static final VoidKnowledgeVaultService instance =
      VoidKnowledgeVaultService._();

  static const String _prefsDocsKey = 'void_knowledge_vault_docs_v1';
  static const String _prefsEnabledKey = 'void_knowledge_vault_enabled_v1';

  List<VaultDocument> _documents = [];
  bool _autoInjectInChat = false;
  bool _loaded = false;

  List<VaultDocument> get documents => List.unmodifiable(_documents);
  bool get autoInjectInChat => _autoInjectInChat;

  Future<void> ensureLoaded() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    _autoInjectInChat = prefs.getBool(_prefsEnabledKey) ?? false;
    final raw = prefs.getString(_prefsDocsKey);
    if (raw != null && raw.isNotEmpty) {
      try {
        final list = jsonDecode(raw) as List;
        _documents = list
            .whereType<Map>()
            .map((m) => VaultDocument.fromJson(Map<String, dynamic>.from(m)))
            .toList();
      } catch (_) {
        _documents = [];
      }
    }
    _loaded = true;
    notifyListeners();
  }

  Future<void> setAutoInjectInChat(bool enabled) async {
    await ensureLoaded();
    _autoInjectInChat = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsEnabledKey, enabled);
    notifyListeners();
  }

  Future<VaultDocument> addNote({
    required String title,
    required String content,
    String? sourcePath,
    List<String> tags = const [],
  }) async {
    await ensureLoaded();
    final doc = VaultDocument(
      id: 'doc_${DateTime.now().microsecondsSinceEpoch}',
      title: title.trim().isEmpty ? 'Untitled Document' : title.trim(),
      content: content,
      sourcePath: sourcePath,
      addedAt: DateTime.now(),
      tags: tags,
    );
    _documents = [doc, ..._documents];
    await _persist();
    notifyListeners();
    return doc;
  }

  Future<VaultDocument?> importFile(File file) async {
    try {
      final bytes = await file.readAsBytes();
      final text = utf8.decode(bytes, allowMalformed: true);
      if (text.trim().isEmpty) return null;
      final name = file.uri.pathSegments.isNotEmpty
          ? file.uri.pathSegments.last
          : file.path.split(RegExp(r'[/\\]')).last;
      return await addNote(
        title: name,
        content: text.length > 150000 ? text.substring(0, 150000) : text,
        sourcePath: file.path,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> removeDocument(String id) async {
    await ensureLoaded();
    _documents = _documents.where((d) => d.id != id).toList();
    await _persist();
    notifyListeners();
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _prefsDocsKey,
      jsonEncode(_documents.map((d) => d.toJson()).toList()),
    );
  }

  /// Searches all indexed vault documents and returns the top matching chunks.
  List<VaultChunkHit> query(String rawQuery, {int topK = 4}) {
    if (_documents.isEmpty) return const [];
    final terms = _tokenize(rawQuery);
    final hits = <VaultChunkHit>[];

    for (final doc in _documents) {
      final chunks = _splitIntoChunks(doc.content, maxChars: 650);
      for (final chunk in chunks) {
        if (terms.isEmpty) {
          hits.add(VaultChunkHit(document: doc, excerpt: chunk, score: 1.0));
          continue;
        }
        final lowerChunk = chunk.toLowerCase();
        final lowerTitle = doc.title.toLowerCase();
        double score = 0.0;
        for (final term in terms) {
          if (lowerTitle.contains(term)) {
            score += 3.0;
          }
          var idx = 0;
          var count = 0;
          while (true) {
            final found = lowerChunk.indexOf(term, idx);
            if (found < 0) break;
            count++;
            idx = found + term.length;
          }
          if (count > 0) {
            score += 1.0 + math.log(count + 1);
          }
        }
        if (score > 0) {
          hits.add(VaultChunkHit(document: doc, excerpt: chunk, score: score));
        }
      }
    }

    hits.sort((a, b) => b.score.compareTo(a.score));
    if (hits.isEmpty && _documents.isNotEmpty) {
      // Fallback to most recent document excerpts when query has no exact lexical overlap
      for (final doc in _documents.take(2)) {
        final chunks = _splitIntoChunks(doc.content, maxChars: 550);
        if (chunks.isNotEmpty) {
          hits.add(
            VaultChunkHit(document: doc, excerpt: chunks.first, score: 0.5),
          );
        }
      }
    }
    return hits.take(topK).toList();
  }

  /// Formats retrieved chunks as a grounded RAG context block for the LLM.
  String buildContextPrompt(String userQuery, {int topK = 4}) {
    final hits = query(userQuery, topK: topK);
    if (hits.isEmpty) return '';
    final buffer = StringBuffer()
      ..writeln('<void_knowledge_vault_context>')
      ..writeln(
        'The following excerpts were retrieved from the user\'s Local Knowledge Vault. Cite the document title when using this information:',
      );
    for (var i = 0; i < hits.length; i++) {
      final hit = hits[i];
      buffer
        ..writeln('\n[Source ${i + 1}: ${hit.document.title}]')
        ..writeln(hit.excerpt.trim());
    }
    buffer.writeln('</void_knowledge_vault_context>\n');
    return buffer.toString();
  }

  List<String> _tokenize(String input) {
    return input
        .toLowerCase()
        .split(RegExp(r'[^a-z0-9\u00C0-\u024F\u4E00-\u9FFF]+'))
        .where((t) => t.length >= 2)
        .toSet()
        .toList();
  }

  List<String> _splitIntoChunks(String text, {int maxChars = 650}) {
    final normalized = text.replaceAll('\r\n', '\n').trim();
    if (normalized.isEmpty) return const [];
    if (normalized.length <= maxChars) return [normalized];

    final paragraphs = normalized.split(RegExp(r'\n\s*\n'));
    final chunks = <String>[];
    final current = StringBuffer();

    for (final para in paragraphs) {
      final clean = para.trim();
      if (clean.isEmpty) continue;
      if (current.length + clean.length + 2 <= maxChars) {
        if (current.isNotEmpty) current.write('\n\n');
        current.write(clean);
      } else {
        if (current.isNotEmpty) {
          chunks.add(current.toString());
          current.clear();
        }
        if (clean.length <= maxChars) {
          current.write(clean);
        } else {
          for (var i = 0; i < clean.length; i += maxChars) {
            chunks.add(
              clean.substring(i, math.min(i + maxChars, clean.length)),
            );
          }
        }
      }
    }
    if (current.isNotEmpty) {
      chunks.add(current.toString());
    }
    return chunks;
  }
}
