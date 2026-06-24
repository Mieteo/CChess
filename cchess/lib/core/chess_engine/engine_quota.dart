// Client-side mirror of the engine service's free-tier quota model.
//
// `GET /engine/quota` returns how much of today's free allowance is left per
// feature, so the app can show "N gợi ý còn lại" and a VIP upsell *before* a
// request is rejected with 429. VIP users report `limit`/`remaining` == -1,
// surfaced here as EngineFeatureQuota.unlimited.

/// Remaining free allowance for a single engine feature today.
class EngineFeatureQuota {
  final int used;

  /// Daily free cap. `-1` means unlimited (VIP).
  final int limit;

  /// Calls left today. `-1` means unlimited (VIP).
  final int remaining;

  const EngineFeatureQuota({
    required this.used,
    required this.limit,
    required this.remaining,
  });

  bool get unlimited => limit < 0;

  bool get exhausted => !unlimited && remaining <= 0;

  factory EngineFeatureQuota.fromJson(Map<String, dynamic> json) {
    return EngineFeatureQuota(
      used: _asInt(json['used']) ?? 0,
      limit: _asInt(json['limit']) ?? 0,
      remaining: _asInt(json['remaining']) ?? 0,
    );
  }
}

/// A snapshot of a user's free engine usage for one day.
class EngineQuotaStatus {
  final String day;
  final bool vip;
  final EngineFeatureQuota bestMove;
  final EngineFeatureQuota hint;
  final EngineFeatureQuota analyze;

  const EngineQuotaStatus({
    required this.day,
    required this.vip,
    required this.bestMove,
    required this.hint,
    required this.analyze,
  });

  factory EngineQuotaStatus.fromJson(Map<String, dynamic> json) {
    final features = json['features'] is Map
        ? (json['features'] as Map).cast<String, dynamic>()
        : const <String, dynamic>{};
    return EngineQuotaStatus(
      day: json['day'] as String? ?? '',
      vip: json['vip'] == true,
      bestMove: _featureFrom(features['best-move']),
      hint: _featureFrom(features['hint']),
      analyze: _featureFrom(features['analyze']),
    );
  }

  static EngineFeatureQuota _featureFrom(Object? raw) {
    if (raw is Map) {
      return EngineFeatureQuota.fromJson(raw.cast<String, dynamic>());
    }
    return const EngineFeatureQuota(used: 0, limit: 0, remaining: 0);
  }
}

/// Thrown when the free daily engine quota for [feature] is exhausted (the
/// service replied 429 `quota-exceeded`). The router turns this into a
/// graceful local fallback tagged with the quota reason so the UI can prompt
/// the user to upgrade instead of blaming the network.
class EngineQuotaExceededException implements Exception {
  final String feature;

  const EngineQuotaExceededException([this.feature = '']);

  @override
  String toString() => 'EngineQuotaExceededException($feature)';
}

int? _asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.round();
  return null;
}
