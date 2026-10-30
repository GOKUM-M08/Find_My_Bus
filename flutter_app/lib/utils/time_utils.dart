/// Shared time and timestamp utilities for bus live tracking.

/// Returns true if [ts] represents a live bus timestamp.
///
/// Parses [ts] as UTC, computes the difference in seconds from the current UTC time:
/// `diffSeconds = DateTime.now().toUtc().difference(parsed).inSeconds`.
///
/// Returns true only if `diffSeconds >= -30 && diffSeconds < 60`.
/// Timestamps from the future (beyond a 30s clock skew window) or older than 60s
/// are considered NOT live.
/// Returns false for null or unparseable values.
bool isLiveTimestamp(String? ts) {
  if (ts == null) return false;
  try {
    final parsed = DateTime.parse(ts).toUtc();
    final diffSeconds = DateTime.now().toUtc().difference(parsed).inSeconds;
    return diffSeconds >= -30 && diffSeconds < 60;
  } catch (_) {
    return false;
  }
}
