import 'dart:convert';

/// Minimal JWT reader. We only ever need the expiry claim, so decoding the
/// payload by hand is cheaper than pulling in a dependency.
class Jwt {
  Jwt._();

  static DateTime? expiryOf(String token) {
    final parts = token.split('.');
    if (parts.length != 3) return null;
    try {
      final payload = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
      ) as Map<String, dynamic>;
      final exp = payload['exp'];
      if (exp is! num) return null;
      return DateTime.fromMillisecondsSinceEpoch(
        exp.toInt() * 1000,
        isUtc: true,
      );
    } catch (_) {
      return null;
    }
  }

  /// Whether [token] lapses within [margin]. A token we cannot read counts as
  /// expiring, so the caller refreshes instead of trusting it.
  static bool expiresWithin(String token, Duration margin) {
    final expiry = expiryOf(token);
    if (expiry == null) return true;
    return DateTime.now().toUtc().add(margin).isAfter(expiry);
  }
}
