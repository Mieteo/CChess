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
  List<PairResult> _results = [];
  double _progress = 0;
  bool _running = false;
  bool _done = false;
  final ScrollController _scroll = ScrollController();

  void _start() {
    setState(() {
      _log.clear();
      _results = [];
      _progress = 0;
      _running = true;
      _done = false;
    });

    final runner = CalibrationRunner();
    _runner = runner;
    _sub = runner.run().listen(
      (event) {
        if (!mounted) return;
        setState(() {
          _log.add(event.log);
          _results = event.results;
          _progress = event.progress;
          if (event.done) {
            _running = false;
            _done = true;
          }
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
          _running = false;
        });
      },
    );
  }

  void _stop() {
    _runner?.cancel();
    _sub?.cancel();
    setState(() => _running = false);
  }

  void _copyResults() {
    final buf = StringBuffer('CChess Bot ELO Calibration\n');
    buf.writeln('Zone A · 6 ván/cặp · local engine only\n');
    buf.writeln('ELO thấp | ELO cao | Thắng | Thua | Hòa | Win%');
    buf.writeln('─' * 55);
    for (final r in _results) {
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
          if (_done)
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
            if (_running || _done) ...[
              LinearProgressIndicator(
                value: _progress,
                backgroundColor: const Color(0xFF333333),
                valueColor: const AlwaysStoppedAnimation(Color(0xFFEFBC97)),
                minHeight: 6,
              ),
              const SizedBox(height: 4),
              Text(
                '${(_progress * 100).toStringAsFixed(0)}% hoàn thành',
                style: AppTextStyles.captionSm
                    .copyWith(color: const Color(0xFF888888)),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),
            ],
            FilledButton.icon(
              onPressed: _running ? _stop : _start,
              icon: Icon(_running ? Icons.stop : Icons.play_arrow),
              label: Text(
                _running ? 'Dừng lại' : 'Bắt đầu Calibration',
              ),
              style: FilledButton.styleFrom(
                backgroundColor:
                    _running ? Colors.red[700] : const Color(0xFF5C3A1E),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
            if (_results.isNotEmpty) ...[
              const SizedBox(height: 12),
              _ResultsTable(results: _results),
            ],
            const SizedBox(height: 12),
            Expanded(child: _LogView(scroll: _scroll, log: _log)),
          ],
        ),
      ),
    );
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
            '6 ván/cặp (3 đỏ + 3 đen) · tối đa 42 ván · ~45–70 phút',
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
                'Nhấn "Bắt đầu Calibration" để chạy…',
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
