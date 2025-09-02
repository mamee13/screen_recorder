import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../main.dart';

// Local helpers for this screen
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
              onChanged: (v) { if (v != null) { model.updateSettings((s) => s.resolution = v); }},
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
              onChanged: (v) { if (v != null) { model.updateSettings((s) => s.fps = v); }},
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
              onChanged: (v) { if (v != null) { model.updateSettings((s) => s.bitrateKbps = v); }},
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
            onChanged: (v) async {
              model.updateSettings((s) => s.includeAudio = v);
              if (v) {
                try { await const MethodChannel('com.example.screen_recorder/recorder').invokeMethod('requestRecordAudioPermission'); } catch (_) {}
              }
            },
          ),
          _Tile(
            title: 'Countdown',
            subtitle: '${s.countdownSeconds} seconds',
            onTap: () async {
              final v = await showDialog<int>(context: context, builder: (_) => _CountdownDialog(initial: s.countdownSeconds));
              if (v != null) { model.updateSettings((s) => s.countdownSeconds = v); }
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
              if (mode != null) AppScope.of(context).model.setThemeMode(mode);
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
