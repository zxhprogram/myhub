import 'dart:convert';
import 'dart:typed_data';

import 'package:fast_gbk/fast_gbk.dart';

/// Best-effort text decoding for e-book source files.
///
/// E-book files, especially plain-text novels from Chinese sites, are not
/// always UTF-8. Strict UTF-8 is tried first; on failure the bytes are
/// decoded as GBK and, as a last resort, Latin-1 (which never fails).
String decodeTextBytes(Uint8List bytes) {
  try {
    return utf8.decode(bytes);
  } catch (_) {
    // Fall through to GBK.
  }
  try {
    return gbk.decode(bytes);
  } catch (_) {
    // Fall through to Latin-1.
  }
  return latin1.decode(bytes, allowInvalid: true);
}
