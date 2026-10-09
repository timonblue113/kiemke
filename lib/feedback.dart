import 'dart:math';
import 'dart:typed_data';
import 'package:audioplayers/audioplayers.dart';
import 'package:vibration/vibration.dart';

/// Tạo file WAV (PCM 16-bit mono) gồm các nốt, mỗi nốt tắt dần -> tiếng "ting".
Uint8List _makeWav(List<double> freqs, int msEach) {
  const sr = 44100;
  final per = sr * msEach ~/ 1000;
  final n = per * freqs.length;
  final d = ByteData(44 + n * 2);
  void tag(int o, String t) {
    for (var i = 0; i < t.length; i++) {
      d.setUint8(o + i, t.codeUnitAt(i));
    }
  }

  tag(0, 'RIFF');
  d.setUint32(4, 36 + n * 2, Endian.little);
  tag(8, 'WAVE');
  tag(12, 'fmt ');
  d.setUint32(16, 16, Endian.little);
  d.setUint16(20, 1, Endian.little);
  d.setUint16(22, 1, Endian.little);
  d.setUint32(24, sr, Endian.little);
  d.setUint32(28, sr * 2, Endian.little);
  d.setUint16(32, 2, Endian.little);
  d.setUint16(34, 16, Endian.little);
  tag(36, 'data');
  d.setUint32(40, n * 2, Endian.little);
  var idx = 0;
  for (final f in freqs) {
    for (var i = 0; i < per; i++) {
      final t = i / sr;
      final env = exp(-5.0 * i / per);
      final v = (sin(2 * pi * f * t) + 0.3 * sin(4 * pi * f * t)) * env * 0.6;
      d.setInt16(44 + idx * 2, (v * 32767).round().clamp(-32768, 32767).toInt(), Endian.little);
      idx++;
    }
  }
  return d.buffer.asUint8List();
}

final _okWav = _makeWav([1760], 220); // "ting" cao
final _warnWav = _makeWav([330, 330], 140); // 2 tiếng thấp
final AudioPlayer _player = AudioPlayer();

/// Bật/tắt âm thanh + rung khi quét
bool feedbackEnabled = true;

Future<void> _play(Uint8List b) async {
  try {
    await _player.stop();
    await _player.play(BytesSource(b), volume: 1.0);
  } catch (_) {}
}

Future<void> _vibe({List<int>? pattern, int ms = 80}) async {
  try {
    if (await Vibration.hasVibrator() != true) return;
    if (pattern != null) {
      Vibration.vibrate(pattern: pattern);
    } else {
      Vibration.vibrate(duration: ms);
    }
  } catch (_) {}
}

/// Quét đúng mã trong danh sách: ting + rung ngắn
void scanFeedbackOk() {
  if (!feedbackEnabled) return;
  _play(_okWav);
  _vibe(ms: 80);
}

/// Mã ngoài danh sách: 2 tiếng thấp + rung 2 nhịp
void scanFeedbackWarn() {
  if (!feedbackEnabled) return;
  _play(_warnWav);
  _vibe(pattern: [0, 120, 80, 120]);
}
