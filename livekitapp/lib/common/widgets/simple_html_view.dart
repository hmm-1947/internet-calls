import 'package:livekitapp/core/theme/app_theme.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Renders a constrained subset of HTML produced by the admin panel's
/// rich text editor (bold/italic/underline, font size via `<font size=...>`,
/// headings, paragraphs, and bullet/numbered lists) as Flutter widgets.
///
/// This is intentionally not a general-purpose HTML renderer - it only
/// understands the tags the admin panel's editor actually produces, so we
/// avoid pulling in a full HTML/webview dependency just to show legal text.
class SimpleHtmlView extends StatelessWidget {
  final String html;
  final Color? textColor;
  final double baseFontSize;

  const SimpleHtmlView({
    super.key,
    required this.html,
    this.textColor,
    this.baseFontSize = 14,
  });

  @override
  Widget build(BuildContext context) {
    if (html.trim().isEmpty) {
      return Text(
        'Nothing has been added yet.',
        style: TextStyle(color: (textColor ?? context.c.text).withValues(alpha: 0.6), fontSize: baseFontSize),
      );
    }
    final blocks = _HtmlBlockParser(html, textColor ?? context.c.text, baseFontSize).parse();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: blocks);
  }
}

/// Legacy `<font size="1..7">` maps roughly to these pixel sizes, matching
/// what `document.execCommand('fontSize', ...)` in the admin panel produces.
double _legacyFontSize(String size, double base) {
  switch (size) {
    case '1':
      return base * 0.75;
    case '2':
      return base * 0.9;
    case '3':
      return base;
    case '4':
      return base * 1.15;
    case '5':
      return base * 1.4;
    case '6':
      return base * 1.75;
    case '7':
      return base * 2.2;
    default:
      return base;
  }
}

class _InlineStyle {
  final bool bold;
  final bool italic;
  final bool underline;
  final bool strikethrough;
  final double fontSize;
  final String? fontFamily;
  final Color? color;
  final Color? background;
  final String? href;
  const _InlineStyle({
    this.bold = false,
    this.italic = false,
    this.underline = false,
    this.strikethrough = false,
    required this.fontSize,
    this.fontFamily,
    this.color,
    this.background,
    this.href,
  });

  _InlineStyle copyWith({
    bool? bold,
    bool? italic,
    bool? underline,
    bool? strikethrough,
    double? fontSize,
    String? fontFamily,
    Color? color,
    Color? background,
    String? href,
  }) {
    return _InlineStyle(
      bold: bold ?? this.bold,
      italic: italic ?? this.italic,
      underline: underline ?? this.underline,
      strikethrough: strikethrough ?? this.strikethrough,
      fontSize: fontSize ?? this.fontSize,
      fontFamily: fontFamily ?? this.fontFamily,
      color: color ?? this.color,
      background: background ?? this.background,
      href: href ?? this.href,
    );
  }
}

/// Picks the closest bundled/system font family for a CSS font stack like
/// `"'Times New Roman', Times, serif"`, since Flutter can't resolve an
/// arbitrary CSS font-family string the way a browser does.
String? _resolveFontFamily(String cssFamily) {
  final first = cssFamily.split(',').first.replaceAll(RegExp('["\']'), '').trim();
  return first.isEmpty ? null : first;
}

/// Parses a CSS color value produced by the admin panel's color picker
/// (`#rrggbb`, `#rgb`, or `rgb(r, g, b)`) into a Flutter [Color].
Color? _parseCssColor(String css) {
  final value = css.trim();
  final hexMatch = RegExp(r'^#([0-9a-fA-F]{3}|[0-9a-fA-F]{6})$').firstMatch(value);
  if (hexMatch != null) {
    var hex = hexMatch.group(1)!;
    if (hex.length == 3) {
      hex = hex.split('').map((c) => '$c$c').join();
    }
    return Color(int.parse('FF$hex', radix: 16));
  }
  final rgbMatch = RegExp(r'^rgba?\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)').firstMatch(value);
  if (rgbMatch != null) {
    final r = int.parse(rgbMatch.group(1)!);
    final g = int.parse(rgbMatch.group(2)!);
    final b = int.parse(rgbMatch.group(3)!);
    return Color.fromARGB(255, r, g, b);
  }
  return null;
}

class _HtmlBlockParser {
  final String html;
  final Color textColor;
  final double baseFontSize;
  int _pos = 0;

  _HtmlBlockParser(this.html, this.textColor, this.baseFontSize);

  List<Widget> parse() {
    final widgets = <Widget>[];
    _consumeBlocks(widgets, _InlineStyle(fontSize: baseFontSize));
    if (widgets.isEmpty) {
      widgets.add(_paragraph(html, _InlineStyle(fontSize: baseFontSize)));
    }
    return widgets;
  }

  void _consumeBlocks(List<Widget> out, _InlineStyle inherited) {
    final buffer = StringBuffer();
    while (_pos < html.length) {
      if (html[_pos] == '<') {
        final tagEnd = html.indexOf('>', _pos);
        if (tagEnd == -1) {
          buffer.write(html.substring(_pos));
          _pos = html.length;
          break;
        }
        final tag = html.substring(_pos + 1, tagEnd).trim();
        final lower = tag.toLowerCase();
        final isClose = lower.startsWith('/');
        final name = lower
            .replaceFirst('/', '')
            .split(RegExp(r'[\s/]'))
            .first;

        if (!isClose && (name == 'h1' || name == 'h2' || name == 'h3' || name == 'p' || name == 'div')) {
          _flushParagraph(buffer, out, inherited);
          _pos = tagEnd + 1;
          final inner = _collectUntilClose(name);
          if (inner.trim().isNotEmpty) {
            final size = name == 'h1'
                ? baseFontSize * 1.7
                : name == 'h2'
                    ? baseFontSize * 1.4
                    : name == 'h3'
                        ? baseFontSize * 1.2
                        : baseFontSize;
            final bold = name == 'h1' || name == 'h2' || name == 'h3';
            out.add(_paragraph(inner, _InlineStyle(fontSize: size, bold: bold)));
          }
          continue;
        }

        if (!isClose && (name == 'ul' || name == 'ol')) {
          _flushParagraph(buffer, out, inherited);
          _pos = tagEnd + 1;
          final inner = _collectUntilClose(name);
          out.add(_bulletList(inner, ordered: name == 'ol', style: inherited));
          continue;
        }

        if (!isClose && name == 'blockquote') {
          _flushParagraph(buffer, out, inherited);
          _pos = tagEnd + 1;
          final inner = _collectUntilClose(name);
          if (inner.trim().isNotEmpty) {
            out.add(Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Container(
                padding: const EdgeInsets.only(left: 12),
                decoration: BoxDecoration(
                  border: Border(left: BorderSide(color: textColor.withValues(alpha: 0.35), width: 3)),
                ),
                child: Text.rich(TextSpan(
                  children: _parseInline(inner, inherited.copyWith(color: inherited.color ?? textColor.withValues(alpha: 0.8))),
                )),
              ),
            ));
          }
          continue;
        }
        if (!isClose && (name == 'br')) {
          buffer.write('\n');
          _pos = tagEnd + 1;
          continue;
        }

        // Any other tag (span/font/b/i/u/etc.) at block level: keep the raw
        // text in this paragraph's buffer, stripped of tags, since inline
        // formatting inside a bare block is rare from this editor.
        buffer.write(html.substring(_pos, tagEnd + 1));
        _pos = tagEnd + 1;
      } else {
        final nextTag = html.indexOf('<', _pos);
        if (nextTag == -1) {
          buffer.write(html.substring(_pos));
          _pos = html.length;
        } else {
          buffer.write(html.substring(_pos, nextTag));
          _pos = nextTag;
        }
      }
    }
    _flushParagraph(buffer, out, inherited);
  }

  void _flushParagraph(StringBuffer buffer, List<Widget> out, _InlineStyle inherited) {
    final text = buffer.toString();
    if (text.trim().isNotEmpty) {
      out.add(_paragraph(text, inherited));
    }
    buffer.clear();
  }

  /// Reads raw inner HTML until the matching close tag for [name], handling
  /// simple nesting of the same tag name.
  String _collectUntilClose(String name) {
    final start = _pos;
    var depth = 1;
    final openRe = RegExp('<$name\\b', caseSensitive: false);
    final closeTag = '</$name>';
    while (_pos < html.length) {
      final nextClose = html.toLowerCase().indexOf(closeTag, _pos);
      final nextOpenMatch = openRe.firstMatch(html.substring(_pos));
      final nextOpen = nextOpenMatch == null ? -1 : _pos + nextOpenMatch.start;
      if (nextClose == -1) {
        final result = html.substring(start);
        _pos = html.length;
        return result;
      }
      if (nextOpen != -1 && nextOpen < nextClose) {
        depth++;
        _pos = nextOpen + name.length + 1;
        continue;
      }
      depth--;
      if (depth == 0) {
        final result = html.substring(start, nextClose);
        _pos = nextClose + closeTag.length;
        return result;
      }
      _pos = nextClose + closeTag.length;
    }
    return html.substring(start);
  }

  Widget _paragraph(String innerHtml, _InlineStyle blockStyle) {
    final spans = _parseInline(innerHtml, blockStyle);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text.rich(TextSpan(children: spans)),
    );
  }

  Widget _bulletList(String innerHtml, {required bool ordered, required _InlineStyle style}) {
    final items = <String>[];
    var pos = 0;
    while (true) {
      final start = innerHtml.toLowerCase().indexOf('<li', pos);
      if (start == -1) break;
      final openEnd = innerHtml.indexOf('>', start);
      if (openEnd == -1) break;
      final closeIdx = innerHtml.toLowerCase().indexOf('</li>', openEnd);
      final content = closeIdx == -1
          ? innerHtml.substring(openEnd + 1)
          : innerHtml.substring(openEnd + 1, closeIdx);
      items.add(content);
      pos = closeIdx == -1 ? innerHtml.length : closeIdx + 5;
      if (pos >= innerHtml.length) break;
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < items.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 22,
                    child: Text(
                      ordered ? '${i + 1}.' : '\u2022',
                      style: TextStyle(color: textColor, fontSize: style.fontSize),
                    ),
                  ),
                  Expanded(
                    child: Text.rich(TextSpan(children: _parseInline(items[i], style))),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  List<InlineSpan> _parseInline(String innerHtml, _InlineStyle inherited) {
    final spans = <InlineSpan>[];
    final stack = <_InlineStyle>[inherited];
    var pos = 0;
    final buffer = StringBuffer();

    void flush() {
      if (buffer.isEmpty) return;
      final s = stack.last;
      TextDecoration decoration = TextDecoration.none;
      if (s.underline && s.strikethrough) {
        decoration = TextDecoration.combine([TextDecoration.underline, TextDecoration.lineThrough]);
      } else if (s.underline) {
        decoration = TextDecoration.underline;
      } else if (s.strikethrough) {
        decoration = TextDecoration.lineThrough;
      }
      final style = TextStyle(
        color: s.href != null ? AppColors.brand : (s.color ?? textColor),
        backgroundColor: s.background,
        fontSize: s.fontSize,
        fontFamily: s.fontFamily,
        fontWeight: s.bold ? FontWeight.w700 : FontWeight.w400,
        fontStyle: s.italic ? FontStyle.italic : FontStyle.normal,
        decoration: s.href != null ? TextDecoration.underline : decoration,
        height: 1.5,
      );
      if (s.href != null) {
        final href = s.href!;
        spans.add(TextSpan(
          text: _decodeEntities(buffer.toString()),
          style: style,
          recognizer: TapGestureRecognizer()
            ..onTap = () {
              final uri = Uri.tryParse(href);
              if (uri != null) launchUrl(uri, mode: LaunchMode.externalApplication);
            },
        ));
      } else {
        spans.add(TextSpan(text: _decodeEntities(buffer.toString()), style: style));
      }
      buffer.clear();
    }

    while (pos < innerHtml.length) {
      if (innerHtml[pos] == '<') {
        final end = innerHtml.indexOf('>', pos);
        if (end == -1) {
          buffer.write(innerHtml.substring(pos));
          break;
        }
        final tag = innerHtml.substring(pos + 1, end).trim();
        final lower = tag.toLowerCase();
        final isClose = lower.startsWith('/');
        final name = lower.replaceFirst('/', '').split(RegExp(r'[\s/]')).first;

        if (name == 'br') {
          buffer.write('\n');
        } else if (!isClose) {
          flush();
          final current = stack.last;
          if (name == 'b' || name == 'strong') {
            stack.add(current.copyWith(bold: true));
          } else if (name == 'i' || name == 'em') {
            stack.add(current.copyWith(italic: true));
          } else if (name == 'u') {
            stack.add(current.copyWith(underline: true));
          } else if (name == 's' || name == 'strike' || name == 'del') {
            stack.add(current.copyWith(strikethrough: true));
          } else if (name == 'a') {
            final hrefMatch = RegExp('href="([^"]*)"').firstMatch(tag);
            stack.add(current.copyWith(href: hrefMatch?.group(1) ?? ''));
          } else if (name == 'font') {
            final sizeMatch = RegExp('size="?(\\d)"?').firstMatch(lower);
            final faceMatch = RegExp('face="([^"]+)"').firstMatch(tag);
            var next = current;
            if (sizeMatch != null) {
              next = next.copyWith(fontSize: _legacyFontSize(sizeMatch.group(1)!, baseFontSize));
            }
            if (faceMatch != null) {
              next = next.copyWith(fontFamily: _resolveFontFamily(faceMatch.group(1)!));
            }
            stack.add(next);
          } else if (name == 'span') {
            final ptMatch = RegExp(r'font-size:\s*([\d.]+)pt').firstMatch(lower);
            final pxMatch = RegExp(r'font-size:\s*([\d.]+)px').firstMatch(lower);
            final familyMatch = RegExp('font-family:\\s*([^;"]+)').firstMatch(lower);
            // Match "color:" but not "background-color:"/"border-color:" etc,
            // and grab the raw-case value since hex/rgb parsing doesn't care
            // about case but we still want the original from `tag`, not `lower`.
            final colorMatch = RegExp(r'(?<![\w-])color:\s*([^;"]+)').firstMatch(tag);
            final backgroundMatch = RegExp(r'background-color:\s*([^;"]+)').firstMatch(tag);
            var next = current;
            if (ptMatch != null) {
              // 1pt == 1.333px, matching the CSS conversion the admin
              // panel's contenteditable preview uses.
              next = next.copyWith(fontSize: double.parse(ptMatch.group(1)!) * 1.333);
            } else if (pxMatch != null) {
              next = next.copyWith(fontSize: double.parse(pxMatch.group(1)!));
            }
            if (familyMatch != null) {
              next = next.copyWith(fontFamily: _resolveFontFamily(familyMatch.group(1)!));
            }
            if (colorMatch != null) {
              final parsed = _parseCssColor(colorMatch.group(1)!.trim());
              if (parsed != null) next = next.copyWith(color: parsed);
            }
            if (backgroundMatch != null) {
              final parsed = _parseCssColor(backgroundMatch.group(1)!.trim());
              if (parsed != null) next = next.copyWith(background: parsed);
            }
            stack.add(next);
          } else {
            stack.add(current);
          }
        } else {
          flush();
          if (stack.length > 1) stack.removeLast();
        }
        pos = end + 1;
      } else {
        final nextTag = innerHtml.indexOf('<', pos);
        if (nextTag == -1) {
          buffer.write(innerHtml.substring(pos));
          pos = innerHtml.length;
        } else {
          buffer.write(innerHtml.substring(pos, nextTag));
          pos = nextTag;
        }
      }
    }
    flush();
    return spans;
  }

  String _decodeEntities(String s) {
    return s
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'");
  }
}
