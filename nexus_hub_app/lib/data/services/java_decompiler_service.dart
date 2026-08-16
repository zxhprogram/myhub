import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:java_decompiler/java_decompiler.dart';

/// Result of decompiling a single .class file.
class JavaDecompilerResult {
  const JavaDecompilerResult({
    required this.filePath,
    required this.className,
    required this.majorVersion,
    required this.minorVersion,
    required this.source,
  });

  /// Absolute path of the decompiled file.
  final String filePath;

  /// Binary class name in source form (`com.example.Foo`).
  final String className;

  /// class-file major version (e.g. 61 for Java 17).
  final int majorVersion;

  /// class-file minor version.
  final int minorVersion;

  /// Decompiled Java source text.
  final String source;

  /// Human-readable JDK version this class file was compiled with.
  String get javaVersion => _majorToJavaVersion(majorVersion, minorVersion);
}

/// Decompiles Java .class files using the vendored `java_decompiler` package
/// (path dependency at ../../java-decompiler).
///
/// Parsing and decompilation run on a background isolate so large class files
/// never block the UI thread.
class JavaDecompilerService {
  /// Reads and decompiles the .class file at [filePath].
  ///
  /// Throws if the file does not exist or is not a valid class file (e.g. the
  /// magic number check fails inside [ClassFileParser]).
  Future<JavaDecompilerResult> decompileFile(String filePath) async {
    final file = File(filePath);
    final bytes = await file.readAsBytes();
    return Isolate.run(() => _decompileSync(filePath, bytes));
  }

  static JavaDecompilerResult _decompileSync(
    String filePath,
    Uint8List bytes,
  ) {
    final classFile = ClassFileParser(bytes).parse();
    final source = Decompiler(classFile).decompile();
    final internalName = classFile.constantPool.getClassName(
      classFile.thisClass,
    );
    return JavaDecompilerResult(
      filePath: filePath,
      className: internalName.replaceAll('/', '.'),
      majorVersion: classFile.majorVersion,
      minorVersion: classFile.minorVersion,
      source: source,
    );
  }
}

/// Maps a class-file version to its JDK release string.
/// Reference: https://javaalmanac.io/wiki/class_file_versions/
String _majorToJavaVersion(int major, int minor) {
  const map = {
    45: '1.1',
    46: '1.2',
    47: '1.3',
    48: '1.4',
    49: '5',
    50: '6',
    51: '7',
    52: '8',
    53: '9',
    54: '10',
    55: '11',
    56: '12',
    57: '13',
    58: '14',
    59: '15',
    60: '16',
    61: '17',
    62: '18',
    63: '19',
    64: '20',
    65: '21',
    66: '22',
    67: '23',
    68: '24',
    69: '25',
  };
  final base = map[major] ?? 'unknown (major=$major)';
  final isPreview = minor != 0 && minor != 3;
  return isPreview ? '$base (preview)' : base;
}
