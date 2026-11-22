import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

class LiveCallTutorialPage extends StatefulWidget {
  const LiveCallTutorialPage({super.key});
  @override
  State<LiveCallTutorialPage> createState() => _LiveCallTutorialPageState();
}

class _LiveCallTutorialPageState extends State<LiveCallTutorialPage> {
  late final VideoPlayerController _c;
  bool _ready = false;
  bool _finished = false;

  @override
  void initState() {
    super.initState();
    _c = VideoPlayerController.asset('assets/videos/live_call_guide.mp4')
      ..initialize().then((_) {
        if (!mounted) return;
        setState(() => _ready = true);
        _c.play();
      });
    _c.addListener(() {
      final v = _c.value;
      if (v.isInitialized && v.position >= v.duration && !_finished && mounted) {
        setState(() => _finished = true);
      }
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('How Live Call Detection works')),
    body: SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(children: [
          Expanded(
            child: Center(
              child: _ready
                  ? AspectRatio(
                      aspectRatio: _c.value.aspectRatio,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: Stack(alignment: Alignment.bottomCenter, children: [
                          VideoPlayer(_c),
                          VideoProgressIndicator(_c, allowScrubbing: true),
                          Positioned.fill(
                            child: GestureDetector(
                              onTap: () => setState(() {
                                _c.value.isPlaying ? _c.pause() : _c.play();
                              }),
                              child: Container(
                                color: Colors.transparent,
                                child: Center(
                                  child: _c.value.isPlaying
                                      ? const SizedBox()
                                      : const Icon(Icons.play_circle_fill,
                                          color: Colors.white, size: 64),
                                ),
                              ),
                            ),
                          ),
                        ]),
                      ),
                    )
                  : const CircularProgressIndicator(),
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Watch this short guide. Recording never starts unless you tap Allow.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Text(_finished ? 'Continue' : 'Skip and continue'),
              ),
            ),
          ),
        ]),
      ),
    ),
  );
}