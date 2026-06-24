import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../core/constants/app_constants.dart';
import '../datasources/local/puzzle_seed.dart';
import '../datasources/remote/puzzle_api_transport.dart';
import '../datasources/remote/remote_puzzle_source.dart';
import '../models/chess_puzzle.dart';
import '../models/puzzle_stats.dart';

/// Repository combining the backend puzzle catalog with the built-in seed and
/// locally persisted per-user progress.
///
/// Reads prefer the remote API ([RemotePuzzleSource]) and fall back to a Hive
/// cache of the last successful fetch, then to the in-code [seedPuzzles] when
/// offline. Progress lives in a Hive box keyed by puzzle id and is mirrored to
/// the backend (best-effort) when the user is signed in.
///
/// The synchronous seed-based accessors ([allPuzzles], [filteredPuzzles],
/// [puzzleById], [dailyPuzzle]) remain for callers that have not yet migrated
/// to the async remote-backed flow.
class PuzzleRepository {
  PuzzleRepository({RemotePuzzleSource? remote}) : _remote = remote;

  final RemotePuzzleSource? _remote;

  static const String _progressBoxName = AppConstants.boxPuzzleProgress;
  static const String _cacheBoxName = AppConstants.boxPuzzleCache;

  Box<dynamic>? _progressBox;
  Box<dynamic>? _cacheBox;

  Future<Box<dynamic>> _openProgressBox() =>
      _openBox(_progressBoxName, (b) => _progressBox = b, () => _progressBox);

  Future<Box<dynamic>> _openCacheBox() =>
      _openBox(_cacheBoxName, (b) => _cacheBox = b, () => _cacheBox);

  Future<Box<dynamic>> _openBox(
    String name,
    void Function(Box<dynamic>) store,
    Box<dynamic>? Function() current,
  ) async {
    final existing = current();
    if (existing != null && existing.isOpen) return existing;
    final box = await Hive.openBox<dynamic>(name);
    store(box);
    return box;
  }

  // ── Synchronous seed catalog (legacy / offline-only callers) ──────────────

  /// The built-in seed catalog. Always available offline.
  List<ChessPuzzle> allPuzzles() => List.unmodifiable(seedPuzzles);

  List<String> availableTags() {
    final tags = <String>{};
    for (final puzzle in seedPuzzles) {
      tags.addAll(puzzle.tags);
    }
    final sorted = tags.toList()..sort();
    return List.unmodifiable(sorted);
  }

  List<ChessPuzzle> filteredPuzzles({String? tag, int? difficulty}) {
    return List.unmodifiable(
      _filter(seedPuzzles, tag: tag, difficulty: difficulty),
    );
  }

  ChessPuzzle? dailyPuzzle() {
    if (seedPuzzles.isEmpty) return null;
    return puzzleById('p003') ?? seedPuzzles.first;
  }

  ChessPuzzle? puzzleById(String id) {
    for (final p in seedPuzzles) {
      if (p.id == id) return p;
    }
    return null;
  }

  // ── Remote-backed catalog (with cache + seed fallback) ────────────────────

  /// Fetch a page of puzzles from the backend, caching results for offline use.
  /// On any network error, returns a single page built from the local catalog
  /// (cache merged with seed) filtered client-side.
  Future<PuzzlePage> fetchPuzzles({
    int limit = 20,
    String? cursor,
    int? difficulty,
    String? category,
    String? theme,
    String? tag,
    PuzzleSort sort = PuzzleSort.newest,
  }) async {
    final remote = _remote;
    if (remote != null) {
      try {
        final page = await remote.list(
          limit: limit,
          cursor: cursor,
          difficulty: difficulty,
          category: category,
          theme: theme,
          tag: tag,
          sort: sort,
        );
        await _cachePuzzles(page.puzzles);
        return page;
      } on PuzzleApiException {
        // fall through to local fallback
      }
    }
    final local = await _localCatalog();
    final filtered = _filter(
      local,
      tag: tag,
      difficulty: difficulty,
      category: category,
      theme: theme,
    );
    _sortInPlace(filtered, sort);
    return PuzzlePage(
      puzzles: List.unmodifiable(filtered),
      hasMore: false,
      nextCursor: null,
    );
  }

  /// Resolve one puzzle: backend → cache → seed.
  Future<ChessPuzzle?> fetchPuzzleById(String id) async {
    final remote = _remote;
    if (remote != null) {
      try {
        final puzzle = await remote.getById(id);
        if (puzzle != null) {
          await _cachePuzzles([puzzle]);
          return puzzle;
        }
      } on PuzzleApiException {
        // fall through to cache / seed
      }
    }
    return (await _cachedById(id)) ?? puzzleById(id);
  }

  /// Resolve the daily puzzle: backend → seed default.
  Future<ChessPuzzle?> fetchDailyPuzzle({String? date}) async {
    final remote = _remote;
    if (remote != null) {
      try {
        final puzzle = await remote.daily(date: date);
        if (puzzle != null) {
          await _cachePuzzles([puzzle]);
          return puzzle;
        }
      } on PuzzleApiException {
        // fall through to seed
      }
    }
    return dailyPuzzle();
  }

  /// Cache merged with seed, de-duplicated by id (cache wins — it is fresher).
  Future<List<ChessPuzzle>> _localCatalog() async {
    final byId = <String, ChessPuzzle>{};
    for (final p in seedPuzzles) {
      byId[p.id] = p;
    }
    for (final p in await cachedPuzzles()) {
      byId[p.id] = p;
    }
    return byId.values.toList(growable: false);
  }

  /// All puzzles previously fetched from the backend and cached locally.
  Future<List<ChessPuzzle>> cachedPuzzles() async {
    final box = await _openCacheBox();
    final out = <ChessPuzzle>[];
    for (final raw in box.values) {
      if (raw is Map) out.add(ChessPuzzle.fromJson(raw));
    }
    return out;
  }

  Future<ChessPuzzle?> _cachedById(String id) async {
    final box = await _openCacheBox();
    final raw = box.get(id);
    return raw is Map ? ChessPuzzle.fromJson(raw) : null;
  }

  Future<void> _cachePuzzles(Iterable<ChessPuzzle> puzzles) async {
    if (puzzles.isEmpty) return;
    final box = await _openCacheBox();
    for (final p in puzzles) {
      if (p.id.isEmpty) continue;
      await box.put(p.id, p.toJson());
    }
  }

  // ── Progress (local source of truth + best-effort remote mirror) ──────────

  /// Read the progress entry for a puzzle, or a default "not attempted yet".
  Future<PuzzleProgress> getProgress(String puzzleId) async {
    final box = await _openProgressBox();
    final raw = box.get(puzzleId);
    if (raw is Map) {
      return PuzzleProgress.fromJson(raw);
    }
    return PuzzleProgress(puzzleId: puzzleId);
  }

  /// Bulk fetch over the seed catalog — kept for legacy callers (achievements).
  Future<Map<String, PuzzleProgress>> getAllProgress() async {
    final box = await _openProgressBox();
    final map = <String, PuzzleProgress>{};
    for (final p in seedPuzzles) {
      final raw = box.get(p.id);
      map[p.id] =
          raw is Map ? PuzzleProgress.fromJson(raw) : PuzzleProgress(puzzleId: p.id);
    }
    return map;
  }

  /// Progress for an explicit set of puzzle ids — used by the remote-backed
  /// list screen, which doesn't know its puzzles ahead of time. Missing ids map
  /// to a default "not attempted yet" entry.
  Future<Map<String, PuzzleProgress>> getProgressForIds(
    Iterable<String> ids,
  ) async {
    final box = await _openProgressBox();
    final map = <String, PuzzleProgress>{};
    for (final id in ids) {
      final raw = box.get(id);
      map[id] = raw is Map
          ? PuzzleProgress.fromJson(raw)
          : PuzzleProgress(puzzleId: id);
    }
    return map;
  }

  /// Aggregate the entire progress box (joined against the local catalog for
  /// difficulty buckets) into a single [PuzzleStats] for the stats screen.
  Future<PuzzleStats> computeStats() async {
    final box = await _openProgressBox();
    final catalog = {for (final p in await _localCatalog()) p.id: p};

    var attempted = 0;
    var solved = 0;
    var totalAttempts = 0;
    var totalHints = 0;
    var bestScoreSum = 0;
    var scoredCount = 0;
    // difficulty -> [solved, attempted]
    final diff = <int, List<int>>{};

    for (final raw in box.values) {
      if (raw is! Map) continue;
      final p = PuzzleProgress.fromJson(raw);
      if (p.attempts <= 0 && !p.solved) continue;
      attempted++;
      totalAttempts += p.attempts;
      totalHints += p.hintsUsed;
      if (p.solved) solved++;
      if (p.bestScore > 0) {
        bestScoreSum += p.bestScore;
        scoredCount++;
      }
      final d = catalog[p.puzzleId]?.difficulty ?? 0;
      final slot = diff.putIfAbsent(d, () => [0, 0]);
      slot[1] += 1;
      if (p.solved) slot[0] += 1;
    }

    final buckets = diff.entries
        .map((e) => DifficultyStat(
              difficulty: e.key,
              solved: e.value[0],
              attempted: e.value[1],
            ))
        .toList()
      ..sort((a, b) => a.difficulty.compareTo(b.difficulty));

    return PuzzleStats(
      attempted: attempted,
      solved: solved,
      catalogSize: catalog.length,
      totalAttempts: totalAttempts,
      totalHints: totalHints,
      bestScoreSum: bestScoreSum,
      scoredCount: scoredCount,
      byDifficulty: buckets,
    );
  }

  Future<void> saveProgress(PuzzleProgress progress) async {
    final box = await _openProgressBox();
    await box.put(progress.puzzleId, progress.toJson());
  }

  /// Increment attempt counter, persist locally, and (best-effort) mirror to
  /// the backend. Returns the locally-stored value immediately so callers stay
  /// responsive offline; the server-authoritative `bestScore` is merged into
  /// the cache in the background when the sync succeeds.
  Future<PuzzleProgress> recordAttempt(
    String puzzleId, {
    bool solved = false,
    int hintsUsed = 0,
    int score = 0,
    bool mirror = true,
  }) async {
    final current = await getProgress(puzzleId);
    final updated = current.copyWith(
      attempts: current.attempts + 1,
      hintsUsed: current.hintsUsed + (hintsUsed > 0 ? hintsUsed : 0),
      solved: current.solved || solved,
      bestScore: score > current.bestScore ? score : current.bestScore,
      solvedAt: solved && !current.solved ? DateTime.now() : current.solvedAt,
    );
    await saveProgress(updated);

    // Mirror to the backend without blocking the caller (offline-safe). Callers
    // that follow up with an awaited [syncProgress] pass `mirror: false` to
    // avoid a duplicate POST.
    if (mirror) {
      _mirrorProgress(
        puzzleId,
        solved: updated.solved,
        hintsUsed: hintsUsed > 0 ? hintsUsed : 0,
        score: score,
      );
    }

    return updated;
  }

  /// Push an attempt to the backend and merge the authoritative result into the
  /// local store. Awaited variant of the mirror used by [recordAttempt]; safe
  /// to call directly when the caller wants the merged progress back. Returns
  /// the local progress unchanged when the user is offline / signed out.
  Future<PuzzleProgress> syncProgress(
    String puzzleId, {
    required bool solved,
    int hintsUsed = 0,
    int score = 0,
  }) async {
    final remote = _remote;
    if (remote == null) return getProgress(puzzleId);
    try {
      final server = await remote.reportProgress(
        puzzleId,
        solved: solved,
        hintsUsed: hintsUsed,
        score: score,
      );
      return _mergeServerProgress(puzzleId, server);
    } on PuzzleApiException {
      return getProgress(puzzleId);
    }
  }

  void _mirrorProgress(
    String puzzleId, {
    required bool solved,
    required int hintsUsed,
    required int score,
  }) {
    final remote = _remote;
    if (remote == null) return;
    remote
        .reportProgress(puzzleId, solved: solved, hintsUsed: hintsUsed, score: score)
        .then((server) => _mergeServerProgress(puzzleId, server))
        .ignore();
  }

  /// Adopt the server-authoritative `solved` / `bestScore` into the local entry
  /// (never lowers either). Local attempt/hint counters stay as-is — they are
  /// the offline-authoritative counters.
  Future<PuzzleProgress> _mergeServerProgress(
    String puzzleId,
    PuzzleProgress server,
  ) async {
    final local = await getProgress(puzzleId);
    final merged = local.copyWith(
      solved: local.solved || server.solved,
      bestScore: server.bestScore > local.bestScore
          ? server.bestScore
          : local.bestScore,
      solvedAt: local.solvedAt ?? server.solvedAt,
    );
    if (merged != local) {
      await saveProgress(merged);
    }
    return merged;
  }

  // ── Filtering / sorting helpers ───────────────────────────────────────────

  List<ChessPuzzle> _filter(
    List<ChessPuzzle> source, {
    String? tag,
    int? difficulty,
    String? category,
    String? theme,
  }) {
    final selectedTag = tag?.trim();
    final selectedCategory = category?.trim();
    final selectedTheme = theme?.trim();
    return source.where((puzzle) {
      final matchesTag = selectedTag == null ||
          selectedTag.isEmpty ||
          puzzle.tags.contains(selectedTag);
      final matchesDifficulty =
          difficulty == null || puzzle.difficulty == difficulty;
      final matchesCategory = selectedCategory == null ||
          selectedCategory.isEmpty ||
          puzzle.category == selectedCategory;
      final matchesTheme = selectedTheme == null ||
          selectedTheme.isEmpty ||
          puzzle.theme == selectedTheme;
      return matchesTag && matchesDifficulty && matchesCategory && matchesTheme;
    }).toList();
  }

  void _sortInPlace(List<ChessPuzzle> puzzles, PuzzleSort sort) {
    switch (sort) {
      case PuzzleSort.hardest:
        puzzles.sort((a, b) => b.difficulty.compareTo(a.difficulty));
      case PuzzleSort.easiest:
        puzzles.sort((a, b) => a.difficulty.compareTo(b.difficulty));
      case PuzzleSort.newest:
        break; // preserve source order
    }
  }
}

final puzzleRepositoryProvider = Provider<PuzzleRepository>((ref) {
  return PuzzleRepository(remote: ref.watch(remotePuzzleSourceProvider));
});
