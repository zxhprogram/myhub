import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_hub_app/data/services/java_decompiler_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Real class file shipped with the java-decompiler package repo.
  final sampleClass =
      Platform.script.resolve('../../java-decompiler/DateUtils.class').toFilePath();

  test('decompiles a real .class file into Java source', () async {
    final result = await JavaDecompilerService().decompileFile(sampleClass);

    expect(result.source, isNotEmpty);
    expect(result.source, contains('DateUtils'));
    // Decompiled output must look like Java, not raw bytecode.
    expect(result.source, contains(RegExp(r'\bclass\s+DateUtils\b')));
    expect(result.className, contains('DateUtils'));
    expect(result.majorVersion, 52); // major 0x34 => Java 8
    expect(result.javaVersion, '8');
  });

  test('rejects files that are not valid class files', () async {
    final tmp = File(
      '${Directory.systemTemp.path}/nexus_invalid_${DateTime.now().millisecondsSinceEpoch}.class',
    )..writeAsStringSync('this is not a class file');

    try {
      await JavaDecompilerService().decompileFile(tmp.path);
      fail('expected decompileFile to throw');
    } catch (e) {
      expect(e, isNotNull);
    } finally {
      tmp.deleteSync();
    }
  });
}
