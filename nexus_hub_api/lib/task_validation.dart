import 'dart:convert';

/// Validates a task description.
///
/// Returns `null` if valid, otherwise an error message.
String? validateDescription(String? description) {
  if (description == null) return null;
  if (description.length > 10000) {
    return 'Description must be at most 10000 characters';
  }
  final trimmed = description.trim();
  if (trimmed.isEmpty) return null;
  try {
    final json = jsonDecode(trimmed) as Map<String, dynamic>;
    final ops = json['ops'];
    if (ops != null && ops is! List) {
      return 'Invalid rich text format';
    }
  } catch (_) {
    // Non-JSON descriptions are accepted as plain text fallback.
  }
  return null;
}
