import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const SRApp());
}

class SRApp extends StatefulWidget {
  const SRApp({super.key});

  @override
  State<SRApp> createState() => _SRAppState();
}

class _SRAppState extends State<SRApp> {
  final AppModel model = AppModel();
  late final RecordingController controller = RecordingController(model: model);

  @override
  void dispose() {
    controller.dispose();
    model.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final light = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo, brightness: Brightness.light),
      visualDensity: VisualDensity.adaptivePlatformDensity,
      fontFamily: 'Roboto',
    );
    final dark = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo, brightness: Brightness.dark),
      visualDensity: VisualDensity.adaptivePlatformDensity,
      fontFamily: 'Roboto',
    );

    return AnimatedBuilder(
      animation: model,
      builder: (context, _) {
        return AppScope(
          model: model,
          controller: controller,
          child: MaterialApp(
            title: 'Screen Recorder',
            debugShowCheckedModeBanner: false,
            theme: light,
            darkTheme: dark,
            themeMode: model.themeMode,
            routes: {
              '/': (_) => const OnboardingScreen(),
              '/root': (_) => const RootShell(),
              '/contact': (_) => const ContactPage(),
            },
          ),
        );
      },
    );
  }
}

// App-wide scope to access model and controller
class AppScope extends InheritedWidget {
  final AppModel model;
  final RecordingController controller;

  const AppScope({super.key, required this.model, required this.controller, required super.child});

  static AppScope of(BuildContext context) {
    final AppScope? scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'AppScope not found in context');
    return scope!;
  }

  @override
  bool updateShouldNotify(covariant AppScope oldWidget) =>
      model != oldWidget.model || controller != oldWidget.controller;
}

// Models and state
enum RecordingState { idle, countdown, recording, paused }

enum VideoResolution { p480, p720, p1080 }

class RecordingSettings {
  VideoResolution resolution;
  int fps; // 24..60
  int bitrateKbps; // e.g., 4000..20000
  bool includeAudio;
  int countdownSeconds; // 0..10

  RecordingSettings({
    this.resolution = VideoResolution.p1080,
    this.fps = 30,
    this.bitrateKbps = 8000,
    this.includeAudio = true,
    this.countdownSeconds = 3,
  });
}

class RecordingSession {
  final DateTime startedAt;
  final DateTime endedAt;
  final Duration duration;
  final VideoResolution resolution;
  final int fps;
  final int bitrateKbps;
  final bool includeAudio;

  RecordingSession({
    required this.startedAt,
    required this.endedAt,
    required this.duration,
    required this.resolution,
    required this.fps,
    required this.bitrateKbps,
    required this.includeAudio,
  });
}

class AppModel extends ChangeNotifier {
  ThemeMode _themeMode = ThemeMode.system;
  final RecordingSettings settings = RecordingSettings();
  final List<RecordingSession> history = [];

  ThemeMode get themeMode => _themeMode;

  void setThemeMode(ThemeMode mode) {
    _themeMode = mode;
    notifyListeners();
  }

  void addHistory(RecordingSession s) {
    history.insert(0, s);
    notifyListeners();
  }
}

class RecordingController extends ChangeNotifier {
  static const MethodChannel _ch = MethodChannel('com.example.screen_recorder/recorder');
  final AppModel model;

  RecordingState state = RecordingState.idle;
  Duration elapsed = Duration.zero;
  int countdownRemaining = 0;

  Timer? _ticker;
  Timer? _countdownTimer;
  DateTime? _startedAt;

  RecordingController({required this.model});

  void start() {
    if (state != RecordingState.idle) return;
    final seconds = model.settings.countdownSeconds;
    if (seconds > 0) {
      countdownRemaining = seconds;
      state = RecordingState.countdown;
      notifyListeners();
      _countdownTimer?.cancel();
      _countdownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
        countdownRemaining--;
        if (countdownRemaining <= 0) {
          t.cancel();
          _beginRecording();
        }
        notifyListeners();
      });
    } else {
      _beginRecording();
    }
  }

  Future<void> _invoke(String method) async {
    if (defaultTargetPlatform == TargetPlatform.android) {
      try { await _ch.invokeMethod(method); } catch (_) {}
    }
  }

  void _beginRecording() {
    state = RecordingState.recording;
    elapsed = Duration.zero;
    _startedAt = DateTime.now();
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      elapsed += const Duration(seconds: 1);
      notifyListeners();
    });
    notifyListeners();
    // Start Android foreground service with notification actions
    _invoke('serviceStart');
  }

  void pause() {
    if (state != RecordingState.recording) return;
    state = RecordingState.paused;
    _ticker?.cancel();
    _invoke('servicePause');
    notifyListeners();
  }

  void resume() {
    if (state != RecordingState.paused) return;
    state = RecordingState.recording;
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      elapsed += const Duration(seconds: 1);
      notifyListeners();
    });
    _invoke('serviceResume');
    notifyListeners();
  }

  void stop() {
    if (state == RecordingState.idle) return;
    _ticker?.cancel();
    _countdownTimer?.cancel();
    _invoke('serviceStop');
    final end = DateTime.now();
    final start = _startedAt ?? end;
    if (state == RecordingState.recording || state == RecordingState.paused) {
      final session = RecordingSession(
        startedAt: start,
        endedAt: end,
        duration: elapsed,
        resolution: model.settings.resolution,
        fps: model.settings.fps,
        bitrateKbps: model.settings.bitrateKbps,
        includeAudio: model.settings.includeAudio,
      );
      model.addHistory(session);
    }
    state = RecordingState.idle;
    elapsed = Duration.zero;
    countdownRemaining = 0;
    _startedAt = null;
    notifyListeners();
    // Stop platform recording later.
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _countdownTimer?.cancel();
    super.dispose();
  }
}

// UI
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _controller = PageController();
  int _index = 0;

  final pages = const [
    _OnboardPage(
      title: 'Record your screen',
      subtitle: 'Start, pause, and stop recordings with a single tap.',
      icon: Icons.fiber_manual_record_rounded,
    ),
    _OnboardPage(
      title: 'Quick controls',
      subtitle: 'Use notification actions to control recording anytime.',
      icon: Icons.notifications_active_rounded,
    ),
    _OnboardPage(
      title: 'Tune quality',
      subtitle: 'Set resolution, FPS, bitrate and audio options.',
      icon: Icons.tune_rounded,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: pages.length,
                onPageChanged: (i) => setState(() => _index = i),
                itemBuilder: (_, i) => pages[i],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: Row(
                children: [
                  Row(
                    children: List.generate(pages.length, (i) {
                      final active = i == _index;
                      return AnimatedContainer(
                        duration: const Duration(milliseconds: 250),
                        margin: const EdgeInsets.only(right: 6),
                        height: 8,
                        width: active ? 24 : 8,
                        decoration: BoxDecoration(
                          color: active ? scheme.primary : scheme.outlineVariant,
                          borderRadius: BorderRadius.circular(99),
                        ),
                      );
                    }),
                  ),
                  const Spacer(),
                  FilledButton(
                    onPressed: () {
                      if (_index < pages.length - 1) {
                        _controller.nextPage(duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
                      } else {
                        Navigator.of(context).pushReplacementNamed('/root');
                      }
                    },
                    child: Text(_index < pages.length - 1 ? 'Next' : 'Get started'),
                  )
                ],
              ),
            )
          ],
        ),
      ),
    );
  }
}

class _OnboardPage extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  const _OnboardPage({required this.title, required this.subtitle, required this.icon});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(icon, size: 96, color: scheme.primary),
          const SizedBox(height: 24),
          Text(title, textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          Text(subtitle, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: Theme.of(context).textTheme.bodyMedium?.color)),
        ],
      ),
    );
  }
}

class RootShell extends StatefulWidget {
  const RootShell({super.key});

  @override
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final pages = [
      const HomePage(),
      const HistoryPage(),
      const SettingsPage(),
    ];

    return Scaffold(
      body: pages[_index],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_rounded), label: 'Home'),
          NavigationDestination(icon: Icon(Icons.history_rounded), label: 'History'),
          NavigationDestination(icon: Icon(Icons.settings_rounded), label: 'Settings'),
        ],
      ),
    );
  }
}

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final c = scope.controller;

    return AnimatedBuilder(
      animation: Listenable.merge([scope.model, c]),
      builder: (context, _) {
        return Scaffold(
          appBar: AppBar(
            title: const Text('Screen Recorder'),
            actions: [
              IconButton(
                tooltip: 'Contact',
                onPressed: () => Navigator.pushNamed(context, '/contact'),
                icon: const Icon(Icons.mail_rounded),
              )
            ],
          ),
          body: Stack(
            children: [
              ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  if (c.state == RecordingState.recording || c.state == RecordingState.paused)
                    _RecordingBanner(controller: c),
                  const SizedBox(height: 16),
                  _RecordCard(controller: c),
                  const SizedBox(height: 24),
                  _QuickSettings(model: scope.model),
                  const SizedBox(height: 24),
                  const _TipsCard(),
                ],
              ),
              if (c.state == RecordingState.countdown)
                _CountdownOverlay(seconds: c.countdownRemaining),
            ],
          ),
        );
      },
    );
  }
}

class _RecordingBanner extends StatelessWidget {
  final RecordingController controller;
  const _RecordingBanner({required this.controller});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isPaused = controller.state == RecordingState.paused;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isPaused ? scheme.tertiaryContainer : scheme.primaryContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(isPaused ? Icons.pause_circle_filled_rounded : Icons.fiber_manual_record_rounded, color: isPaused ? scheme.onTertiaryContainer : scheme.onPrimaryContainer),
          const SizedBox(width: 12),
          Text(_formatDuration(controller.elapsed), style: Theme.of(context).textTheme.titleMedium?.copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
          const Spacer(),
          IconButton(
            tooltip: isPaused ? 'Resume' : 'Pause',
            onPressed: () => isPaused ? controller.resume() : controller.pause(),
            icon: Icon(isPaused ? Icons.play_arrow_rounded : Icons.pause_rounded),
          ),
          const SizedBox(width: 4),
          FilledButton.tonal(
            onPressed: controller.stop,
            child: const Text('Stop'),
          )
        ],
      ),
    );
  }
}

class _RecordCard extends StatelessWidget {
  final RecordingController controller;
  const _RecordCard({required this.controller});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isIdle = controller.state == RecordingState.idle;
    final isRecording = controller.state == RecordingState.recording || controller.state == RecordingState.countdown || controller.state == RecordingState.paused;

    return Card(
      elevation: 0,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Recorder', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 16),
            Center(
              child: GestureDetector(
                onTap: isIdle ? controller.start : controller.stop,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  height: 120,
                  width: 120,
                  decoration: BoxDecoration(
                    color: isIdle ? scheme.primary : scheme.error,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(color: (isIdle ? scheme.primary : scheme.error).withOpacity(0.3), blurRadius: 24, spreadRadius: 4),
                    ],
                  ),
                  child: Icon(isIdle ? Icons.fiber_manual_record_rounded : Icons.stop_rounded, color: isIdle ? scheme.onPrimary : scheme.onError, size: 56),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Center(
              child: Text(
                isIdle ? 'Tap to start recording' : 'Tap to stop',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).textTheme.bodySmall?.color),
              ),
            ),
            if (!isIdle) ...[
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  FilledButton.icon(
                    onPressed: controller.state == RecordingState.paused ? controller.resume : controller.pause,
                    icon: Icon(controller.state == RecordingState.paused ? Icons.play_arrow_rounded : Icons.pause_rounded),
                    label: Text(controller.state == RecordingState.paused ? 'Resume' : 'Pause'),
                  ),
                  const SizedBox(width: 12),
                  OutlinedButton.icon(
                    onPressed: controller.stop,
                    icon: const Icon(Icons.stop_rounded),
                    label: const Text('Stop'),
                  ),
                ],
              ),
            ]
          ],
        ),
      ),
    );
  }
}

class _QuickSettings extends StatelessWidget {
  final AppModel model;
  const _QuickSettings({required this.model});

  @override
  Widget build(BuildContext context) {
    final s = model.settings;
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Quick settings', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _ChipDropdown<VideoResolution>(
                  label: 'Resolution',
                  value: s.resolution,
                  items: const {
                    VideoResolution.p1080: '1080p',
                    VideoResolution.p720: '720p',
                    VideoResolution.p480: '480p',
                  },
                  onChanged: (v) {
                    if (v == null) return;
                    s.resolution = v;
                    model.notifyListeners();
                  },
                ),
                _ChipDropdown<int>(
                  label: 'FPS',
                  value: s.fps,
                  items: const {
                    24: '24',
                    30: '30',
                    60: '60',
                  },
                  onChanged: (v) {
                    if (v == null) return;
                    s.fps = v;
                    model.notifyListeners();
                  },
                ),
                _ChipDropdown<int>(
                  label: 'Bitrate',
                  value: s.bitrateKbps,
                  items: const {
                    4000: '4 Mbps',
                    8000: '8 Mbps',
                    12000: '12 Mbps',
                    20000: '20 Mbps',
                  },
                  onChanged: (v) {
                    if (v == null) return;
                    s.bitrateKbps = v;
                    model.notifyListeners();
                  },
                ),
                FilterChip(
                  label: const Text('Audio'),
                  selected: s.includeAudio,
                  onSelected: (sel) {
                    s.includeAudio = sel;
                    model.notifyListeners();
                  },
                ),
                InputChip(
                  label: Text('Countdown: ${s.countdownSeconds}s'),
                  onPressed: () async {
                    final v = await showDialog<int>(context: context, builder: (_) => _CountdownDialog(initial: s.countdownSeconds));
                    if (v != null) {
                      s.countdownSeconds = v;
                      model.notifyListeners();
                    }
                  },
                )
              ],
            )
          ],
        ),
      ),
    );
  }
}

class _TipsCard extends StatelessWidget {
  const _TipsCard();
  @override
  Widget build(BuildContext context) {
    final textStyle = Theme.of(context).textTheme.bodyMedium;
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Tip', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Text('After initial run, a persistent notification with quick actions (Start, Pause/Resume, Stop) will be available once platform integration is added.', style: textStyle),
          ],
        ),
      ),
    );
  }
}

class _ChipDropdown<T> extends StatelessWidget {
  final String label;
  final T value;
  final Map<T, String> items;
  final ValueChanged<T?> onChanged;

  const _ChipDropdown({required this.label, required this.value, required this.items, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<T>(
      tooltip: label,
      initialValue: value,
      onSelected: onChanged,
      itemBuilder: (_) => items.entries
          .map((e) => PopupMenuItem<T>(value: e.key, child: Text(e.value)))
          .toList(),
      child: InputChip(
        label: Text('$label: ${items[value]}'),
        onPressed: () {},
      ),
    );
  }
}

class _CountdownOverlay extends StatelessWidget {
  final int seconds;
  const _CountdownOverlay({required this.seconds});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black.withOpacity(0.4),
      alignment: Alignment.center,
      child: AnimatedScale(
        scale: 1,
        duration: const Duration(milliseconds: 300),
        child: Container(
          height: 140,
          width: 140,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.inverseSurface,
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: Text('$seconds', style: Theme.of(context).textTheme.displayMedium?.copyWith(color: Theme.of(context).colorScheme.onInverseSurface)),
        ),
      ),
    );
  }
}

class HistoryPage extends StatelessWidget {
  const HistoryPage({super.key});

  @override
  Widget build(BuildContext context) {
    final model = AppScope.of(context).model;
    return AnimatedBuilder(
      animation: model,
      builder: (context, _) {
        return Scaffold(
          appBar: AppBar(title: const Text('History')),
          body: model.history.isEmpty
              ? const _EmptyHistory()
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: model.history.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (_, i) {
                    final s = model.history[i];
                    return ListTile(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      tileColor: Theme.of(context).colorScheme.surfaceContainerHigh,
                      leading: const Icon(Icons.videocam_rounded),
                      title: Text('${_formatDateTime(s.startedAt)} • ${_formatDuration(s.duration)}'),
                      subtitle: Text('${_resLabel(s.resolution)} • ${s.fps} FPS • ${(s.bitrateKbps / 1000).toStringAsFixed(0)} Mbps${s.includeAudio ? ' • Audio' : ''}'),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () {},
                    );
                  },
                ),
        );
      },
    );
  }
}

class _EmptyHistory extends StatelessWidget {
  const _EmptyHistory();
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.video_library_outlined, size: 64, color: Theme.of(context).colorScheme.outline),
          const SizedBox(height: 12),
          Text('No recordings yet', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          Text('Your recordings will appear here.', style: Theme.of(context).textTheme.bodyMedium),
        ],
      ),
    );
  }
}

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final model = AppScope.of(context).model;
    final s = model.settings;
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _Section(title: 'Video'),
          _Tile(
            title: 'Resolution',
            subtitle: _resLabel(s.resolution),
            trailing: DropdownButton<VideoResolution>(
              value: s.resolution,
              onChanged: (v) { if (v != null) { s.resolution = v; model.notifyListeners(); }},
              items: const [
                DropdownMenuItem(value: VideoResolution.p1080, child: Text('1080p')),
                DropdownMenuItem(value: VideoResolution.p720, child: Text('720p')),
                DropdownMenuItem(value: VideoResolution.p480, child: Text('480p')),
              ],
            ),
          ),
          _Tile(
            title: 'Frame rate',
            subtitle: '${s.fps} FPS',
            trailing: DropdownButton<int>(
              value: s.fps,
              onChanged: (v) { if (v != null) { s.fps = v; model.notifyListeners(); }},
              items: const [
                DropdownMenuItem(value: 24, child: Text('24')), DropdownMenuItem(value: 30, child: Text('30')), DropdownMenuItem(value: 60, child: Text('60')),
              ],
            ),
          ),
          _Tile(
            title: 'Bitrate',
            subtitle: '${(s.bitrateKbps / 1000).toStringAsFixed(0)} Mbps',
            trailing: DropdownButton<int>(
              value: s.bitrateKbps,
              onChanged: (v) { if (v != null) { s.bitrateKbps = v; model.notifyListeners(); }},
              items: const [
                DropdownMenuItem(value: 4000, child: Text('4 Mbps')),
                DropdownMenuItem(value: 8000, child: Text('8 Mbps')),
                DropdownMenuItem(value: 12000, child: Text('12 Mbps')),
                DropdownMenuItem(value: 20000, child: Text('20 Mbps')),
              ],
            ),
          ),
          const SizedBox(height: 8),
          _Section(title: 'Audio'),
          SwitchListTile(
            title: const Text('Record audio'),
            subtitle: const Text('Include microphone input'),
            value: s.includeAudio,
            onChanged: (v) { s.includeAudio = v; model.notifyListeners(); },
          ),
          _Tile(
            title: 'Countdown',
            subtitle: '${s.countdownSeconds} seconds',
            onTap: () async {
              final v = await showDialog<int>(context: context, builder: (_) => _CountdownDialog(initial: s.countdownSeconds));
              if (v != null) { s.countdownSeconds = v; model.notifyListeners(); }
            },
          ),
          const SizedBox(height: 8),
          _Section(title: 'Appearance'),
          _Tile(
            title: 'Theme',
            subtitle: _themeLabel(model.themeMode),
            onTap: () async {
              final mode = await showModalBottomSheet<ThemeMode>(
                context: context,
                showDragHandle: true,
                builder: (_) => _ThemePicker(current: model.themeMode),
              );
              if (mode != null) model.setThemeMode(mode);
            },
          ),
          const SizedBox(height: 8),
          _Section(title: 'Support'),
          _Tile(
            title: 'Contact',
            subtitle: 'Get in touch',
            onTap: () => Navigator.pushNamed(context, '/contact'),
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  const _Section({required this.title});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(left: 16, right: 16, top: 8, bottom: 4),
        child: Text(title, style: Theme.of(context).textTheme.titleSmall?.copyWith(color: Theme.of(context).colorScheme.primary)),
      );
}

class _Tile extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  const _Tile({required this.title, this.subtitle, this.trailing, this.onTap});
  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      margin: const EdgeInsets.symmetric(vertical: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ListTile(
        title: Text(title),
        subtitle: subtitle != null ? Text(subtitle!) : null,
        trailing: trailing ?? const Icon(Icons.chevron_right_rounded),
        onTap: onTap,
      ),
    );
  }
}

class _CountdownDialog extends StatefulWidget {
  final int initial;
  const _CountdownDialog({required this.initial});
  @override
  State<_CountdownDialog> createState() => _CountdownDialogState();
}

class _CountdownDialogState extends State<_CountdownDialog> {
  late double _value = widget.initial.toDouble();
  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Countdown seconds'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Slider(
            value: _value,
            min: 0,
            max: 10,
            divisions: 10,
            label: _value.toStringAsFixed(0),
            onChanged: (v) => setState(() => _value = v),
          ),
          Text('${_value.toStringAsFixed(0)} seconds')
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop<int>(context, _value.toInt()), child: const Text('Save')),
      ],
    );
  }
}

class _ThemePicker extends StatelessWidget {
  final ThemeMode current;
  const _ThemePicker({required this.current});
  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            RadioListTile<ThemeMode>(
              title: const Text('System'),
              value: ThemeMode.system,
              groupValue: current,
              onChanged: (v) => Navigator.pop(context, v),
            ),
            RadioListTile<ThemeMode>(
              title: const Text('Light'),
              value: ThemeMode.light,
              groupValue: current,
              onChanged: (v) => Navigator.pop(context, v),
            ),
            RadioListTile<ThemeMode>(
              title: const Text('Dark'),
              value: ThemeMode.dark,
              groupValue: current,
              onChanged: (v) => Navigator.pop(context, v),
            ),
          ],
        ),
      ),
    );
  }
}

class ContactPage extends StatelessWidget {
  const ContactPage({super.key});

  static const String email = 'support@example.com';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Contact')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Need help?', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text('Reach out and we\'ll get back to you.'),
            const SizedBox(height: 24),
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: ListTile(
                leading: const Icon(Icons.mail_rounded),
                title: const Text('Email'),
                subtitle: const Text(email),
                trailing: TextButton(
                  onPressed: () async {
                    await Clipboard.setData(const ClipboardData(text: email));
                    // ignore: use_build_context_synchronously
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Email copied')));
                  },
                  child: const Text('Copy'),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: const ListTile(
                leading: Icon(Icons.info_outline_rounded),
                title: Text('Version'),
                subtitle: Text('1.0.0'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _formatDuration(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  if (h > 0) {
    return '$h:$m:$s';
  }
  return '$m:$s';
}

String _formatDateTime(DateTime dt) {
  final y = dt.year.toString().padLeft(4, '0');
  final mo = dt.month.toString().padLeft(2, '0');
  final d = dt.day.toString().padLeft(2, '0');
  final h = dt.hour.toString().padLeft(2, '0');
  final mi = dt.minute.toString().padLeft(2, '0');
  return '$y-$mo-$d $h:$mi';
}

String _resLabel(VideoResolution r) {
  switch (r) {
    case VideoResolution.p1080:
      return '1080p';
    case VideoResolution.p720:
      return '720p';
    case VideoResolution.p480:
      return '480p';
  }
}

String _themeLabel(ThemeMode m) {
  switch (m) {
    case ThemeMode.system:
      return 'System';
    case ThemeMode.light:
      return 'Light';
    case ThemeMode.dark:
      return 'Dark';
  }
}
