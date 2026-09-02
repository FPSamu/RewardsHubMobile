/// Dotted version string ("1.2.3", "1.2", "1.2.3.4") as a comparable value.
///
/// Deliberately lenient: a malformed or unknown segment reads as 0 rather than
/// throwing, because a bad value in server config must never brick the app.
class AppVersion implements Comparable<AppVersion> {
  const AppVersion(this.segments);

  final List<int> segments;

  static const zero = AppVersion([0]);

  factory AppVersion.parse(String raw) {
    // Drop a build suffix ("1.0.0+3") and any pre-release tag ("1.0.0-beta").
    final core = raw.trim().split('+').first.split('-').first;
    final parsed = core
        .split('.')
        .map((s) => int.tryParse(s.trim()) ?? 0)
        .toList(growable: false);
    return parsed.isEmpty ? zero : AppVersion(parsed);
  }

  @override
  int compareTo(AppVersion other) {
    final length = segments.length > other.segments.length
        ? segments.length
        : other.segments.length;
    for (var i = 0; i < length; i++) {
      final a = i < segments.length ? segments[i] : 0;
      final b = i < other.segments.length ? other.segments[i] : 0;
      if (a != b) return a.compareTo(b);
    }
    return 0;
  }

  bool operator <(AppVersion other) => compareTo(other) < 0;
  bool operator <=(AppVersion other) => compareTo(other) <= 0;
  bool operator >(AppVersion other) => compareTo(other) > 0;
  bool operator >=(AppVersion other) => compareTo(other) >= 0;

  @override
  String toString() => segments.join('.');

  @override
  bool operator ==(Object other) =>
      other is AppVersion && compareTo(other) == 0;

  @override
  int get hashCode => toString().hashCode;
}
