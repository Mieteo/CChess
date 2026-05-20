import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../core/constants/app_constants.dart';
import '../models/game_record.dart';
import 'game_record_remote_repository.dart';

class GameHistoryRepository {
  GameHistoryRepository({GameRecordRemoteRepository? remote}) : _remote = remote;

  static const String _boxName = AppConstants.boxGameHistory;
  static const Uuid _uuid = Uuid();

  final GameRecordRemoteRepository? _remote;
  Box<dynamic>? _box;

  Future<Box<dynamic>> _openBox() async {
    final existing = _box;
    if (existing != null && existing.isOpen) return existing;
    final box = await Hive.openBox<dynamic>(_boxName);
    _box = box;
    return box;
  }

  /// Save a finished game locally and fire-and-forget push to cloud.
  Future<GameRecord> save(GameRecord record) async {
    final box = await _openBox();
    final id = record.id.isEmpty ? _uuid.v4() : record.id;
    final stored = GameRecord(
      id: id,
      opponentLabel: record.opponentLabel,
      mode: record.mode,
      humanColor: record.humanColor,
      startingFen: record.startingFen,
      moves: record.moves,
      result: record.result,
      endReason: record.endReason,
      eloDelta: record.eloDelta,
      duration: record.duration,
      endedAt: record.endedAt,
      isFavorite: record.isFavorite,
    );
    await box.put(id, stored.toJson());
    _remote?.pushGameRecord(stored).ignore();
    return stored;
  }

  /// All saved games, newest first.
  Future<List<GameRecord>> all() async {
    final box = await _openBox();
    final out = <GameRecord>[];
    for (final key in box.keys) {
      final raw = box.get(key);
      if (raw is Map) {
        out.add(GameRecord.fromJson(raw));
      }
    }
    out.sort((a, b) => b.endedAt.compareTo(a.endedAt));
    return out;
  }

  Future<GameRecord?> getById(String id) async {
    final box = await _openBox();
    final raw = box.get(id);
    return raw is Map ? GameRecord.fromJson(raw) : null;
  }

  Future<void> delete(String id) async {
    final box = await _openBox();
    await box.delete(id);
  }

  Future<void> toggleFavorite(String id) async {
    final current = await getById(id);
    if (current == null) return;
    final next = current.copyWith(isFavorite: !current.isFavorite);
    final box = await _openBox();
    await box.put(id, next.toJson());
    _remote?.updateFavorite(id, next.isFavorite).ignore();
  }

  Future<void> clear() async {
    final box = await _openBox();
    await box.clear();
  }
}

final gameHistoryRepositoryProvider = Provider<GameHistoryRepository>((ref) {
  return GameHistoryRepository(
    remote: ref.watch(gameRecordRemoteRepositoryProvider),
  );
});
