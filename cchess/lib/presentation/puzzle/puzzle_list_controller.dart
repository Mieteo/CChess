import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/datasources/remote/remote_puzzle_source.dart';
import '../../data/models/chess_puzzle.dart';
import '../../data/repositories/puzzle_repository.dart';

/// A selectable category for the list filter chips. `key == null` is the
/// "Tất cả" (all) chip; the other keys mirror the backend `category` buckets.
class PuzzleCategory {
  final String? key;
  final String label;
  const PuzzleCategory(this.key, this.label);
}

/// Curated category chips. The keys match the coarse `category` buckets the
/// backend filters on (see `ChessPuzzle.category`). "Tất cả" clears the filter
/// so the offline seed catalog (which has no category) still shows.
const List<PuzzleCategory> kPuzzleCategories = [
  PuzzleCategory(null, 'Tất cả'),
  PuzzleCategory('checkmate_1', 'Chiếu hết 1'),
  PuzzleCategory('checkmate_2', 'Chiếu hết 2'),
  PuzzleCategory('capture', 'Bắt quân'),
  PuzzleCategory('defense', 'Phòng thủ'),
  PuzzleCategory('tactic', 'Chiến thuật'),
  PuzzleCategory('endgame', 'Tàn cục'),
];

const int _pageSize = 20;
const Object _keep = Object();

/// State for the paginated, filterable puzzle list.
class PuzzleListState {
  final List<ChessPuzzle> puzzles;
  final Map<String, PuzzleProgress> progress;

  /// True while the first page is loading (shows a full-screen spinner).
  final bool isLoading;

  /// True while a subsequent page is being appended.
  final bool isLoadingMore;

  final bool hasMore;
  final String? nextCursor;
  final Object? error;

  // Active filters.
  final String? category;
  final int? difficulty;
  final PuzzleSort sort;

  const PuzzleListState({
    this.puzzles = const [],
    this.progress = const {},
    this.isLoading = true,
    this.isLoadingMore = false,
    this.hasMore = false,
    this.nextCursor,
    this.error,
    this.category,
    this.difficulty,
    this.sort = PuzzleSort.newest,
  });

  int get solvedCount => progress.values.where((p) => p.solved).length;

  PuzzleListState copyWith({
    List<ChessPuzzle>? puzzles,
    Map<String, PuzzleProgress>? progress,
    bool? isLoading,
    bool? isLoadingMore,
    bool? hasMore,
    Object? nextCursor = _keep,
    Object? error = _keep,
    Object? category = _keep,
    Object? difficulty = _keep,
    PuzzleSort? sort,
  }) {
    return PuzzleListState(
      puzzles: puzzles ?? this.puzzles,
      progress: progress ?? this.progress,
      isLoading: isLoading ?? this.isLoading,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      hasMore: hasMore ?? this.hasMore,
      nextCursor:
          identical(nextCursor, _keep) ? this.nextCursor : nextCursor as String?,
      error: identical(error, _keep) ? this.error : error,
      category:
          identical(category, _keep) ? this.category : category as String?,
      difficulty:
          identical(difficulty, _keep) ? this.difficulty : difficulty as int?,
      sort: sort ?? this.sort,
    );
  }
}

class PuzzleListController extends StateNotifier<PuzzleListState> {
  final PuzzleRepository _repo;

  PuzzleListController(this._repo) : super(const PuzzleListState()) {
    load();
  }

  /// (Re)load the first page with the current filters.
  Future<void> load() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final page = await _repo.fetchPuzzles(
        limit: _pageSize,
        difficulty: state.difficulty,
        category: state.category,
        sort: state.sort,
      );
      final progress =
          await _repo.getProgressForIds(page.puzzles.map((p) => p.id));
      if (!mounted) return;
      state = state.copyWith(
        puzzles: page.puzzles,
        progress: progress,
        hasMore: page.hasMore,
        nextCursor: page.nextCursor,
        isLoading: false,
        error: null,
      );
    } catch (e) {
      if (!mounted) return;
      state = state.copyWith(isLoading: false, error: e);
    }
  }

  /// Append the next page if there is one.
  Future<void> loadMore() async {
    if (state.isLoadingMore || state.isLoading || !state.hasMore) return;
    if (state.nextCursor == null) return;
    state = state.copyWith(isLoadingMore: true);
    try {
      final page = await _repo.fetchPuzzles(
        limit: _pageSize,
        cursor: state.nextCursor,
        difficulty: state.difficulty,
        category: state.category,
        sort: state.sort,
      );
      final more =
          await _repo.getProgressForIds(page.puzzles.map((p) => p.id));
      if (!mounted) return;
      state = state.copyWith(
        puzzles: [...state.puzzles, ...page.puzzles],
        progress: {...state.progress, ...more},
        hasMore: page.hasMore,
        nextCursor: page.nextCursor,
        isLoadingMore: false,
      );
    } catch (_) {
      if (!mounted) return;
      // Keep what we have; just stop the spinner.
      state = state.copyWith(isLoadingMore: false, hasMore: false);
    }
  }

  void setCategory(String? category) {
    if (category == state.category) return;
    state = state.copyWith(category: category);
    load();
  }

  void setDifficulty(int? difficulty) {
    if (difficulty == state.difficulty) return;
    state = state.copyWith(difficulty: difficulty);
    load();
  }

  void setSort(PuzzleSort sort) {
    if (sort == state.sort) return;
    state = state.copyWith(sort: sort);
    load();
  }

  Future<void> refresh() => load();
}

final puzzleListControllerProvider = StateNotifierProvider.autoDispose<
    PuzzleListController, PuzzleListState>((ref) {
  return PuzzleListController(ref.watch(puzzleRepositoryProvider));
});

/// The featured daily puzzle (backend → seed default). Refreshed when the
/// screen is reopened.
final dailyPuzzleProvider =
    FutureProvider.autoDispose<ChessPuzzle?>((ref) {
  return ref.watch(puzzleRepositoryProvider).fetchDailyPuzzle();
});
