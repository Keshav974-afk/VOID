import 'dart:async';
import 'dart:convert';

import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;

/// An individual issue detected during a website inspection.
class SiteIssue {
  const SiteIssue({
    required this.id,
    required this.category,
    required this.severity,
    required this.title,
    required this.description,
    this.selector,
    this.codeSnippet,
    this.fixRecommendation,
  });

  final String id;
  final String
  category; // 'bug' | 'accessibility' | 'security' | 'seo' | 'performance'
  final String severity; // 'critical' | 'warning' | 'info'
  final String title;
  final String description;
  final String? selector;
  final String? codeSnippet;
  final String? fixRecommendation;

  Map<String, dynamic> toJson() => {
    'id': id,
    'category': category,
    'severity': severity,
    'title': title,
    'description': description,
    if (selector != null) 'selector': selector,
    if (codeSnippet != null) 'codeSnippet': codeSnippet,
    if (fixRecommendation != null) 'fixRecommendation': fixRecommendation,
  };

  factory SiteIssue.fromJson(Map<String, dynamic> json) => SiteIssue(
    id: (json['id'] ?? '').toString(),
    category: (json['category'] ?? 'bug').toString(),
    severity: (json['severity'] ?? 'info').toString(),
    title: (json['title'] ?? '').toString(),
    description: (json['description'] ?? '').toString(),
    selector: json['selector'] as String?,
    codeSnippet: json['codeSnippet'] as String?,
    fixRecommendation: json['fixRecommendation'] as String?,
  );
}

/// Aggregated website inspection report.
class SiteInspectToolResult {
  const SiteInspectToolResult({
    required this.status,
    required this.url,
    this.title = '',
    this.statusCode = 200,
    this.healthScore = 100,
    this.grade = 'A',
    this.latencyMs = 0,
    this.issues = const <SiteIssue>[],
    this.metrics = const <String, dynamic>{},
    this.error,
  });

  final String status;
  final String url;
  final String title;
  final int statusCode;
  final int healthScore;
  final String grade;
  final int latencyMs;
  final List<SiteIssue> issues;
  final Map<String, dynamic> metrics;
  final String? error;

  int get criticalCount => issues.where((i) => i.severity == 'critical').length;
  int get warningCount => issues.where((i) => i.severity == 'warning').length;
  int get infoCount => issues.where((i) => i.severity == 'info').length;

  Map<String, dynamic> toJson() => {
    'status': status,
    'url': url,
    'title': title,
    'statusCode': statusCode,
    'healthScore': healthScore,
    'grade': grade,
    'latencyMs': latencyMs,
    'criticalCount': criticalCount,
    'warningCount': warningCount,
    'infoCount': infoCount,
    'issues': issues.map((i) => i.toJson()).toList(),
    'metrics': metrics,
    if (error != null) 'error': error,
  };

  String toJsonString() => jsonEncode(toJson());

  factory SiteInspectToolResult.fromJson(Map<String, dynamic> json) {
    final issuesRaw = json['issues'] as List? ?? const [];
    return SiteInspectToolResult(
      status: (json['status'] ?? 'success').toString(),
      url: (json['url'] ?? '').toString(),
      title: (json['title'] ?? '').toString(),
      statusCode: (json['statusCode'] as num?)?.toInt() ?? 200,
      healthScore: (json['healthScore'] as num?)?.toInt() ?? 100,
      grade: (json['grade'] ?? 'A').toString(),
      latencyMs: (json['latencyMs'] as num?)?.toInt() ?? 0,
      issues: issuesRaw
          .whereType<Map>()
          .map((e) => SiteIssue.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
      metrics: (json['metrics'] as Map?)?.cast<String, dynamic>() ?? const {},
      error: json['error'] as String?,
    );
  }

  static SiteInspectToolResult? tryParse(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      if (!decoded.containsKey('healthScore') || !decoded.containsKey('url')) {
        return null;
      }
      return SiteInspectToolResult.fromJson(Map<String, dynamic>.from(decoded));
    } catch (_) {
      return null;
    }
  }
}

/// Agentic site inspection service that audits live websites for bugs,
/// broken links, accessibility defects, and security flaws.
class SiteInspectionService {
  SiteInspectionService({http.Client? client})
    : _client = client ?? http.Client();

  final http.Client _client;

  static const String _defaultUserAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/133.0.0.0 Safari/537.36 VOID-Agent/1.0';

  Future<SiteInspectToolResult> inspect({
    required String rawUrl,
    bool checkLinks = true,
    bool auditA11y = true,
    bool auditSecurity = true,
    bool auditSeo = true,
    int timeoutMs = 15000,
  }) async {
    String url = rawUrl.trim();
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      url = 'https://$url';
    }

    final parsedUri = Uri.tryParse(url);
    if (parsedUri == null || !parsedUri.hasAuthority) {
      return SiteInspectToolResult(
        status: 'error',
        url: url,
        error: 'Invalid URL format: $rawUrl',
      );
    }

    final stopwatch = Stopwatch()..start();
    http.Response response;
    try {
      response = await _client
          .get(
            parsedUri,
            headers: {
              'User-Agent': _defaultUserAgent,
              'Accept':
                  'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
              'Accept-Language': 'en-US,en;q=0.9',
            },
          )
          .timeout(Duration(milliseconds: timeoutMs));
    } catch (e) {
      stopwatch.stop();
      return SiteInspectToolResult(
        status: 'error',
        url: url,
        latencyMs: stopwatch.elapsedMilliseconds,
        error: 'Failed to connect to $url: $e',
      );
    }
    stopwatch.stop();
    final latency = stopwatch.elapsedMilliseconds;

    final issues = <SiteIssue>[];
    int score = 100;

    // 1. HTTP Status & Connection Audit
    if (response.statusCode >= 400) {
      issues.add(
        SiteIssue(
          id: 'http_error',
          category: 'bug',
          severity: 'critical',
          title: 'HTTP ${response.statusCode} Error',
          description:
              'Server returned error status ${response.statusCode} for requested URL.',
          fixRecommendation:
              'Verify the route endpoint exists and server configuration permits access.',
        ),
      );
      score -= 30;
    }

    // 2. Security Headers Audit
    if (auditSecurity) {
      final headers = response.headers;
      final isHttps = parsedUri.scheme == 'https';

      if (!isHttps) {
        issues.add(
          const SiteIssue(
            id: 'insecure_http',
            category: 'security',
            severity: 'critical',
            title: 'Unencrypted HTTP Connection',
            description:
                'The site transmits unencrypted traffic over HTTP instead of HTTPS.',
            fixRecommendation:
                'Deploy an SSL/TLS certificate and enforce HSTS 301 redirects to https://.',
          ),
        );
        score -= 20;
      }

      if (isHttps && !headers.containsKey('strict-transport-security')) {
        issues.add(
          const SiteIssue(
            id: 'missing_hsts',
            category: 'security',
            severity: 'warning',
            title: 'Missing HSTS Header',
            description:
                'Strict-Transport-Security header is missing, allowing potential SSL strip attacks.',
            fixRecommendation:
                'Add Strict-Transport-Security: max-age=31536000; includeSubDomains header.',
          ),
        );
        score -= 5;
      }

      if (!headers.containsKey('content-security-policy')) {
        issues.add(
          const SiteIssue(
            id: 'missing_csp',
            category: 'security',
            severity: 'info',
            title: 'No Content-Security-Policy (CSP)',
            description:
                'A Content-Security-Policy header helps mitigate XSS and unauthorized data injection.',
            fixRecommendation:
                'Configure a Content-Security-Policy header restricting trusted script sources.',
          ),
        );
        score -= 3;
      }

      if (!headers.containsKey('x-frame-options') &&
          !(headers['content-security-policy']?.contains('frame-ancestors') ??
              false)) {
        issues.add(
          const SiteIssue(
            id: 'clickjacking_risk',
            category: 'security',
            severity: 'warning',
            title: 'Potential Clickjacking Vulnerability',
            description:
                'Missing X-Frame-Options or CSP frame-ancestors header allows embedding in malicious iframes.',
            fixRecommendation: 'Add X-Frame-Options: DENY or SAMEORIGIN.',
          ),
        );
        score -= 5;
      }
    }

    // Parse HTML DOM
    dom.Document doc;
    try {
      doc = html_parser.parse(response.body);
    } catch (e) {
      return SiteInspectToolResult(
        status: 'partial',
        url: url,
        statusCode: response.statusCode,
        latencyMs: latency,
        healthScore: score.clamp(0, 100),
        grade: _calculateGrade(score),
        issues: issues,
        error: 'Failed to parse HTML document: $e',
      );
    }

    final pageTitle = doc.querySelector('title')?.text.trim() ?? '';
    final metaViewport = doc.querySelector('meta[name="viewport"]');
    final metaDescription = doc.querySelector('meta[name="description"]');

    // 3. SEO & Document Structure
    if (auditSeo) {
      if (pageTitle.isEmpty) {
        issues.add(
          const SiteIssue(
            id: 'missing_title',
            category: 'seo',
            severity: 'critical',
            title: 'Missing Page Title',
            description:
                'Document does not have a `<title>` tag, severely damaging search indexing and browser tabs.',
            fixRecommendation: 'Add a descriptive `<title>` tag in `<head>`.',
          ),
        );
        score -= 10;
      }

      if (metaViewport == null) {
        issues.add(
          const SiteIssue(
            id: 'missing_viewport',
            category: 'bug',
            severity: 'critical',
            title: 'Missing Responsive Viewport Meta Tag',
            description:
                'Page lacks `<meta name="viewport" content="width=device-width, initial-scale=1">`, breaking mobile scaling.',
            fixRecommendation:
                'Insert `<meta name="viewport" content="width=device-width, initial-scale=1">` into `<head>`.',
          ),
        );
        score -= 15;
      }

      if (metaDescription == null ||
          (metaDescription.attributes['content']?.trim().isEmpty ?? true)) {
        issues.add(
          const SiteIssue(
            id: 'missing_meta_desc',
            category: 'seo',
            severity: 'info',
            title: 'Missing Meta Description',
            description:
                'Search engines use meta description for snippets in search results.',
            fixRecommendation:
                'Add `<meta name="description" content="...">` with 50-160 characters summary.',
          ),
        );
        score -= 3;
      }
    }

    // 4. Accessibility (a11y) & DOM Integrity
    final images = doc.querySelectorAll('img');
    final imagesWithoutAlt = <String>[];
    final brokenImages = <String>[];

    for (final img in images) {
      final src = img.attributes['src']?.trim() ?? '';
      final alt = img.attributes['alt'];
      if (src.isEmpty) {
        brokenImages.add(
          img.outerHtml.length > 80
              ? '${img.outerHtml.substring(0, 80)}...'
              : img.outerHtml,
        );
      }
      if (alt == null || alt.trim().isEmpty) {
        imagesWithoutAlt.add(src.isNotEmpty ? src : img.outerHtml);
      }
    }

    if (imagesWithoutAlt.isNotEmpty && auditA11y) {
      issues.add(
        SiteIssue(
          id: 'images_missing_alt',
          category: 'accessibility',
          severity: 'warning',
          title: '${imagesWithoutAlt.length} Images Missing Alt Text',
          description:
              'Images without `alt` text cannot be described by screen readers for visually impaired users.',
          codeSnippet: imagesWithoutAlt.take(3).join('\n'),
          fixRecommendation:
              'Add descriptive `alt="..."` attributes to all informative images, or `alt=""` for decorative ones.',
        ),
      );
      score -= (imagesWithoutAlt.length * 2).clamp(2, 12);
    }

    if (brokenImages.isNotEmpty) {
      issues.add(
        SiteIssue(
          id: 'empty_image_src',
          category: 'bug',
          severity: 'critical',
          title: '${brokenImages.length} Image Tags With Empty src',
          description:
              'Detected `<img>` elements with missing or empty source paths causing broken render frames.',
          codeSnippet: brokenImages.take(3).join('\n'),
          fixRecommendation:
              'Provide a valid image URI or remove the empty `<img>` tags.',
        ),
      );
      score -= 10;
    }

    // 5. Button and Form Input Accessibility
    if (auditA11y) {
      final buttons = doc.querySelectorAll('button, a[role="button"]');
      final emptyButtons = <String>[];
      for (final btn in buttons) {
        final text = btn.text.trim();
        final aria = btn.attributes['aria-label']?.trim() ?? '';
        final hasIconOrImg = btn.querySelector('svg, img, i') != null;
        if (text.isEmpty && aria.isEmpty && !hasIconOrImg) {
          emptyButtons.add(
            btn.outerHtml.length > 80
                ? '${btn.outerHtml.substring(0, 80)}...'
                : btn.outerHtml,
          );
        }
      }
      if (emptyButtons.isNotEmpty) {
        issues.add(
          SiteIssue(
            id: 'empty_buttons',
            category: 'accessibility',
            severity: 'warning',
            title: '${emptyButtons.length} Buttons Lack Accessible Name',
            description:
                'Buttons without inner text or `aria-label` are unusable for screen reader users.',
            codeSnippet: emptyButtons.take(3).join('\n'),
            fixRecommendation:
                'Provide an `aria-label="..."` or visible text content for all interactive buttons.',
          ),
        );
        score -= 8;
      }

      final inputs = doc.querySelectorAll(
        'input:not([type="hidden"]), select, textarea',
      );
      final unlabelledInputs = <String>[];
      for (final inp in inputs) {
        final id = inp.attributes['id'];
        final aria =
            inp.attributes['aria-label'] ?? inp.attributes['aria-labelledby'];
        final hasLabel =
            id != null && doc.querySelector('label[for="$id"]') != null;
        final hasWrappingLabel = inp.parent?.localName == 'label';
        if (!hasLabel &&
            !hasWrappingLabel &&
            (aria == null || aria.trim().isEmpty)) {
          unlabelledInputs.add(
            inp.outerHtml.length > 80
                ? '${inp.outerHtml.substring(0, 80)}...'
                : inp.outerHtml,
          );
        }
      }
      if (unlabelledInputs.isNotEmpty) {
        issues.add(
          SiteIssue(
            id: 'unlabelled_form_inputs',
            category: 'accessibility',
            severity: 'warning',
            title: '${unlabelledInputs.length} Form Controls Without Labels',
            description:
                'Form fields without associated `<label>` or `aria-label` cannot be identified by assistive tech.',
            codeSnippet: unlabelledInputs.take(3).join('\n'),
            fixRecommendation:
                'Associate each input with a `<label for="...">` or provide `aria-label="..."`.',
          ),
        );
        score -= 8;
      }
    }

    // 6. Heading Hierarchy & Duplicate IDs
    final h1s = doc.querySelectorAll('h1');
    if (h1s.isEmpty) {
      issues.add(
        const SiteIssue(
          id: 'missing_h1',
          category: 'seo',
          severity: 'warning',
          title: 'Missing Main <h1> Heading',
          description:
              'Document lacks a top-level `<h1>` heading to establish semantic page topic.',
          fixRecommendation:
              'Introduce a single descriptive `<h1>` representing the page title or primary action.',
        ),
      );
      score -= 5;
    } else if (h1s.length > 1) {
      issues.add(
        SiteIssue(
          id: 'multiple_h1',
          category: 'seo',
          severity: 'info',
          title: 'Multiple <h1> Headings Found (${h1s.length})',
          description:
              'Best practice recommends a single primary `<h1>` per page for clear heading structure.',
          fixRecommendation:
              'Consolidate page structure to one `<h1>` and downgrade secondary sections to `<h2>`.',
        ),
      );
      score -= 2;
    }

    final idElements = doc.querySelectorAll('[id]');
    final seenIds = <String>{};
    final duplicateIds = <String>{};
    for (final el in idElements) {
      final id = el.attributes['id']?.trim() ?? '';
      if (id.isNotEmpty) {
        if (!seenIds.add(id)) {
          duplicateIds.add(id);
        }
      }
    }
    if (duplicateIds.isNotEmpty) {
      issues.add(
        SiteIssue(
          id: 'duplicate_ids',
          category: 'bug',
          severity: 'critical',
          title: '${duplicateIds.length} Duplicate HTML IDs Detected',
          description:
              'HTML IDs must be unique across the document. Duplicates cause broken anchor navigation and JS bugs.',
          codeSnippet: duplicateIds.take(5).map((id) => 'id="$id"').join(', '),
          fixRecommendation:
              'Ensure every HTML element id attribute is globally unique on the page.',
        ),
      );
      score -= 10;
    }

    // 7. Broken Links & External Security
    final links = doc.querySelectorAll('a[href]');
    final unsafeBlankLinks = <String>[];
    final deadAnchors = <String>[];

    for (final link in links) {
      final href = link.attributes['href']?.trim() ?? '';
      final target = link.attributes['target']?.trim();
      final rel = link.attributes['rel']?.toLowerCase() ?? '';

      if (target == '_blank' &&
          !rel.contains('noopener') &&
          !rel.contains('noreferrer')) {
        unsafeBlankLinks.add(href);
      }
      if (href == '#' ||
          href == 'javascript:void(0)' ||
          href == 'javascript:;') {
        deadAnchors.add(
          link.text.trim().isNotEmpty ? link.text.trim() : link.outerHtml,
        );
      }
    }

    if (unsafeBlankLinks.isNotEmpty && auditSecurity) {
      issues.add(
        SiteIssue(
          id: 'reverse_tabnabbing',
          category: 'security',
          severity: 'warning',
          title:
              '${unsafeBlankLinks.length} target="_blank" Links Missing rel="noopener"',
          description:
              'Opening new tabs without `rel="noopener"` exposes the window to reverse tabnabbing attacks.',
          codeSnippet: unsafeBlankLinks.take(3).join('\n'),
          fixRecommendation:
              'Add `rel="noopener noreferrer"` to all outbound links with `target="_blank"`.',
        ),
      );
      score -= 5;
    }

    if (deadAnchors.isNotEmpty) {
      issues.add(
        SiteIssue(
          id: 'dead_anchor_links',
          category: 'bug',
          severity: 'info',
          title: '${deadAnchors.length} Placeholder/Dead Anchor Links',
          description:
              'Detected `<a>` tags with `href="#"` or `javascript:void(0)` instead of semantic buttons or valid URLs.',
          codeSnippet: deadAnchors.take(3).join(', '),
          fixRecommendation:
              'Replace dead anchor links with `<button>` for script actions or real routes.',
        ),
      );
      score -= 3;
    }

    final finalScore = score.clamp(0, 100);
    final grade = _calculateGrade(finalScore);

    final metrics = <String, dynamic>{
      'totalDomElements': doc.querySelectorAll('*').length,
      'imagesCount': images.length,
      'linksCount': links.length,
      'scriptsCount': doc.querySelectorAll('script').length,
      'stylesheetsCount': doc.querySelectorAll('link[rel="stylesheet"]').length,
      'formsCount': doc.querySelectorAll('form').length,
      'hasViewport': metaViewport != null,
      'htmlLengthBytes': response.bodyBytes.length,
    };

    return SiteInspectToolResult(
      status: 'success',
      url: url,
      title: pageTitle,
      statusCode: response.statusCode,
      healthScore: finalScore,
      grade: grade,
      latencyMs: latency,
      issues: issues,
      metrics: metrics,
    );
  }

  static String _calculateGrade(int score) {
    if (score >= 95) return 'A+';
    if (score >= 90) return 'A';
    if (score >= 80) return 'B';
    if (score >= 70) return 'C';
    if (score >= 60) return 'D';
    return 'F';
  }
}
