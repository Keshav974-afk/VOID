import 'package:flutter/widgets.dart';
import 'package:flutter_math_fork/ast.dart'
    show EquationArrayNode, GreenNode, TransparentNode;
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_math_fork/tex.dart';
import 'package:markstream/markstream.dart';
import 'package:Kelivo/theme/theme_factory.dart' show getPlatformFontFallback;

/// The parser retains original LaTeX; repairs belong only to its visual adapter.
class KelivoMathRenderer implements MathRenderer {
  const KelivoMathRenderer();

  @override
  Widget build(
    BuildContext context,
    String tex, {
    required TextStyle style,
    required bool displayMode,
  }) => _ParsedMath(
    tex: tex,
    displayMode: displayMode,
    builder: (context, renderer) =>
        renderer.build(context, tex, style: style, displayMode: displayMode),
  );
}

/// A fenced formula keeps its source-code UI when parsing fails.
class KelivoMathBlock extends StatelessWidget {
  const KelivoMathBlock({
    super.key,
    required this.node,
    required this.theme,
    required this.fallback,
  });

  final CodeBlockNode node;
  final MarkstreamTheme theme;
  final Widget fallback;

  @override
  Widget build(BuildContext context) => _ParsedMath(
    tex: node.code,
    displayMode: true,
    builder: (context, renderer) => renderer.ast == null
        ? fallback
        : MarkstreamMathBlock(
            node: node,
            tex: node.code,
            theme: theme,
            renderer: renderer,
          ),
  );
}

class FullWidthMath extends StatelessWidget implements FullWidthMathWidget {
  const FullWidthMath({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}

bool _usesFullWidthEquationLayout(Widget math) {
  if (math is! Math) return false;
  final root = math.ast?.greenRoot;
  if (root == null) return false;

  final flattened = <GreenNode>[];
  void collect(GreenNode node) {
    if (node is TransparentNode) {
      for (final child in node.children) {
        collect(child);
      }
    } else {
      flattened.add(node);
    }
  }

  for (final child in root.children) {
    collect(child);
    if (flattened.length > 1) return false;
  }
  final child = flattened.length == 1 ? flattened.single : null;
  return child is EquationArrayNode && child.displayLayout;
}

class _ParsedMath extends StatefulWidget {
  const _ParsedMath({
    required this.tex,
    this.displayMode = false,
    required this.builder,
  });

  final String tex;
  final bool displayMode;
  final Widget Function(BuildContext, _ParsedMathRenderer) builder;

  @override
  State<_ParsedMath> createState() => _ParsedMathState();
}

class _ParsedMathState extends State<_ParsedMath> {
  // flutter_math_fork trees retain widgets and GlobalKeys, so each mounted
  // formula must own its tree. Keep only its current parse until unmounted.
  late _ParsedMathRenderer _renderer;

  @override
  void initState() {
    super.initState();
    _parse();
  }

  @override
  void didUpdateWidget(_ParsedMath oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tex != widget.tex ||
        oldWidget.displayMode != widget.displayMode) {
      _parse();
    }
  }

  void _parse() {
    final normalized = normalizeMathTex(widget.tex);
    SyntaxTree? ast;
    try {
      ast = SyntaxTree(
        greenRoot: TexParser(
          normalized,
          TexParserSettings(
            displayMode: widget.displayMode,
            strict: Strict.ignore,
          ),
        ).parse(),
      );
    } catch (_) {
      // Preserve malformed input; changed streaming text gets a fresh parse.
    }
    _renderer = _ParsedMathRenderer(normalized, ast);
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _renderer);
}

class _ParsedMathRenderer implements MathRenderer {
  const _ParsedMathRenderer(this.normalized, this.ast);

  final String normalized;
  final SyntaxTree? ast;

  @override
  Widget build(
    BuildContext context,
    String tex, {
    required TextStyle style,
    required bool displayMode,
  }) {
    final effectiveStyle = style.copyWith(
      fontFamilyFallback: style.fontFamilyFallback ?? getPlatformFontFallback(),
    );
    if (ast == null) {
      return Text(normalized, style: effectiveStyle);
    }
    final mathWidget = Math(
      ast: ast,
      mathStyle: displayMode ? MathStyle.display : MathStyle.text,
      textStyle: effectiveStyle,
      onErrorFallback: (_) => Text(normalized, style: effectiveStyle),
    );
    if (displayMode && _usesFullWidthEquationLayout(mathWidget)) {
      return FullWidthMath(child: mathWidget);
    }
    return mathWidget;
  }
}

String normalizeMathTex(String tex) {
  final escapedSpecials = _escapeInlineMathSpecials(tex);
  final normalizedBraces = _escapeLikelyLiteralMathBraces(escapedSpecials);
  return normalizedBraces.replaceAllMapped(RegExp(r'\\\|([\s\S]*?)\\\|'), (
    match,
  ) {
    final body = match.group(1) ?? '';
    return r'\lVert '
        '$body'
        r' \rVert';
  });
}

String _escapeInlineMathSpecials(String tex) {
  final buf = StringBuffer();
  for (var i = 0; i < tex.length; i++) {
    final ch = tex.codeUnitAt(i);
    if (ch == 0x23 &&
        !_isEscaped(tex, i) &&
        !_isTexColorHexArgumentPrefix(tex, i)) {
      buf.write(r'\#');
    } else {
      buf.writeCharCode(ch);
    }
  }
  return buf.toString();
}

bool _isTexColorHexArgumentPrefix(String tex, int index) {
  final open = _findContainingBraceOpen(tex, index);
  if (open == -1) return false;

  final close = _findMatchingCloseBrace(tex, open);
  if (close == -1 || index >= close) return false;
  if (!_isExactHexColorArgument(tex, open, index, close)) return false;

  return _isTexColorArgumentGroup(tex, open);
}

bool _isExactHexColorArgument(String tex, int open, int hash, int close) {
  if (hash != open + 1) return false;
  final hexDigits = close - hash - 1;
  if (hexDigits != 3 && hexDigits != 6) return false;

  for (var i = hash + 1; i < close; i++) {
    if (!_isAsciiHexDigit(tex.codeUnitAt(i))) return false;
  }
  return true;
}

bool _isAsciiHexDigit(int codeUnit) {
  return _isAsciiDigit(codeUnit) ||
      (codeUnit >= 0x41 && codeUnit <= 0x46) ||
      (codeUnit >= 0x61 && codeUnit <= 0x66);
}

int _findContainingBraceOpen(String tex, int index) {
  final stack = <int>[];

  for (var i = 0; i < index; i++) {
    final ch = tex.codeUnitAt(i);
    if (ch == 0x5C) {
      i++;
      continue;
    }
    if (ch == 0x7B) {
      stack.add(i);
    } else if (ch == 0x7D && stack.isNotEmpty) {
      stack.removeLast();
    }
  }

  return stack.isEmpty ? -1 : stack.last;
}

int _findMatchingCloseBrace(String tex, int open) {
  var depth = 0;
  for (var i = open; i < tex.length; i++) {
    final ch = tex.codeUnitAt(i);
    if (ch == 0x5C) {
      i++;
      continue;
    }
    if (ch == 0x7B) {
      depth++;
    } else if (ch == 0x7D) {
      depth--;
      if (depth == 0) return i;
    }
  }
  return -1;
}

int _findMatchingOpenBrace(String tex, int close) {
  var depth = 0;
  for (var i = close; i >= 0; i--) {
    final ch = tex.codeUnitAt(i);
    if (_isEscaped(tex, i)) continue;
    if (ch == 0x7D) {
      depth++;
    } else if (ch == 0x7B) {
      depth--;
      if (depth == 0) return i;
    }
  }
  return -1;
}

String? _controlWordEndingAt(String tex, int index) {
  if (index < 0 ||
      index >= tex.length ||
      !_isAsciiLetter(tex.codeUnitAt(index))) {
    return null;
  }

  var start = index;
  while (start >= 0 && _isAsciiLetter(tex.codeUnitAt(start))) {
    start--;
  }
  if (start < 0 || tex.codeUnitAt(start) != 0x5C) return null;
  return tex.substring(start, index + 1);
}

bool _isTexColorArgumentGroup(String tex, int open) {
  var argOpen = open;
  var argumentIndex = 0;

  while (true) {
    var prev = _previousNonWhitespaceIndex(tex, argOpen - 1);
    if (prev == -1) return false;

    if (tex.codeUnitAt(prev) == 0x5D) {
      final optionalOpen = _findMatchingOpenBracket(tex, prev);
      if (optionalOpen == -1) return false;
      prev = _previousNonWhitespaceIndex(tex, optionalOpen - 1);
      if (prev == -1) return false;
    }

    if (tex.codeUnitAt(prev) == 0x7D && !_isEscaped(tex, prev)) {
      final previousArgOpen = _findMatchingOpenBrace(tex, prev);
      if (previousArgOpen == -1) return false;
      argumentIndex++;
      argOpen = previousArgOpen;
      continue;
    }

    final command = _controlWordEndingAt(tex, prev);
    if (command == null) return false;
    return _isTexColorCommandArgument(command, argumentIndex);
  }
}

bool _isTexColorCommandArgument(String command, int argumentIndex) {
  switch (command) {
    case r'\color':
    case r'\textcolor':
    case r'\colorbox':
      return argumentIndex == 0;
    case r'\fcolorbox':
      return argumentIndex == 0 || argumentIndex == 1;
  }
  return false;
}

String _escapeLikelyLiteralMathBraces(String tex) {
  final escapeOpens = <int>{};
  final escapeCloses = <int>{};
  final stack = <int>[];

  for (var i = 0; i < tex.length; i++) {
    final ch = tex.codeUnitAt(i);
    if (ch == 0x5C) {
      i++;
      continue;
    }
    if (ch == 0x7B) {
      stack.add(i);
      continue;
    }
    if (ch != 0x7D || stack.isEmpty) continue;

    final open = stack.removeLast();
    if (stack.isNotEmpty) continue;
    if (_looksLikeLiteralMathBraceGroup(tex, open, i)) {
      escapeOpens.add(open);
      escapeCloses.add(i);
    }
  }

  if (escapeOpens.isEmpty) return tex;
  final buf = StringBuffer();
  for (var i = 0; i < tex.length; i++) {
    if (escapeOpens.contains(i)) {
      buf.write(r'\{');
    } else if (escapeCloses.contains(i)) {
      buf.write(r'\}');
    } else {
      buf.writeCharCode(tex.codeUnitAt(i));
    }
  }
  return buf.toString();
}

bool _looksLikeLiteralMathBraceGroup(String tex, int open, int close) {
  if (_isCommandArgumentBrace(tex, open) || _isScriptArgumentBrace(tex, open)) {
    return false;
  }
  if (!_hasLiteralBraceBoundaryBefore(tex, open)) return false;

  final body = tex.substring(open + 1, close).trim();
  if (body.isEmpty) return true;
  if (body.startsWith(r'\')) return false;
  if (_nextNonWhitespaceCodeUnit(tex, close + 1) == 0x5F &&
      body.contains('_')) {
    return true;
  }
  return body.contains(',') ||
      body.contains(':') ||
      body.contains(';') ||
      body.contains(r'\in') ||
      body.contains(r'\notin') ||
      body.contains(r'\mid') ||
      body.contains('|');
}

bool _isCommandArgumentBrace(String tex, int open) {
  final prev = _previousNonWhitespaceIndex(tex, open - 1);
  if (prev == -1) return false;

  if (tex.codeUnitAt(prev) == 0x2A &&
      _endsControlWordAt(tex, _previousNonWhitespaceIndex(tex, prev - 1))) {
    return true;
  }

  if (tex.codeUnitAt(prev) == 0x5D) {
    final optionalOpen = _findMatchingOpenBracket(tex, prev);
    if (optionalOpen != -1) {
      final beforeOptional = _previousNonWhitespaceIndex(tex, optionalOpen - 1);
      if (beforeOptional != -1 && _endsControlWordAt(tex, beforeOptional)) {
        return true;
      }
    }
  }

  return _endsControlWordAt(tex, prev);
}

bool _isScriptArgumentBrace(String tex, int open) {
  final prev = _previousNonWhitespaceIndex(tex, open - 1);
  if (prev == -1) return false;
  final ch = tex.codeUnitAt(prev);
  return ch == 0x5E || ch == 0x5F;
}

bool _hasLiteralBraceBoundaryBefore(String tex, int open) {
  final prev = _previousNonWhitespaceIndex(tex, open - 1);
  if (prev == -1) return true;
  final ch = tex.codeUnitAt(prev);
  if (ch == 0x5C || ch == 0x5E || ch == 0x5F || ch == 0x7D) return false;
  if (_isAsciiLetterOrDigit(ch)) return false;
  return true;
}

int _previousNonWhitespaceIndex(String input, int index) {
  for (var i = index; i >= 0; i--) {
    if (!_isWhitespaceCodeUnit(input.codeUnitAt(i))) return i;
  }
  return -1;
}

int _nextNonWhitespaceCodeUnit(String input, int index) {
  for (var i = index; i < input.length; i++) {
    final ch = input.codeUnitAt(i);
    if (!_isWhitespaceCodeUnit(ch)) return ch;
  }
  return -1;
}

bool _endsControlWordAt(String tex, int index) {
  if (index < 0 || index >= tex.length) return false;
  var start = index;
  while (start >= 0 && _isAsciiLetter(tex.codeUnitAt(start))) {
    start--;
  }
  return start < index && start >= 0 && tex.codeUnitAt(start) == 0x5C;
}

bool _isAsciiLetter(int codeUnit) {
  return (codeUnit >= 0x41 && codeUnit <= 0x5A) ||
      (codeUnit >= 0x61 && codeUnit <= 0x7A);
}

int _findMatchingOpenBracket(String tex, int close) {
  var depth = 0;
  for (var i = close; i >= 0; i--) {
    final ch = tex.codeUnitAt(i);
    if (ch == 0x5C) {
      i--;
      continue;
    }
    if (ch == 0x5D) {
      depth++;
    } else if (ch == 0x5B) {
      depth--;
      if (depth == 0) return i;
    }
  }
  return -1;
}

bool _isEscaped(String input, int index) {
  var backslashes = 0;
  for (var i = index - 1; i >= 0 && input.codeUnitAt(i) == 0x5C; i--) {
    backslashes++;
  }
  return backslashes.isOdd;
}

bool _isWhitespaceCodeUnit(int codeUnit) {
  return codeUnit == 0x20 ||
      codeUnit == 0x09 ||
      codeUnit == 0x0A ||
      codeUnit == 0x0D;
}

bool _isAsciiDigit(int codeUnit) {
  return codeUnit >= 0x30 && codeUnit <= 0x39;
}

bool _isAsciiLetterOrDigit(int codeUnit) {
  return _isAsciiDigit(codeUnit) ||
      (codeUnit >= 0x41 && codeUnit <= 0x5A) ||
      (codeUnit >= 0x61 && codeUnit <= 0x7A);
}

/// Standard LaTeX math environments supported by flutter_math_fork.
const markdownMathEnvironments = <String>{
  'array',
  'darray',
  'matrix',
  'pmatrix',
  'bmatrix',
  'Bmatrix',
  'vmatrix',
  'Vmatrix',
  'smallmatrix',
  'subarray',
  'cases',
  'dcases',
  'rcases',
  'drcases',
  'aligned',
  'alignedat',
  'equation',
  'equation*',
  'align',
  'align*',
  'alignat',
  'alignat*',
  'gather',
  'gather*',
  'gathered',
  'split',
};

final _mathBeginRegex = RegExp(
  r'\\begin\{(' +
      markdownMathEnvironments.map(RegExp.escape).join('|') +
      r')\}',
);

/// Wraps bare LaTeX math environments in `\[\n...\n\]` so the markdown parser
/// recognizes them as display math blocks.
String wrapBareMathEnvironments(String input) {
  if (!input.contains(r'\begin{')) return input;

  final protectedRanges = <_MathSpan>[];

  // Protect fenced code blocks: ```...``` or ~~~...~~~
  final fenceRegex = RegExp(
    r'^[ \t]*(`{3,}|~{3,})[^\n]*\n[\s\S]*?\n[ \t]*\1[ \t]*$',
    multiLine: true,
  );
  for (final m in fenceRegex.allMatches(input)) {
    protectedRanges.add(_MathSpan(m.start, m.end));
  }

  // Protect existing display math blocks: $$...$$
  final doubleDollarRegex = RegExp(r'\$\$[\s\S]*?\$\$');
  for (final m in doubleDollarRegex.allMatches(input)) {
    protectedRanges.add(_MathSpan(m.start, m.end));
  }

  // Protect existing bracket math blocks: \[...\]
  final bracketMathRegex = RegExp(r'\\\[[\s\S]*?\\\]');
  for (final m in bracketMathRegex.allMatches(input)) {
    protectedRanges.add(_MathSpan(m.start, m.end));
  }

  bool isProtected(int offset) {
    for (final p in protectedRanges) {
      if (offset >= p.start && offset < p.end) return true;
    }
    return false;
  }

  final bareSpans = <_MathSpan>[];
  var searchFrom = 0;

  while (searchFrom < input.length) {
    final match = _mathBeginRegex.firstMatch(input.substring(searchFrom));
    if (match == null) break;

    final beginStart = searchFrom + match.start;
    final envName = match.group(1)!;

    if (isProtected(beginStart)) {
      searchFrom = searchFrom + match.end;
      continue;
    }

    // Verify it begins on a line boundary (only whitespace before it on the same line)
    if (beginStart > 0) {
      final lineStart = input.lastIndexOf('\n', beginStart - 1);
      final preceding = input.substring(
        lineStart == -1 ? 0 : lineStart + 1,
        beginStart,
      );
      if (preceding.trim().isNotEmpty) {
        searchFrom = searchFrom + match.end;
        continue;
      }
    }

    // Find the matching \end{envName}, handling nesting
    final endPattern = '\\end{$envName}';
    final beginPattern = '\\begin{$envName}';
    var depth = 1;
    var scanIdx = searchFrom + match.end;
    int? matchedEnd;

    while (scanIdx < input.length) {
      final nextBegin = input.indexOf(beginPattern, scanIdx);
      final nextEnd = input.indexOf(endPattern, scanIdx);

      if (nextEnd == -1) break; // Unclosed environment

      if (nextBegin != -1 && nextBegin < nextEnd) {
        depth++;
        scanIdx = nextBegin + beginPattern.length;
      } else {
        depth--;
        if (depth == 0) {
          // Check for trailing whitespace on the same line after \end{envName}
          var endPos = nextEnd + endPattern.length;
          while (endPos < input.length &&
              (input.codeUnitAt(endPos) == 0x20 ||
                  input.codeUnitAt(endPos) == 0x09)) {
            endPos++;
          }
          matchedEnd = endPos;
          break;
        }
        scanIdx = nextEnd + endPattern.length;
      }
    }

    if (matchedEnd != null) {
      bareSpans.add(_MathSpan(beginStart, matchedEnd));
      searchFrom = matchedEnd;
    } else {
      searchFrom = searchFrom + match.end;
    }
  }

  if (bareSpans.isEmpty) return input;

  final buf = StringBuffer();
  var cursor = 0;
  for (final span in bareSpans) {
    buf.write(input.substring(cursor, span.start));
    if (span.start > 0 && input.codeUnitAt(span.start - 1) != 0x0A) {
      buf.write('\n\n');
    }
    buf.write('\\[\n');
    buf.write(input.substring(span.start, span.end).trim());
    buf.write('\n\\]');
    if (span.end < input.length && input.codeUnitAt(span.end) != 0x0A) {
      buf.write('\n\n');
    }
    cursor = span.end;
  }
  buf.write(input.substring(cursor));
  return buf.toString();
}

class _MathSpan {
  const _MathSpan(this.start, this.end);
  final int start;
  final int end;
}
