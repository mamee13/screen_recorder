import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';

// Screens
import 'screens/onboarding_screen.dart';
import 'screens/root_shell.dart';
import 'screens/contact_page.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  _requestNotificationsIfNeeded();
  runApp(const SRApp());
}

Future<void> _requestNotificationsIfNeeded() async {
  const ch = MethodChannel('com.example.screen_recorder/recorder');
  try {
    await ch.invokeMethod('requestNotificationPermission');
  } catch (_) {}
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

  void updateSettings(void Function(RecordingSettings) update) {
    update(settings);
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

  Future<void> _invokeWithArgs(String method, Map<String, dynamic> args) async {
    if (defaultTargetPlatform == TargetPlatform.android) {
      try { await _ch.invokeMethod(method, args); } catch (_) {}
    }
  }

  Future<void> _beginRecording() async {
    state = RecordingState.recording;
    elapsed = Duration.zero;
    _startedAt = DateTime.now();
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      elapsed += const Duration(seconds: 1);
      notifyListeners();
    });
    notifyListeners();
    // Request Android MediaProjection and start foreground recording with settings
    final res = _resolutionToSize(model.settings.resolution);
    await _invokeWithArgs('requestProjectionAndStart', {
      'width': res.$1,
      'height': res.$2,
      'fps': model.settings.fps,
      'bitrateKbps': model.settings.bitrateKbps,
      'includeAudio': model.settings.includeAudio,
    });
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
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _countdownTimer?.cancel();
    super.dispose();
  }
}

// Shared helpers
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

// Maps enum to an approximate portrait size. MediaProjection will scale accordingly.
(int, int) _resolutionToSize(VideoResolution r) {
  switch (r) {
    case VideoResolution.p1080:
      return (1080, 1920);
    case VideoResolution.p720:
      return (720, 1280);
    case VideoResolution.p480:
      return (480, 854);
  }
}
