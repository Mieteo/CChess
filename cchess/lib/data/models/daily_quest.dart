import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';

enum QuestKind {
  playGames,
  winGames,
  solvePuzzles,
  loginDay,
}

extension QuestKindX on QuestKind {
  IconData get icon {
    switch (this) {
      case QuestKind.playGames:
        return Icons.casino_outlined;
      case QuestKind.winGames:
        return Icons.emoji_events_outlined;
      case QuestKind.solvePuzzles:
        return Icons.extension_outlined;
      case QuestKind.loginDay:
        return Icons.calendar_today_outlined;
    }
  }

  String get statKey {
    switch (this) {
      case QuestKind.playGames:
        return 'gamesToday';
      case QuestKind.winGames:
        return 'winsToday';
      case QuestKind.solvePuzzles:
        return 'puzzlesToday';
      case QuestKind.loginDay:
        return 'loggedInToday';
    }
  }
}

class DailyQuest extends Equatable {
  final String id;
  final QuestKind kind;
  final String titleVi;
  final String descVi;
  final int target;
  final int rewardCoins;
  final int rewardGems;

  const DailyQuest({
    required this.id,
    required this.kind,
    required this.titleVi,
    required this.descVi,
    required this.target,
    required this.rewardCoins,
    this.rewardGems = 0,
  });

  @override
  List<Object?> get props =>
      [id, kind, titleVi, descVi, target, rewardCoins, rewardGems];
}

/// Daily progress for one user. Resets each calendar day.
class DailyQuestState extends Equatable {
  /// Calendar date this state covers (YYYY-MM-DD, local time).
  final String day;
  final int gamesPlayed;
  final int gamesWon;
  final int puzzlesSolved;
  final bool loggedIn;
  final Set<String> claimedQuestIds;

  const DailyQuestState({
    required this.day,
    this.gamesPlayed = 0,
    this.gamesWon = 0,
    this.puzzlesSolved = 0,
    this.loggedIn = true,
    this.claimedQuestIds = const {},
  });

  int progress(DailyQuest quest) {
    switch (quest.kind) {
      case QuestKind.playGames:
        return gamesPlayed;
      case QuestKind.winGames:
        return gamesWon;
      case QuestKind.solvePuzzles:
        return puzzlesSolved;
      case QuestKind.loginDay:
        return loggedIn ? 1 : 0;
    }
  }

  bool isComplete(DailyQuest quest) => progress(quest) >= quest.target;
  bool isClaimed(DailyQuest quest) => claimedQuestIds.contains(quest.id);

  DailyQuestState copyWith({
    String? day,
    int? gamesPlayed,
    int? gamesWon,
    int? puzzlesSolved,
    bool? loggedIn,
    Set<String>? claimedQuestIds,
  }) {
    return DailyQuestState(
      day: day ?? this.day,
      gamesPlayed: gamesPlayed ?? this.gamesPlayed,
      gamesWon: gamesWon ?? this.gamesWon,
      puzzlesSolved: puzzlesSolved ?? this.puzzlesSolved,
      loggedIn: loggedIn ?? this.loggedIn,
      claimedQuestIds: claimedQuestIds ?? this.claimedQuestIds,
    );
  }

  Map<String, dynamic> toJson() => {
        'day': day,
        'gamesPlayed': gamesPlayed,
        'gamesWon': gamesWon,
        'puzzlesSolved': puzzlesSolved,
        'loggedIn': loggedIn,
        'claimedQuestIds': claimedQuestIds.toList(),
      };

  factory DailyQuestState.fromJson(Map<dynamic, dynamic> json) {
    final claimedList = (json['claimedQuestIds'] as List?) ?? const [];
    return DailyQuestState(
      day: json['day'] as String,
      gamesPlayed: json['gamesPlayed'] as int? ?? 0,
      gamesWon: json['gamesWon'] as int? ?? 0,
      puzzlesSolved: json['puzzlesSolved'] as int? ?? 0,
      loggedIn: json['loggedIn'] as bool? ?? true,
      claimedQuestIds: claimedList.map((e) => e as String).toSet(),
    );
  }

  @override
  List<Object?> get props => [
        day,
        gamesPlayed,
        gamesWon,
        puzzlesSolved,
        loggedIn,
        claimedQuestIds,
      ];
}

/// Static daily quest list. Same 4 quests every day for MVP.
const List<DailyQuest> kDailyQuests = [
  DailyQuest(
    id: 'q_login',
    kind: QuestKind.loginDay,
    titleVi: 'Điểm danh',
    descVi: 'Mở app hôm nay.',
    target: 1,
    rewardCoins: 30,
  ),
  DailyQuest(
    id: 'q_play_1',
    kind: QuestKind.playGames,
    titleVi: 'Chơi 1 ván',
    descVi: 'Hoàn thành 1 ván cờ.',
    target: 1,
    rewardCoins: 50,
  ),
  DailyQuest(
    id: 'q_win_1',
    kind: QuestKind.winGames,
    titleVi: 'Thắng 1 ván',
    descVi: 'Giành chiến thắng trong 1 ván.',
    target: 1,
    rewardCoins: 100,
    rewardGems: 1,
  ),
  DailyQuest(
    id: 'q_puzzle_2',
    kind: QuestKind.solvePuzzles,
    titleVi: 'Giải 2 bài tập',
    descVi: 'Giải xong 2 bài tập tàn cục.',
    target: 2,
    rewardCoins: 60,
  ),
];
