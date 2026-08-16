/// Exception thrown when the anonymous Zhihu endpoints fail or return an
/// unexpected payload (risk-control rejection, login wall, parse error).
class ZhihuException implements Exception {
  const ZhihuException(this.message);

  final String message;

  @override
  String toString() => message;
}
