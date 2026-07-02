import 'package:nexus_hub_api/task_validation.dart';
import 'package:test/test.dart';

void main() {
  test('accepts valid Delta JSON', () {
    expect(
      validateDescription(r'{"ops":[{"insert":"hello\n"}]}'),
      isNull,
    );
  });

  test('rejects too-long description', () {
    expect(
      validateDescription('a' * 10001),
      isNotNull,
    );
  });

  test('accepts plain text', () {
    expect(validateDescription('plain'), isNull);
  });
}
