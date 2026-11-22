
import 'dart:async';
import 'dart:io';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';
import 'api_service.dart';
import 'main.dart'; // red, muted, FirebaseService, ResultPage

class RecordPage extends StatefulWidget {
  /// true when opened by tapping the notification body (asks first)
  final bool askToStart;

  /// true when the user tapped "Allow" on the notification (starts at once)
  final bool autoStart;

  const RecordPage({super.key, this.askToStart = false, this.autoStart = false});

  @override
  State<RecordPage> createState() => _RecordPageState();
}

class _RecordPageState extends State<RecordPage> {
  final _recorder = AudioRecorder();
  final _player = AudioPlayer();
  Timer? _timer;
  int _seconds = 0;
  bool _recording = false;
  bool _analyzing = false;
  bool _playing = false;
  String? _path;

  @override
  void initState() {
    super.initState();
    _player.onPlayerComplete.listen((_) {
      if (mounted) setState(() => _playing = false);
    });
    if (widget.autoStart) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _start());
    } else if (widget.askToStart) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _askAndStart());
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _recorder.dispose();
    _player.dispose();
    super.dispose();
  }

  Future<void> _askAndStart() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Record this call?'),
        content: const Text(
          'Recording starts only if you tap Allow. Your microphone will be used '
          'and you can stop at any time.\n\n'
          'Use speakerphone if you want the other voice picked up. It may not '
          'capture both sides clearly. Make sure everyone on the call has agreed '
          'to be recorded where the law requires it.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Don't allow")),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Allow')),
        ],
      ),
    );
    if (ok == true) await _start();
  }

  Future<void> _start() async {
    if (_recording) return;
    final mic = await Permission.microphone.request();
    if (!mic.isGranted) {
      _snack('Microphone permission is needed to record.');
      return;
    }
    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/call_${DateTime.now().millisecondsSinceEpoch}.wav';
    await _recorder.start(
      const RecordConfig(encoder: AudioEncoder.wav, sampleRate: 16000, numChannels: 1),
      path: path,
    );
    _seconds = 0;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _seconds++);
    });
    if (mounted) setState(() { _recording = true; _path = null; });
  }

  Future<void> _stop() async {
    _timer?.cancel();
    final path = await _recorder.stop();
    if (mounted) setState(() { _recording = false; _path = path; });
  }

  Future<void> _togglePlay() async {
    if (_path == null) return;
    if (_playing) {
      await _player.pause();
      setState(() => _playing = false);
    } else {
      await _player.play(DeviceFileSource(_path!));
      setState(() => _playing = true);
    }
  }

  Future<void> _delete() async {
    await _player.stop();
    if (_path != null) {
      final f = File(_path!);
      if (await f.exists()) await f.delete();
    }
    setState(() { _path = null; _seconds = 0; _playing = false; });
  }

  Future<void> _analyze() async {
    if (_path == null) return;
    await _player.stop();
    setState(() => _analyzing = true);
    try {
      final result = await VoiceApi().predict(_path!);
      final raw = result['ai_score'];
      if (raw is num && raw >= 0 && raw <= 1) {
        final s = raw.toDouble();
        final name = _path!.split(RegExp(r'[/\\]')).last;
        try {
          await FirebaseService().saveAnalysis(
            filename: name,
            aiScore: s,
            result: s > 0.5 ? 'Possible AI-generated voice' : 'Likely human voice',
          );
        } catch (_) {
          _snack('Analysis completed, but saving history failed.');
        }
        if (mounted) {
          await Navigator.push(context, MaterialPageRoute(
            builder: (_) => ResultPage(filename: name, score: s)));
        }
      } else {
        _snack('Unexpected result: ${result['result'] ?? result}');
      }
    } catch (e) {
      _snack('Analysis failed: $e');
    } finally {
      if (mounted) setState(() => _analyzing = false);
    }
  }

  void _snack(String m) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  String get _time {
    final m = (_seconds ~/ 60).toString().padLeft(2, '0');
    final s = (_seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Record for AI Check')),
    body: SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(children: [
          const Spacer(),
          if (_recording)
            const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.fiber_manual_record, color: red, size: 18),
              SizedBox(width: 6),
              Text('RECORDING', style: TextStyle(color: red, fontWeight: FontWeight.bold)),
            ]),
          const SizedBox(height: 12),
          Text(_time, style: const TextStyle(fontSize: 56, fontWeight: FontWeight.w300)),
          const SizedBox(height: 8),
          Text(
            _recording
                ? 'Microphone is on. Tap Stop to finish.'
                : _path != null
                    ? 'Recording ready. Listen, then analyze or delete.'
                    : 'Recording is off. It starts only when you allow it.',
            textAlign: TextAlign.center, style: const TextStyle(color: muted)),
          const SizedBox(height: 32),
          if (!_recording && _path == null)
            SizedBox(width: double.infinity, child: FilledButton.icon(
              onPressed: _askAndStart, icon: const Icon(Icons.mic), label: const Text('Start Recording'))),
          if (_recording)
            SizedBox(width: double.infinity, child: FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: red),
              onPressed: _stop, icon: const Icon(Icons.stop), label: const Text('Stop'))),
          if (!_recording && _path != null) ...[
            OutlinedButton.icon(
              onPressed: _analyzing ? null : _togglePlay,
              icon: Icon(_playing ? Icons.pause : Icons.play_arrow),
              label: Text(_playing ? 'Pause' : 'Play recording')),
            const SizedBox(height: 10),
            SizedBox(width: double.infinity, child: FilledButton.icon(
              onPressed: _analyzing ? null : _analyze,
              icon: _analyzing
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.search),
              label: Text(_analyzing ? 'Analyzing...' : 'Analyze'))),
            const SizedBox(height: 10),
            TextButton.icon(
              onPressed: _analyzing ? null : _delete,
              icon: const Icon(Icons.delete_outline), label: const Text('Delete')),
          ],
          const Spacer(),
          const Text(
            'Speakerphone recording may not capture both voices. Only record when everyone '
            'on the call has agreed, where the law requires it.',
            textAlign: TextAlign.center, style: TextStyle(color: muted, fontSize: 12)),
        ]),
      ),
    ),
  );
}