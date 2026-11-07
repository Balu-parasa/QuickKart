/// What the app must do about its own version.
enum UpdateRequirement {
  /// Nothing to do.
  none,

  /// A newer version exists; the user may update or dismiss.
  optional,

  /// This version is no longer supported; the app must be blocked until the
  /// user updates.
  required,
}

/// Decides whether the running app must / may be updated.
///
/// ## TODO(F2) - implement
///
/// Contract (hidden tests check this exactly - see ASSIGNMENT.md, Feature 2):
/// * Versions are dotted numbers like `1.4.0`, `1.10.2`, `2.0`. Compare them
///   numerically, segment by segment. Missing segments count as 0
///   (`1.4` == `1.4.0`).
/// * `current < minSupported`  -> [UpdateRequirement.required]
/// * `current < latest`        -> [UpdateRequirement.optional]
/// * otherwise                 -> [UpdateRequirement.none]
/// * If ANY of the three versions is malformed (empty, letters, negative
///   numbers, ...) return [UpdateRequirement.none]. A bad value in the
///   config console must never lock users out of the app.
class UpdatePolicy {
  const UpdatePolicy._();

  static UpdateRequirement evaluate({
    required String currentVersion,
    required String minSupportedVersion,
    required String latestVersion,
  }) {
    final current = _parse(currentVersion);
    final minSupported = _parse(minSupportedVersion);
    final latest = _parse(latestVersion);

    if (current == null || minSupported == null || latest == null) {
      return UpdateRequirement.none;
    }

    if (_compare(current, minSupported) < 0) {
      return UpdateRequirement.required;
    }
    if (_compare(current, latest) < 0) {
      return UpdateRequirement.optional;
    }
    return UpdateRequirement.none;
  }

  static List<int>? _parse(String version) {
    final trimmed = version.trim();
    if (trimmed.isEmpty) return null;

    final parts = trimmed.split('.');
    final segments = <int>[];
    for (final part in parts) {
      if (part.isEmpty) return null;
      // Must contain only ASCII digits 0-9
      for (var i = 0; i < part.length; i++) {
        final code = part.codeUnitAt(i);
        if (code < 48 || code > 57) return null;
      }
      final num = int.tryParse(part);
      if (num == null || num < 0) return null;
      segments.add(num);
    }
    return segments;
  }

  static int _compare(List<int> a, List<int> b) {
    final maxLen = a.length > b.length ? a.length : b.length;
    for (var i = 0; i < maxLen; i++) {
      final segA = i < a.length ? a[i] : 0;
      final segB = i < b.length ? b[i] : 0;
      if (segA < segB) return -1;
      if (segA > segB) return 1;
    }
    return 0;
  }
}
