// ignore_for_file: unused_element

import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:ui';

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
    await ch.invokeMethod('requestRuntimePermissions');
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
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    model.loadFromPrefs().then((_) {
      if (mounted) setState(() => _loaded = true);
    });
  }

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
            home: _loaded
                ? (model.hasCompletedOnboarding ? const RootShell() : const OnboardingScreen())
                : const Scaffold(body: Center(child: CircularProgressIndicator())),
            routes: {
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

  Map<String, dynamic> toMap() => {
        'resolution': resolution.index,
        'fps': fps,
        'bitrateKbps': bitrateKbps,
        'includeAudio': includeAudio,
        'countdownSeconds': countdownSeconds,
      };

  factory RecordingSettings.fromMap(Map<String, dynamic> m) {
    final resIdx = (m['resolution'] ?? 0) as int;
    return RecordingSettings(
      resolution: VideoResolution.values[resIdx.clamp(0, VideoResolution.values.length - 1)],
      fps: (m['fps'] ?? 30) as int,
      bitrateKbps: (m['bitrateKbps'] ?? 8000) as int,
      includeAudio: (m['includeAudio'] ?? true) as bool,
      countdownSeconds: (m['countdownSeconds'] ?? 3) as int,
    );
  }
}

class RecordingSession {
  final DateTime startedAt;
  final DateTime endedAt;
  final Duration duration;
  final VideoResolution resolution;
  final int fps;
  final int bitrateKbps;
  final bool includeAudio;
  final String? filePath;

  RecordingSession({
    required this.startedAt,
    required this.endedAt,
    required this.duration,
    required this.resolution,
    required this.fps,
    required this.bitrateKbps,
    required this.includeAudio,
    this.filePath,
  });

  Map<String, dynamic> toMap() => {
        'startedAt': startedAt.toIso8601String(),
        'endedAt': endedAt.toIso8601String(),
        'durationSeconds': duration.inSeconds,
        'resolution': resolution.index,
        'fps': fps,
        'bitrateKbps': bitrateKbps,
        'includeAudio': includeAudio,
        'filePath': filePath,
      };

  factory RecordingSession.fromMap(Map<String, dynamic> m) {
    return RecordingSession(
      startedAt: DateTime.parse(m['startedAt'] as String),
      endedAt: DateTime.parse(m['endedAt'] as String),
      duration: Duration(seconds: (m['durationSeconds'] ?? 0) as int),
      resolution: VideoResolution.values[(m['resolution'] ?? 0) as int],
      fps: (m['fps'] ?? 30) as int,
      bitrateKbps: (m['bitrateKbps'] ?? 8000) as int,
      includeAudio: (m['includeAudio'] ?? true) as bool,
      filePath: m['filePath'] as String?,
    );
  }

  RecordingSession copyWith({
    DateTime? startedAt,
    DateTime? endedAt,
    Duration? duration,
    VideoResolution? resolution,
    int? fps,
    int? bitrateKbps,
    bool? includeAudio,
    String? filePath,
  }) {
    return RecordingSession(
      startedAt: startedAt ?? this.startedAt,
      endedAt: endedAt ?? this.endedAt,
      duration: duration ?? this.duration,
      resolution: resolution ?? this.resolution,
      fps: fps ?? this.fps,
      bitrateKbps: bitrateKbps ?? this.bitrateKbps,
      includeAudio: includeAudio ?? this.includeAudio,
      filePath: filePath ?? this.filePath,
    );
  }
}

class AppModel extends ChangeNotifier {
  static const _kThemeMode = 'themeMode';
  static const _kSettings = 'settings';
  static const _kHistory = 'history';
  static const _kOnboardingDone = 'onboardingDone';

  ThemeMode _themeMode = ThemeMode.system;
  final RecordingSettings settings = RecordingSettings();
  final List<RecordingSession> history = [];
  bool hasCompletedOnboarding = false;

  ThemeMode get themeMode => _themeMode;

  Future<void> loadFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    hasCompletedOnboarding = prefs.getBool(_kOnboardingDone) ?? false;

    final tm = prefs.getInt(_kThemeMode);
    if (tm != null) {
      _themeMode = ThemeMode.values[tm.clamp(0, ThemeMode.values.length - 1)];
    }

    final settingsJson = prefs.getString(_kSettings);
    if (settingsJson != null) {
      try {
        final map = json.decode(settingsJson) as Map<String, dynamic>;
        final loaded = RecordingSettings.fromMap(map);
        settings.resolution = loaded.resolution;
        settings.fps = loaded.fps;
        settings.bitrateKbps = loaded.bitrateKbps;
        settings.includeAudio = loaded.includeAudio;
        settings.countdownSeconds = loaded.countdownSeconds;
      } catch (_) {}
    }

    final historyJson = prefs.getString(_kHistory);
    history.clear();
    if (historyJson != null) {
      try {
        final list = (json.decode(historyJson) as List)
            .map((e) => (e as Map).cast<String, dynamic>())
            .toList();
        for (final m in list) {
          history.add(RecordingSession.fromMap(m));
        }
      } catch (_) {}
    }

    notifyListeners();
  }

  Future<void> _saveThemeMode() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kThemeMode, _themeMode.index);
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kSettings, json.encode(settings.toMap()));
  }

  Future<void> _saveHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kHistory, json.encode(history.map((e) => e.toMap()).toList()));
  }

  Future<void> _saveOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kOnboardingDone, hasCompletedOnboarding);
  }

  void setOnboardingCompleted(bool v) {
    hasCompletedOnboarding = v;
    _saveOnboarding();
    notifyListeners();
  }

  void setThemeMode(ThemeMode mode) {
    _themeMode = mode;
    _saveThemeMode();
    notifyListeners();
  }

  void addHistory(RecordingSession s) {
    history.insert(0, s);
    _saveHistory();
    notifyListeners();
  }

  void setHistoryFilePath(int index, String path) {
    if (index < 0 || index >= history.length) return;
    history[index] = history[index].copyWith(filePath: path);
    _saveHistory();
    notifyListeners();
  }

  void removeHistory(int index) {
    if (index < 0 || index >= history.length) return;
    history.removeAt(index);
    _saveHistory();
    notifyListeners();
  }

  void updateSettings(void Function(RecordingSettings) update) {
    update(settings);
    _saveSettings();
    notifyListeners();
  }
}

class RecordingController extends ChangeNotifier {
  static const MethodChannel _ch = MethodChannel('com.example.screen_recorder/recorder');
  static const EventChannel _eventCh = EventChannel('com.example.screen_recorder/events');
  final AppModel model;

  RecordingState state = RecordingState.idle;
  Duration elapsed = Duration.zero;
  int countdownRemaining = 0;

  Timer? _ticker;
  Timer? _countdownTimer;
  DateTime? _startedAt;
  StreamSubscription? _eventSubscription;

  RecordingController({required this.model}) {
    _eventSubscription = _eventCh.receiveBroadcastStream().listen(_onEvent);
  }

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
      // Hint to native code: save under Movies/screen_recorder on device storage
      'relativeDir': 'Movies/screen_recorder',
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

  void stop() async {
    if (state == RecordingState.idle) return;
    _ticker?.cancel();
    _countdownTimer?.cancel();

    String? savedPath;
    if (defaultTargetPlatform == TargetPlatform.android) {
      try {
        savedPath = await _ch.invokeMethod<String>('serviceStopAndGetPath');
      } catch (_) {
        try { await _ch.invokeMethod('serviceStop'); } catch (_) {}
      }
      if (savedPath != null) {
        try { await _ch.invokeMethod('scanFile', {'path': savedPath}); } catch (_) {}
      }
    } else {
      try { await _ch.invokeMethod('serviceStop'); } catch (_) {}
    }

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
        filePath: savedPath,
      );
      model.addHistory(session);
    }
    state = RecordingState.idle;
    elapsed = Duration.zero;
    countdownRemaining = 0;
    _startedAt = null;
    notifyListeners();
  }

  void _onEvent(dynamic event) async {
    if (event is String) {
      switch (event) {
        case 'paused':
          if (state == RecordingState.recording) {
            state = RecordingState.paused;
            _ticker?.cancel();
            notifyListeners();
          }
          break;
        case 'resumed':
          if (state == RecordingState.paused) {
            state = RecordingState.recording;
            _ticker?.cancel();
            _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
              elapsed += const Duration(seconds: 1);
              notifyListeners();
            });
            notifyListeners();
          }
          break;
        case 'stopped':
          if (state == RecordingState.recording || state == RecordingState.paused) {
            _ticker?.cancel();
            _countdownTimer?.cancel();
            final end = DateTime.now();
            final start = _startedAt ?? end;
            String? savedPath;
            if (defaultTargetPlatform == TargetPlatform.android) {
              try {
                savedPath = await _ch.invokeMethod<String>('resolveLastRecordingPath');
              } catch (_) {}
            }
            final session = RecordingSession(
              startedAt: start,
              endedAt: end,
              duration: elapsed,
              resolution: model.settings.resolution,
              fps: model.settings.fps,
              bitrateKbps: model.settings.bitrateKbps,
              includeAudio: model.settings.includeAudio,
              filePath: savedPath,
            );
            model.addHistory(session);
            state = RecordingState.idle;
            elapsed = Duration.zero;
            countdownRemaining = 0;
            _startedAt = null;
            notifyListeners();
          }
          break;
      }
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _countdownTimer?.cancel();
    _eventSubscription?.cancel();
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
