import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../core/constants/app_constants.dart';
import '../datasources/remote/economy_api_source.dart';
import '../models/economy_models.dart';

/// Repository for the S16 economy extension (D4 Hộp Thư / D5 Sự Kiện /
/// D6 Phúc Lợi / D7 Đúc Bàn Cờ). Server-authoritative like the shop: reads go
/// backend → Hive-cache fallback so the screens still render offline; every
/// mutation (claim, check-in, craft) requires the server and throws
/// [EconomyApiException] when offline.
class EconomyRepository {
  EconomyRepository({EconomyApiSource? remote}) : _remote = remote;

  final EconomyApiSource? _remote;

  static const String _boxName = AppConstants.boxEconomy;
  static const String _kMail = 'mail';
  static const String _kEvents = 'events';
  static const String _kEventClaims = 'event_claims';
  static const String _kWelfare = 'welfare';
  static const String _kRecipes = 'recipes';

  Box<dynamic>? _box;

  Future<Box<dynamic>> _openBox() async {
    final existing = _box;
    if (existing != null && existing.isOpen) return existing;
    final box = await Hive.openBox<dynamic>(_boxName);
    _box = box;
    return box;
  }

  static const _offline = EconomyApiException(
    code: 'offline',
    message: 'Không thể thực hiện khi ngoại tuyến',
  );

  // ── Mail (D4) ─────────────────────────────────────────────────────────────

  Future<List<MailMessage>> mail() async {
    final remote = _remote;
    if (remote != null) {
      try {
        final messages = await remote.listMail();
        await _cacheList(_kMail, messages.map((m) => m.toJson()));
        return messages;
      } on EconomyApiException {
        // fall through to cache
      }
    }
    return cachedMail();
  }

  Future<List<MailMessage>> cachedMail() async =>
      _readList(_kMail, MailMessage.fromJson);

  /// Count shown as the badge on the Explore tile.
  Future<int> unreadMailCount() async {
    final messages = await cachedMail();
    return messages.where((m) => !m.read || m.hasUnclaimedReward).length;
  }

  Future<void> markMailRead(String mailId) async {
    final remote = _remote;
    if (remote == null) throw _offline;
    await remote.markMailRead(mailId);
    await _patchCachedMail(mailId, (m) => m.copyWith(read: true));
  }

  Future<ClaimOutcome> claimMail(String mailId) async {
    final remote = _remote;
    if (remote == null) throw _offline;
    final outcome = await remote.claimMail(mailId);
    await _patchCachedMail(mailId, (m) => m.copyWith(read: true, claimed: true));
    return outcome;
  }

  Future<void> deleteMail(String mailId) async {
    final remote = _remote;
    if (remote == null) throw _offline;
    await remote.deleteMail(mailId);
    final current = await cachedMail();
    await _cacheList(
      _kMail,
      current.where((m) => m.id != mailId).map((m) => m.toJson()),
    );
  }

  Future<void> _patchCachedMail(
    String mailId,
    MailMessage Function(MailMessage) patch,
  ) async {
    final current = await cachedMail();
    await _cacheList(
      _kMail,
      current.map((m) => m.id == mailId ? patch(m) : m).map((m) => m.toJson()),
    );
  }

  // ── Events (D5) ───────────────────────────────────────────────────────────

  Future<List<EconEvent>> events() async {
    final remote = _remote;
    if (remote != null) {
      try {
        final events = await remote.listEvents();
        await _cacheList(_kEvents, events.map((e) => e.toJson()));
        return events;
      } on EconomyApiException {
        // fall through to cache
      }
    }
    return _readList(_kEvents, EconEvent.fromJson);
  }

  /// Claimed gift keys (`eventId__giftId`) of the signed-in user.
  Future<Set<String>> eventClaims() async {
    final remote = _remote;
    if (remote != null) {
      try {
        final claims = await remote.listEventClaims();
        final box = await _openBox();
        await box.put(_kEventClaims, claims.toList());
        return claims;
      } on EconomyApiException {
        // fall through to cache
      }
    }
    final box = await _openBox();
    final raw = box.get(_kEventClaims);
    return raw is List ? raw.whereType<String>().toSet() : const {};
  }

  Future<ClaimOutcome> claimEventGift(String eventId, String giftId) async {
    final remote = _remote;
    if (remote == null) throw _offline;
    final outcome = await remote.claimEventGift(eventId, giftId);
    final box = await _openBox();
    final raw = box.get(_kEventClaims);
    final claims = raw is List ? raw.whereType<String>().toSet() : <String>{};
    claims.add('${eventId}__$giftId');
    await box.put(_kEventClaims, claims.toList());
    return outcome;
  }

  // ── Welfare (D6) ──────────────────────────────────────────────────────────

  Future<WelfareStatus> welfare() async {
    final remote = _remote;
    if (remote != null) {
      try {
        final status = await remote.getWelfare();
        final box = await _openBox();
        await box.put(_kWelfare, status.toJson());
        return status;
      } on EconomyApiException {
        // fall through to cache
      }
    }
    final box = await _openBox();
    final raw = box.get(_kWelfare);
    return raw is Map ? WelfareStatus.fromJson(raw) : const WelfareStatus();
  }

  Future<WelfareClaimOutcome> checkin() => _welfareClaim((r) => r.checkin());

  Future<WelfareClaimOutcome> claimNewbie() =>
      _welfareClaim((r) => r.claimNewbie());

  Future<WelfareClaimOutcome> claimComeback() =>
      _welfareClaim((r) => r.claimComeback());

  Future<WelfareClaimOutcome> _welfareClaim(
    Future<WelfareClaimOutcome> Function(EconomyApiSource) call,
  ) async {
    final remote = _remote;
    if (remote == null) throw _offline;
    final outcome = await call(remote);
    final box = await _openBox();
    await box.put(_kWelfare, outcome.status.toJson());
    return outcome;
  }

  // ── Crafting (D7) ─────────────────────────────────────────────────────────

  Future<List<CraftRecipe>> recipes() async {
    final remote = _remote;
    if (remote != null) {
      try {
        final recipes = await remote.listRecipes();
        await _cacheList(_kRecipes, recipes.map((r) => r.toJson()));
        return recipes;
      } on EconomyApiException {
        // fall through to cache
      }
    }
    return _readList(_kRecipes, CraftRecipe.fromJson);
  }

  Future<CraftOutcome> craft(String recipeId) async {
    final remote = _remote;
    if (remote == null) throw _offline;
    return remote.craft(recipeId);
  }

  // ── Cache helpers ─────────────────────────────────────────────────────────

  Future<void> _cacheList(String key, Iterable<Map<String, dynamic>> items) async {
    final box = await _openBox();
    await box.put(key, items.toList(growable: false));
  }

  Future<List<T>> _readList<T>(
    String key,
    T Function(Map<dynamic, dynamic>) fromJson,
  ) async {
    final box = await _openBox();
    final raw = box.get(key);
    if (raw is List) {
      return raw.whereType<Map>().map(fromJson).toList(growable: false);
    }
    return const [];
  }
}

final economyRepositoryProvider = Provider<EconomyRepository>((ref) {
  return EconomyRepository(remote: ref.watch(economyApiSourceProvider));
});
