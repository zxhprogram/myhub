/// Exception thrown when a scraped video page does not contain the data
/// the protocol expects (missing payload, unexpected status code, failed
/// decryption, ...).
class StateException implements Exception {
  StateException(this.message);

  final String message;

  @override
  String toString() => message;
}
