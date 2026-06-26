import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';
import 'calibration_runner.dart';

class CalibrationScreen extends StatefulWidget {
  const CalibrationScreen({super.key});

  @override
  State<CalibrationScreen> createState() => _CalibrationScreenState();
}

class _CalibrationScreenState extends State<CalibrationScreen> {
  CalibrationRunner? _runner;
  StreamSubscription<CalibrationEvent>? _sub;
  final List<String> _log = [];

  /// Accumulated result per pair index, so the table keeps every pair that
  /// has been run so far across separate button taps.
  final Map<int, PairResult> _results = {};
  double _progress = 0;

  /// Index of the pair currently running, or null when idle.
  int? _runningIndex;
  final ScrollController _scroll = ScrollController();

  bool get _running => _runningIndex != null;

  /// Results ordered by pair index for display / copy.
  List<PairResult> get _sortedResults {
    final keys = _results.keys.toList()..sort();
    return [for (final k in keys) _results[k]!];
  }

  void _startPair(int index) {
    // Guard against parallel runs — only one match at a time on a phone CPU.
    if (_running) return;

    setState(() {
      _runningIndex = index;
      _progress = 0;
    });

    final runner = CalibrationRunner();
    _runner = runner;
    _sub = runner.runPair(index).listen(
      (event) {
        if (!mounted) return;
        setState(() {
          _log.add(event.log);
          _results[index] = event.result;
          _progress = event.progress;
          if (event.done) _runningIndex = null;
        });
        // Auto-scroll log to bottom.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scroll.hasClients) {
            _scroll.animateTo(
              _scroll.position.maxScrollExtent,
              duration: const Duration(milliseconds: 150),
              curve: Curves.easeOut,
            );
          }
        });
      },
      onError: (Object e) {
        if (!mounted) return;
        setState(() {
          _log.add('❌ Lỗi: $e');
          _runningIndex = null;
        });
      },
    );
  }

  void _stop() {
    _runner?.cancel();
    _sub?.cancel();
    setState(() => _runningIndex = null);
  }

  void _copyResults() {
    final buf = StringBuffer('CChess Bot ELO Calibration\n');
    buf.writeln('Zone A · 6 ván/cặp · local engine only\n');
    buf.writeln('ELO thấp | ELO cao | Thắng | Thua | Hòa | Win%');
    buf.writeln('─' * 55);
    for (final r in _sortedResults) {
      final pct = r.total == 0
          ? '–'
          : '${(r.lowerWinRate * 100).toStringAsFixed(1)}%';
      buf.writeln(
        '${r.lowerElo.toString().padRight(9)}'
        '${r.higherElo.toString().padRight(9)}'
        '${r.lowerWins.toString().padRight(7)}'
        '${r.higherWins.toString().padRight(6)}'
        '${r.draws.toString().padRight(5)}'
        '$pct',
      );
    }
    Clipboard.setData(ClipboardData(text: buf.toString()));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Đã copy kết quả vào clipboard'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  @override
  void dispose() {
    _sub?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.woodDark,
        title: const Text('Bot ELO Calibration'),
        actions: [
          if (_results.isNotEmpty && !_running)
            IconButton(
              icon: const Icon(Icons.copy_outlined),
              onPressed: _copyResults,
              tooltip: 'Copy kết quả',
            ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _InfoCard(),
            const SizedBox(height: 12),
            if (_running) ...[
              LinearProgressIndicator(
                value: _progress,
                backgroundColor: const Color(0xFF333333),
                valueColor: const AlwaysStoppedAnimation(Color(0xFFEFBC97)),
                minHeight: 6,
              ),
              const SizedBox(height: 4),
              Text(
                'Đang chạy cặp ${kCalibrationPairs[_runningIndex!].label}'
                ' · ${(_progress * 100).toStringAsFixed(0)}%',
                style: AppTextStyles.captionSm
                    .copyWith(color: const Color(0xFF888888)),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),
            ],
            _PairButtonsGrid(
              runningIndex: _runningIndex,
              results: _results,
              onStart: _startPair,
              onStop: _stop,
            ),
            if (_results.isNotEmpty) ...[
              const SizedBox(height: 12),
              _ResultsTable(results: _sortedResults),
            ],
            const SizedBox(height: 12),
            Expanded(child: _LogView(scroll: _scroll, log: _log)),
          ],
        ),
      ),
    );
  }
}

/// A 2-column grid of one button per ELO pair.
///
/// While any pair is running, every other button is disabled so two matches
/// never compete for the phone's CPU. The running button turns into a stop
/// button; finished pairs show a check + win%.
class _PairButtonsGrid extends StatelessWidget {
  final int? runningIndex;
  final Map<int, PairResult> results;
  final void Function(int index) onStart;
  final VoidCallback onStop;

  const _PairButtonsGrid({
    required this.runningIndex,
    required this.results,
    required this.onStart,
    required this.onStop,
  });

  @override
  Widget build(BuildContext context) {
    const spacing = 8.0;
    return LayoutBuilder(
      builder: (context, constraints) {
        final tileWidth = (constraints.maxWidth - spacing) / 2;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (int i = 0; i < kCalibrationPairs.length; i++)
              SizedBox(
                width: tileWidth,
                child: _pairButton(i),
              ),
          ],
        );
      },
    );
  }

  Widget _pairButton(int index) {
    final pair = kCalibrationPairs[index];
    final result = results[index];
    final hasResult = result != null && result.total > 0;
    final isThisRunning = runningIndex == index;
    final otherRunning = runningIndex != null && !isThisRunning;

    // Leading icon reflects state.
    Widget leading;
    Color accent;
    if (isThisRunning) {
      accent = Colors.red[300]!;
      leading = const SizedBox(
        width: 14,
        height: 14,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          valueColor: AlwaysStoppedAnimation(Colors.white),
        ),
      );
    } else if (hasResult) {
      accent = _winRateColor(result.lowerWinRate);
      leading = Icon(Icons.check_circle, size: 16, color: accent);
    } else {
      accent = const Color(0xFFEFBC97);
      leading = Icon(Icons.play_arrow, size: 16, color: accent);
    }

    final trailing = isThisRunning
        ? 'dừng'
        : hasResult
        ? '${(result.lowerWinRate * 100).toStringAsFixed(0)}%'
        : null;

    return FilledButton(
      onPressed: isThisRunning
          ? onStop
          : otherRunning
          ? null
          : () => onStart(index),
      style: FilledButton.styleFrom(
        backgroundColor: isThisRunning
            ? Colors.red[700]
            : const Color(0xFF3A2A1A),
        disabledBackgroundColor: const Color(0xFF262626),
        foregroundColor: Colors.white,
        disabledForegroundColor: const Color(0xFF666666),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        alignment: Alignment.centerLeft,
        side: hasResult && !isThisRunning
            ? BorderSide(color: accent.withValues(alpha: 0.5))
            : BorderSide.none,
      ),
      child: Row(
        children: [
          leading,
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              pair.label,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 4),
            Text(
              trailing,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: isThisRunning ? Colors.white : accent,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Color _winRateColor(double rate) {
    if (rate > 0.50) return Colors.red[300]!;
    if (rate > 0.35) return Colors.orange[300]!;
    return Colors.green[400]!;
  }
}

class _InfoCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF2A2A2A),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF3A3A3A)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '7 cặp adjacent · Zone A (1000–1900) · offline',
            style: AppTextStyles.bodyMd.copyWith(
              fontWeight: FontWeight.bold,
              color: const Color(0xFFEFBC97),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '6 ván/cặp (3 đỏ + 3 đen) · ~7–10 phút/cặp · chạy từng cặp một',
            style: AppTextStyles.captionSm.copyWith(color: const Color(0xFF888888)),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              const Icon(Icons.warning_amber_rounded,
                  size: 13, color: Colors.orange),
              const SizedBox(width: 4),
              Text(
                'Chạy với --release để đo đúng tốc độ minimax',
                style: AppTextStyles.captionSm.copyWith(color: Colors.orange[300]),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              const Icon(Icons.wifi_off, size: 13, color: Color(0xFF888888)),
              const SizedBox(width: 4),
              Text(
                'Không dùng Pikafish — không tốn quota',
                style: AppTextStyles.captionSm.copyWith(
                  color: const Color(0xFF888888),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LogView extends StatelessWidget {
  final ScrollController scroll;
  final List<String> log;

  const _LogView({required this.scroll, required this.log});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF0F0F0F),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF2A2A2A)),
      ),
      child: log.isEmpty
          ? Center(
              child: Text(
                'Chọn một cặp ELO để bắt đầu chạy…',
                style: AppTextStyles.captionSm
                    .copyWith(color: const Color(0xFF555555)),
              ),
            )
          : ListView.builder(
              controller: scroll,
              itemCount: log.length,
              itemBuilder: (_, i) => Text(
                log[i],
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11,
                  color: Color(0xFFCCCCCC),
                  height: 1.5,
                ),
              ),
            ),
    );
  }
}

class _ResultsTable extends StatelessWidget {
  final List<PairResult> results;

  const _ResultsTable({required this.results});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF333333)),
      ),
      child: Column(
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            child: Row(
              children: [
                _cell('Cặp ELO', flex: 3, muted: true),
                _cell('W', muted: true),
                _cell('L', muted: true),
                _cell('D', muted: true),
                _cell('Win%', flex: 2, muted: true),
                _cell('Đánh giá', flex: 3, muted: true),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFF333333)),
          ...results.map((r) {
            final pct = r.total == 0 ? '–' : '${(r.lowerWinRate * 100).toStringAsFixed(0)}%';
            final color = _winRateColor(r.lowerWinRate, r.total);
            final label = _diagnose(r);
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  child: Row(
                    children: [
                      _cell('${r.lowerElo}→${r.higherElo}', flex: 3),
                      _cell('${r.lowerWins}'),
                      _cell('${r.higherWins}'),
                      _cell('${r.draws}'),
                      Expanded(
                        flex: 2,
                        child: Text(
                          pct,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: color,
                          ),
                        ),
                      ),
                      Expanded(
                        flex: 3,
                        child: Text(
                          label,
                          style: TextStyle(fontSize: 10, color: color),
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1, color: Color(0xFF282828)),
              ],
            );
          }),
          // Legend
          Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _legend(Colors.green[400]!, '< 35% OK'),
                const SizedBox(width: 12),
                _legend(Colors.orange[300]!, '35-50% gap nhỏ'),
                const SizedBox(width: 12),
                _legend(Colors.red[300]!, '> 50% đảo ngược'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _legend(Color color, String label) => Row(
        children: [
          Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(fontSize: 9, color: color)),
        ],
      );

  Color _winRateColor(double rate, int total) {
    if (total == 0) return const Color(0xFF666666);
    if (rate > 0.50) return Colors.red[300]!;
    if (rate > 0.35) return Colors.orange[300]!;
    return Colors.green[400]!;
  }

  String _diagnose(PairResult r) {
    if (r.total == 0) return '…';
    if (r.lowerWinRate > 0.5) return 'đảo ngược!';
    if (r.lowerWinRate > 0.35) return 'gap quá nhỏ';
    return 'OK';
  }

  Widget _cell(String text, {int flex = 1, bool muted = false}) => Expanded(
        flex: flex,
        child: Text(
          text,
          style: TextStyle(
            fontSize: 11,
            color: muted
                ? const Color(0xFF666666)
                : const Color(0xFFCCCCCC),
          ),
        ),
      );
}
