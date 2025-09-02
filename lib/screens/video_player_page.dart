import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

class VideoPlayerPage extends StatefulWidget {
  final String pathOrUri;
  final String? title;
  const VideoPlayerPage({super.key, required this.pathOrUri, this.title});

  @override
  State<VideoPlayerPage> createState() => _VideoPlayerPageState();
}

class _VideoPlayerPageState extends State<VideoPlayerPage> {
  VideoPlayerController? _controller;
  bool _error = false;
  String? _errorMsg;
  bool _isFullscreen = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final path = widget.pathOrUri;
      if (path.startsWith('content://')) {
        _controller = VideoPlayerController.contentUri(Uri.parse(path));
      } else {
        _controller = VideoPlayerController.file(File(path));
      }

      debugPrint('Initializing video controller...');
      await _controller!.initialize();
      debugPrint('Video initialized. Duration: ${_controller!.value.duration}');

      _controller!.setVolume(1.0);
      _controller!.setLooping(false);

      // Auto-play the video when initialized
      try {
        debugPrint('Starting auto-play...');
        await _controller!.play();
        debugPrint('Auto-play started. Is playing: ${_controller!.value.isPlaying}');

        // Add a small delay to ensure the video starts properly
        await Future.delayed(const Duration(milliseconds: 100));
        debugPrint('After delay - Is playing: ${_controller!.value.isPlaying}, Position: ${_controller!.value.position}');
      } catch (e) {
        // If auto-play fails, at least show the first frame
        debugPrint('Auto-play failed: $e');
      }

      setState(() {});
    } catch (e) {
      debugPrint('Video initialization failed: $e');
      _error = true;
      _errorMsg = e.toString();
      setState(() {});
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  void _toggleFullscreen() {
    setState(() {
      _isFullscreen = !_isFullscreen;
    });
    if (_isFullscreen) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    } else {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual,
          overlays: SystemUiOverlay.values);
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    return Scaffold(
      appBar: _isFullscreen ? null : AppBar(
        title: Text(widget.title ?? 'Playback'),
        actions: [
          IconButton(
            icon: const Icon(Icons.fullscreen),
            onPressed: _toggleFullscreen,
          ),
        ],
      ),
      backgroundColor: Colors.black,
      body: _error
          ? _ErrorBody(message: _errorMsg)
          : (c == null || !c.value.isInitialized)
              ? const Center(child: CircularProgressIndicator())
              : _PlayerBody(
                  controller: c,
                  isFullscreen: _isFullscreen,
                  onFullscreenToggle: _toggleFullscreen,
                ),
    );
  }
}

class _PlayerBody extends StatefulWidget {
  final VideoPlayerController controller;
  final bool isFullscreen;
  final VoidCallback onFullscreenToggle;

  const _PlayerBody({
    required this.controller,
    required this.isFullscreen,
    required this.onFullscreenToggle,
  });

  @override
  State<_PlayerBody> createState() => _PlayerBodyState();
}

class _PlayerBodyState extends State<_PlayerBody> {
  bool _controlsVisible = true;
  Timer? _hideControlsTimer;
  double _volume = 1.0;
  double _playbackSpeed = 1.0;
  bool _isMuted = false;
  bool _isLooping = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_listener);
    _startHideControlsTimer();

    // Ensure video starts playing after a short delay
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _ensureVideoPlays();
    });
  }

  Future<void> _ensureVideoPlays() async {
    await Future.delayed(const Duration(milliseconds: 500));
    if (mounted && widget.controller.value.isInitialized && !widget.controller.value.isPlaying) {
      debugPrint('Ensuring video plays...');
      try {
        await widget.controller.play();
        debugPrint('Video play ensured. Is playing: ${widget.controller.value.isPlaying}');
      } catch (e) {
        debugPrint('Failed to ensure video plays: $e');
      }
    }
  }

  void _listener() {
    if (mounted) {
      debugPrint('Controller listener: position=${widget.controller.value.position}, isPlaying=${widget.controller.value.isPlaying}, isInitialized=${widget.controller.value.isInitialized}');
      setState(() {});
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_listener);
    _hideControlsTimer?.cancel();
    super.dispose();
  }

  void _startHideControlsTimer() {
    _hideControlsTimer?.cancel();
    _hideControlsTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && _controlsVisible) {
        setState(() => _controlsVisible = false);
      }
    });
  }

  void _showControls() {
    setState(() => _controlsVisible = true);
    _startHideControlsTimer();
  }

  void _togglePlay() async {
    final c = widget.controller;
    debugPrint('Toggle play called. Currently playing: ${c.value.isPlaying}');

    if (c.value.isPlaying) {
      debugPrint('Pausing video...');
      await c.pause();
      debugPrint('Video paused. Is playing: ${c.value.isPlaying}');
    } else {
      debugPrint('Playing video...');
      await c.play();
      debugPrint('Video started. Is playing: ${c.value.isPlaying}');
    }
    _showControls();
    // Force a rebuild to update the UI immediately
    if (mounted) {
      setState(() {});
    }
  }

  void _skipForward(int seconds) async {
    final c = widget.controller;
    final wasPlaying = c.value.isPlaying;
    final newPosition = c.value.position + Duration(seconds: seconds);
    await c.seekTo(newPosition < c.value.duration ? newPosition : c.value.duration);
    // Resume playing if it was playing before
    if (wasPlaying) {
      await c.play();
    }
    _showControls();
  }

  void _skipBackward(int seconds) async {
    final c = widget.controller;
    final wasPlaying = c.value.isPlaying;
    final newPosition = c.value.position - Duration(seconds: seconds);
    await c.seekTo(newPosition > Duration.zero ? newPosition : Duration.zero);
    // Resume playing if it was playing before
    if (wasPlaying) {
      await c.play();
    }
    _showControls();
  }

  void _setVolume(double volume) {
    setState(() => _volume = volume);
    widget.controller.setVolume(volume);
    _showControls();
  }

  void _toggleMute() {
    setState(() => _isMuted = !_isMuted);
    widget.controller.setVolume(_isMuted ? 0.0 : _volume);
    _showControls();
  }

  void _setPlaybackSpeed(double speed) {
    setState(() => _playbackSpeed = speed);
    widget.controller.setPlaybackSpeed(speed);
    _showControls();
  }

  void _toggleLoop() {
    setState(() => _isLooping = !_isLooping);
    widget.controller.setLooping(_isLooping);
    _showControls();
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);

    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final aspect = c.value.aspectRatio == 0 ? 16 / 9 : c.value.aspectRatio;

    return KeyboardListener(
      focusNode: FocusNode(),
      onKeyEvent: (event) {
        if (event is KeyDownEvent) {
          switch (event.logicalKey) {
            case LogicalKeyboardKey.space:
              _togglePlay();
              break;
            case LogicalKeyboardKey.arrowLeft:
              _skipBackward(10);
              break;
            case LogicalKeyboardKey.arrowRight:
              _skipForward(10);
              break;
            case LogicalKeyboardKey.keyF:
              widget.onFullscreenToggle();
              break;
            case LogicalKeyboardKey.keyM:
              _toggleMute();
              break;
          }
        }
      },
      child: GestureDetector(
        onTap: _showControls,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Center(
              child: AspectRatio(
                aspectRatio: aspect,
                child: VideoPlayer(
                  c,
                  key: ValueKey('video_player_${c.hashCode}'),
                ),
              ),
            ),
            if (_controlsVisible)
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withOpacity(0.7),
                        Colors.transparent,
                        Colors.transparent,
                        Colors.black.withOpacity(0.7),
                      ],
                    ),
                  ),
                  child: Column(
                    children: [
                      // Top controls
                      if (!widget.isFullscreen)
                        Container(
                          height: 48,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Row(
                            children: [
                              IconButton(
                                icon: const Icon(Icons.arrow_back, color: Colors.white),
                                onPressed: () => Navigator.of(context).pop(),
                              ),
                              const Spacer(),
                              IconButton(
                                icon: Icon(widget.isFullscreen ? Icons.fullscreen_exit : Icons.fullscreen, color: Colors.white),
                                onPressed: widget.onFullscreenToggle,
                              ),
                            ],
                          ),
                        )
                      else
                        const SizedBox(height: 24),

                      const Spacer(),

                      // Center play button
                      Center(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            IconButton(
                              iconSize: 48,
                              color: Colors.white,
                              onPressed: () => _skipBackward(10),
                              icon: const Icon(Icons.replay_10),
                            ),
                            const SizedBox(width: 24),
                            IconButton(
                              iconSize: 72,
                              color: Colors.white,
                              onPressed: _togglePlay,
                              icon: Icon(c.value.isPlaying ? Icons.pause_circle_filled_rounded : Icons.play_circle_fill_rounded),
                            ),
                            const SizedBox(width: 24),
                            IconButton(
                              iconSize: 48,
                              color: Colors.white,
                              onPressed: () => _skipForward(10),
                              icon: const Icon(Icons.forward_10),
                            ),
                          ],
                        ),
                      ),

                      const Spacer(),

                      // Bottom controls
                      Container(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: [
                            // Progress bar with time labels
                            Row(
                              children: [
                                Text(
                                  _formatDuration(c.value.position),
                                  style: const TextStyle(color: Colors.white, fontSize: 12),
                                ),
                                Expanded(
                                  child: GestureDetector(
                                    onHorizontalDragUpdate: (details) {
                                      final box = context.findRenderObject() as RenderBox;
                                      final fraction = details.localPosition.dx / box.size.width;
                                      final newPosition = c.value.duration * fraction.clamp(0.0, 1.0);
                                      c.seekTo(newPosition);
                                    },
                                    onHorizontalDragEnd: (details) async {
                                      // Resume playing if it was playing before scrubbing
                                      final wasPlaying = c.value.isPlaying;
                                      if (wasPlaying) {
                                        await c.play();
                                      }
                                    },
                                    child: VideoProgressIndicator(
                                      c,
                                      allowScrubbing: true,
                                      padding: const EdgeInsets.symmetric(horizontal: 8),
                                      colors: VideoProgressColors(
                                        playedColor: Colors.redAccent,
                                        bufferedColor: Colors.white38,
                                        backgroundColor: Colors.white24,
                                      ),
                                    ),
                                  ),
                                ),
                                Text(
                                  _formatDuration(c.value.duration),
                                  style: const TextStyle(color: Colors.white, fontSize: 12),
                                ),
                              ],
                            ),

                            // Control buttons
                            Row(
                              children: [
                                IconButton(
                                  icon: Icon(_isMuted ? Icons.volume_off : Icons.volume_up, color: Colors.white),
                                  onPressed: _toggleMute,
                                ),
                                Expanded(
                                  child: Slider(
                                    value: _isMuted ? 0.0 : _volume,
                                    onChanged: (value) {
                                      _setVolume(value);
                                      if (_isMuted) {
                                        setState(() => _isMuted = false);
                                      }
                                    },
                                    activeColor: Colors.redAccent,
                                    inactiveColor: Colors.white24,
                                  ),
                                ),
                                PopupMenuButton<double>(
                                  icon: Text(
                                    '${_playbackSpeed}x',
                                    style: const TextStyle(color: Colors.white, fontSize: 12),
                                  ),
                                  onSelected: _setPlaybackSpeed,
                                  itemBuilder: (context) => [
                                    const PopupMenuItem(value: 0.5, child: Text('0.5x')),
                                    const PopupMenuItem(value: 0.75, child: Text('0.75x')),
                                    const PopupMenuItem(value: 1.0, child: Text('1x')),
                                    const PopupMenuItem(value: 1.25, child: Text('1.25x')),
                                    const PopupMenuItem(value: 1.5, child: Text('1.5x')),
                                    const PopupMenuItem(value: 2.0, child: Text('2x')),
                                  ],
                                ),
                                IconButton(
                                  icon: Icon(_isLooping ? Icons.repeat_one : Icons.repeat, color: Colors.white),
                                  onPressed: _toggleLoop,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ErrorBody extends StatelessWidget {
  final String? message;
  const _ErrorBody({this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded, color: Colors.white70, size: 48),
            const SizedBox(height: 12),
            Text(
              'Unable to play video',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Colors.white),
              textAlign: TextAlign.center,
            ),
            if (message != null) ...[
              const SizedBox(height: 8),
              Text(
                message!,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.white70),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
