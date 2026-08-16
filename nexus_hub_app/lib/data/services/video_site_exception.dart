/// Exception thrown when a scraped video page does not contain the data
/// the protocol expects (missing payload, unexpected status code, failed
/// decryption, ...).
class StateException implements Exception {
  StateException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Exception thrown when the site gates a page behind an image captcha
/// that only the user can solve. The caller should collect the code via
/// the site service's captcha helpers (fetch the image, submit the code)
/// and retry the original request.
class CaptchaRequiredException implements Exception {
  CaptchaRequiredException(this.message);

  final String message;

  @override
  String toString() => message;
}
