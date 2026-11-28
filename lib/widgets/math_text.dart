import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';

/// 混合普通文本、LaTeX 与题目图片的文本组件。
///
/// Moodle 的题目 HTML 里常见 `\(...\)`、`\[...\]`、`$$...$$` 和
/// `\begin{...}...\end{...}`；图片则由模型层编码成 `⟦IMG:...⟧`。
/// 这里把数学片段交给 `flutter_math_fork` 渲染，图片通过
/// [resolveImageUrl] 补上 wstoken 后加载，普通文本仍使用应用自己的字体。
class MathText extends StatelessWidget {
  const MathText(
    this.text, {
    super.key,
    this.style,
    this.textAlign = TextAlign.start,
    this.maxLines,
    this.overflow = TextOverflow.clip,
    this.resolveImageUrl,
  });

  final String text;
  final TextStyle? style;
  final TextAlign textAlign;
  final int? maxLines;
  final TextOverflow overflow;

  /// 把题目里的相对图片地址转换成可访问的地址（通常要补上 wstoken）。
  final String Function(String url)? resolveImageUrl;

  @override
  Widget build(BuildContext context) {
    final baseStyle = DefaultTextStyle.of(context).style.merge(style);
    final blocks = _parseBlocks(text);
    if (blocks.length == 1 && blocks.first is _TextBlock) {
      return Text.rich(
        TextSpan(
          children: _inlineSpans(
            (blocks.first as _TextBlock).text,
            baseStyle,
            resolveImageUrl,
          ),
        ),
        style: baseStyle,
        textAlign: textAlign,
        maxLines: maxLines,
        overflow: overflow,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < blocks.length; i++)
          if (blocks[i] is _TextBlock)
            Text.rich(
              TextSpan(
                children: _inlineSpans(
                  (blocks[i] as _TextBlock).text,
                  baseStyle,
                  resolveImageUrl,
                ),
              ),
              style: baseStyle,
              textAlign: textAlign,
              maxLines: i == blocks.length - 1 ? maxLines : null,
              overflow: overflow,
            )
          else if (blocks[i] is _ImageExpression)
            _buildImageBlock(
              (blocks[i] as _ImageExpression).marker,
              baseStyle,
              resolveImageUrl,
            )
          else
            _MathBlock(
              expression: (blocks[i] as _MathExpression).expression,
              style: baseStyle,
            ),
      ],
    );
  }
}

/// 用于列表摘要：把公式和图片替换成占位文字，避免窄行里露出源码。
String stripMathForPreview(String text) {
  var value = text;
  value = value.replaceAll(RegExp(r'\$\$[\s\S]*?\$\$'), ' [公式] ');
  value = value.replaceAll(RegExp(r'\\\[[\s\S]*?\\\]'), ' [公式] ');
  value = value.replaceAll(RegExp(r'\\\([\s\S]*?\\\)'), ' [公式] ');
  value = value.replaceAll(
    RegExp(r'\\begin\{([a-zA-Z*]+)\}[\s\S]*?\\end\{\1\}'),
    ' [公式] ',
  );
  value = value.replaceAll(RegExp(r'⟦IMG:[A-Za-z0-9_-]+⟧'), ' [图片] ');
  value = value.replaceAll('**', '').replaceAll('`', '');
  return value.replaceAll(RegExp(r'\s+'), ' ').trim();
}

List<InlineSpan> _inlineSpans(
  String text,
  TextStyle style,
  String Function(String url)? resolveImageUrl,
) {
  final spans = <InlineSpan>[];
  var start = 0;
  for (final match in _inlineToken.allMatches(text)) {
    if (match.start > start) {
      spans.addAll(_textSpans(text.substring(start, match.start), style));
    }
    final expression = (match.group(1) ?? '').trim();
    final imagePayload = match.group(2);
    if (imagePayload != null) {
      final image = _decodeImageMarker(imagePayload);
      if (image == null) {
        spans.add(TextSpan(text: match.group(0)!));
      } else {
        spans.add(
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: _QuestionImage(
              src: image.$1,
              alt: image.$2,
              style: style,
              resolveImageUrl: resolveImageUrl,
            ),
          ),
        );
      }
    } else if (expression.isEmpty) {
      spans.add(TextSpan(text: match.group(0)!));
    } else {
      spans.add(
        WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: Math.tex(
            _normalizeTex(expression),
            mathStyle: MathStyle.text,
            textStyle: style,
            onErrorFallback: (error) => Text(match.group(0)!, style: style),
          ),
        ),
      );
    }
    start = match.end;
  }
  if (start < text.length) {
    spans.addAll(_textSpans(text.substring(start), style));
  }
  if (spans.isEmpty) spans.add(TextSpan(text: text));
  return spans;
}

final RegExp _textStylePattern = RegExp(r'\*\*([\s\S]*?)\*\*|`([^`]*)`');

List<TextSpan> _textSpans(String text, TextStyle style) {
  final spans = <TextSpan>[];
  var start = 0;
  for (final match in _textStylePattern.allMatches(text)) {
    if (match.start > start) {
      spans.add(TextSpan(text: text.substring(start, match.start)));
    }
    final bold = match.group(1);
    final code = match.group(2);
    if (bold != null) {
      spans.add(
        TextSpan(
          text: bold,
          style: style.copyWith(fontWeight: FontWeight.w700),
        ),
      );
    } else if (code != null) {
      spans.add(
        TextSpan(
          text: code,
          style: style.copyWith(fontFamily: 'monospace'),
        ),
      );
    }
    start = match.end;
  }
  if (start < text.length) {
    spans.add(TextSpan(text: text.substring(start)));
  }
  if (spans.isEmpty) spans.add(TextSpan(text: text));
  return spans;
}

String _normalizeTex(String expression) {
  return expression
      .replaceAll('&amp;', '&')
      .replaceAll(RegExp(r'\\gt(?![a-zA-Z])'), '>')
      .replaceAll(RegExp(r'\\lt(?![a-zA-Z])'), '<')
      .replaceAll(RegExp(r'\\amp(?![a-zA-Z])'), '&')
      .replaceAll(RegExp(r'\\leqslant(?![a-zA-Z])'), r'\leq')
      .replaceAll(RegExp(r'\\geqslant(?![a-zA-Z])'), r'\geq')
      .replaceAll(RegExp(r'\\varDelta(?![a-zA-Z])'), r'\Delta')
      .replaceAll(RegExp(r'\\colon(?![a-zA-Z])'), ':');
}

final RegExp _imageMarkerPattern = RegExp(r'⟦IMG:[A-Za-z0-9_-]+⟧');

final RegExp _inlineToken = RegExp(
  r'\\\(([\s\S]*?)\\\)|⟦IMG:([A-Za-z0-9_-]+)⟧',
);

final RegExp _displayMath = RegExp(
  r'\$\$([\s\S]*?)\$\$'
  r'|\\\[([\s\S]*?)\\\]'
  r'|\\begin\{([a-zA-Z*]+)\}([\s\S]*?)\\end\{\3\}',
);

List<Object> _parseBlocks(String text) {
  final blocks = <Object>[];
  var start = 0;
  for (final match in _displayMath.allMatches(text)) {
    if (match.start > start) {
      blocks.add(_TextBlock(text.substring(start, match.start)));
    }
    final expression =
        match.group(1) ??
        match.group(2) ??
        (match.group(3) == null
            ? ''
            : '\\begin{${match.group(3)}}${match.group(4)}\\end{${match.group(3)}}');
    if (expression.trim().isNotEmpty) {
      blocks.add(_MathExpression(expression.trim()));
    }
    start = match.end;
  }
  if (start < text.length) {
    blocks.add(_TextBlock(text.substring(start)));
  }
  if (blocks.isEmpty) blocks.add(const _TextBlock(''));

  // 图片单独成块，避免多张图片挤在同一行导致横向溢出。
  final result = <Object>[];
  for (final block in blocks) {
    if (block is _TextBlock) {
      result.addAll(_splitImages(block.text));
    } else {
      result.add(block);
    }
  }
  return result.isEmpty ? [const _TextBlock('')] : result;
}

List<Object> _splitImages(String text) {
  final parts = <Object>[];
  var start = 0;
  for (final match in _imageMarkerPattern.allMatches(text)) {
    if (match.start > start) {
      parts.add(_TextBlock(text.substring(start, match.start)));
    }
    parts.add(_ImageExpression(match.group(0)!));
    start = match.end;
  }
  if (start < text.length) parts.add(_TextBlock(text.substring(start)));
  return parts;
}

Widget _buildImageBlock(
  String marker,
  TextStyle style,
  String Function(String url)? resolveImageUrl,
) {
  final payload = marker.substring(5, marker.length - 1);
  final image = _decodeImageMarker(payload);
  if (image == null) return Text(marker, style: style);
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Center(
      child: _QuestionImage(
        src: image.$1,
        alt: image.$2,
        style: style,
        resolveImageUrl: resolveImageUrl,
      ),
    ),
  );
}

(String, String)? _decodeImageMarker(String payload) {
  try {
    var value = payload;
    final padding = (4 - value.length % 4) % 4;
    if (padding > 0) value += '=' * padding;
    final decoded = utf8.decode(base64Url.decode(value));
    final json = jsonDecode(decoded);
    if (json is! Map) return null;
    final src = json['src']?.toString().trim() ?? '';
    if (src.isEmpty) return null;
    return (src, json['alt']?.toString().trim() ?? '');
  } catch (_) {
    return null;
  }
}

class _TextBlock {
  const _TextBlock(this.text);

  final String text;
}

class _MathExpression {
  const _MathExpression(this.expression);

  final String expression;
}

class _ImageExpression {
  const _ImageExpression(this.marker);

  final String marker;
}

class _MathBlock extends StatelessWidget {
  const _MathBlock({required this.expression, required this.style});

  final String expression;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Math.tex(
          _normalizeTex(expression),
          mathStyle: MathStyle.display,
          textStyle: style,
          onErrorFallback: (error) => Text(expression, style: style),
        ),
      ),
    );
  }
}

class _QuestionImage extends StatelessWidget {
  const _QuestionImage({
    required this.src,
    required this.alt,
    required this.style,
    required this.resolveImageUrl,
  });

  final String src;
  final String alt;
  final TextStyle style;
  final String Function(String url)? resolveImageUrl;

  @override
  Widget build(BuildContext context) {
    final url = resolveImageUrl?.call(src) ?? src;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 280, maxHeight: 320),
        child: GestureDetector(
          onTap: () {
            showDialog<void>(
              context: context,
              builder: (context) => Dialog(
                insetPadding: const EdgeInsets.all(12),
                backgroundColor: Colors.black,
                child: Stack(
                  children: [
                    InteractiveViewer(
                      minScale: 1,
                      maxScale: 4,
                      child: Image.network(url, fit: BoxFit.contain),
                    ),
                    Positioned(
                      top: 4,
                      right: 4,
                      child: IconButton(
                        tooltip: '关闭',
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close, color: Colors.white),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
          child: Image.network(
            url,
            fit: BoxFit.contain,
            cacheWidth: 1200,
            errorBuilder: (_, __, ___) =>
                Text(alt.isEmpty ? '[图片]' : '[图片：$alt]', style: style),
            loadingBuilder: (context, child, progress) {
              if (progress == null) return child;
              return const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              );
            },
          ),
        ),
      ),
    );
  }
}
