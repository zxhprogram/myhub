import 'dart:typed_data';

import 'ebook_charset.dart';

/// A detected chapter of a plain-text book, as a character range within
/// [TxtBook.content] (the heading line itself is excluded from the range).
class TxtChapter {
  const TxtChapter({
    required this.title,
    required this.start,
    required this.end,
  });

  final String title;
  final int start;
  final int end;
}

/// Parsed plain-text book.
///
/// Chapter detection targets Chinese web novels (`第X章/节/卷…`), plus the
/// common special openings (序章/楔子/番外). A file with fewer than two
/// matching lines is treated as one single chapter.
class TxtBook {
  TxtBook({required this.content, required this.chapters})
    : chapterBodies = chapters
          .map((c) => content.substring(c.start, c.end).trim())
          .toList();

  final String content;
  final List<TxtChapter> chapters;

  /// Chapter bodies sliced from [content] at parse time, index-aligned
  /// with [chapters].
  final List<String> chapterBodies;
}

class TxtParser {
  const TxtParser._();

  /// Headings like `第一章 大梦谁先觉`, `第12回`, `第 3 卷`, plus special
  /// openings. Must sit on its own line to count as a heading.
  static final RegExp _chapterHeadingRe = RegExp(
    r'^\s*(?:第\s*[0-9零〇一二三四五六七八九十百千万亿两]+'
    r'\s*[章节卷回部篇集幕场]|序章|序言|楔子|引子|前言|后记|尾声|番外)(?:[^\n]{0,40})\s*$',
    multiLine: true,
  );

  static TxtBook parse(Uint8List bytes) {
    var text = decodeTextBytes(bytes);
    text = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');

    final matches = _chapterHeadingRe.allMatches(text).toList();
    if (matches.length < 2) {
      final trimmed = text.trim();
      // A single heading still names the chapter; '正文' is the fallback
      // when no heading was found at all.
      final title =
          matches.length == 1 ? matches.single.group(0)!.trim() : '正文';
      return TxtBook(
        content: trimmed,
        chapters: [TxtChapter(title: title, start: 0, end: trimmed.length)],
      );
    }

    final chapters = <TxtChapter>[];
    for (var i = 0; i < matches.length; i++) {
      final match = matches[i];
      // The body starts after the heading line (the heading is already
      // shown as the chapter title) and ends at the next heading.
      final bodyEnd = i + 1 < matches.length
          ? matches[i + 1].start
          : text.length;
      chapters.add(
        TxtChapter(
          title: match.group(0)!.trim(),
          start: match.end,
          end: bodyEnd,
        ),
      );
    }

    // Whatever precedes the first heading (blurbs, TOC pages) becomes a
    // leading chapter so it is never silently dropped.
    final prologue = text.substring(0, matches.first.start);
    if (prologue.trim().isNotEmpty) {
      chapters.insert(
        0,
        TxtChapter(title: '开篇', start: 0, end: matches.first.start),
      );
    }

    return TxtBook(content: text, chapters: chapters);
  }
}
