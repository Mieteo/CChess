import 'package:equatable/equatable.dart';

/// Local app-level preferences persisted in Hive.
class AppSettings extends Equatable {
  final bool soundEnabled;
  final bool musicEnabled;
  final bool vibrationEnabled;
  final bool showLegalMoveDots;
  final bool defaultBoardFlipped;
  final bool darkMode;
  final int dailyHintsLimit;

  /// 0 = unlimited daily play time, otherwise minutes per day.
  final int healthyGamingMinutes;

  /// "vi" or "en". Currently only Vietnamese is shipped.
  final String languageCode;

  const AppSettings({
    this.soundEnabled = true,
    this.musicEnabled = true,
    this.vibrationEnabled = true,
    this.showLegalMoveDots = true,
    this.defaultBoardFlipped = false,
    this.darkMode = true,
    this.dailyHintsLimit = 3,
    this.healthyGamingMinutes = 0,
    this.languageCode = 'vi',
  });

  AppSettings copyWith({
    bool? soundEnabled,
    bool? musicEnabled,
    bool? vibrationEnabled,
    bool? showLegalMoveDots,
    bool? defaultBoardFlipped,
    bool? darkMode,
    int? dailyHintsLimit,
    int? healthyGamingMinutes,
    String? languageCode,
  }) {
    return AppSettings(
      soundEnabled: soundEnabled ?? this.soundEnabled,
      musicEnabled: musicEnabled ?? this.musicEnabled,
      vibrationEnabled: vibrationEnabled ?? this.vibrationEnabled,
      showLegalMoveDots: showLegalMoveDots ?? this.showLegalMoveDots,
      defaultBoardFlipped: defaultBoardFlipped ?? this.defaultBoardFlipped,
      darkMode: darkMode ?? this.darkMode,
      dailyHintsLimit: dailyHintsLimit ?? this.dailyHintsLimit,
      healthyGamingMinutes: healthyGamingMinutes ?? this.healthyGamingMinutes,
      languageCode: languageCode ?? this.languageCode,
    );
  }

  Map<String, dynamic> toJson() => {
        'soundEnabled': soundEnabled,
        'musicEnabled': musicEnabled,
        'vibrationEnabled': vibrationEnabled,
        'showLegalMoveDots': showLegalMoveDots,
        'defaultBoardFlipped': defaultBoardFlipped,
        'darkMode': darkMode,
        'dailyHintsLimit': dailyHintsLimit,
        'healthyGamingMinutes': healthyGamingMinutes,
        'languageCode': languageCode,
      };

  factory AppSettings.fromJson(Map<dynamic, dynamic> json) {
    return AppSettings(
      soundEnabled: json['soundEnabled'] as bool? ?? true,
      musicEnabled: json['musicEnabled'] as bool? ?? true,
      vibrationEnabled: json['vibrationEnabled'] as bool? ?? true,
      showLegalMoveDots: json['showLegalMoveDots'] as bool? ?? true,
      defaultBoardFlipped: json['defaultBoardFlipped'] as bool? ?? false,
      darkMode: json['darkMode'] as bool? ?? true,
      dailyHintsLimit: json['dailyHintsLimit'] as int? ?? 3,
      healthyGamingMinutes: json['healthyGamingMinutes'] as int? ?? 0,
      languageCode: json['languageCode'] as String? ?? 'vi',
    );
  }

  @override
  List<Object?> get props => [
        soundEnabled,
        musicEnabled,
        vibrationEnabled,
        showLegalMoveDots,
        defaultBoardFlipped,
        darkMode,
        dailyHintsLimit,
        healthyGamingMinutes,
        languageCode,
      ];
}
