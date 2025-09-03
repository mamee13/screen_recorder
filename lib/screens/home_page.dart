import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../main.dart';

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
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                FilterChip(
                  avatar: const Icon(Icons.mic, size: 18),
                  label: const Text('Audio'),
                  selected: s.includeAudio,
                  onSelected: (sel) async {
                    model.updateSettings((s) => s.includeAudio = sel);
                    if (sel) {
                      try { await const MethodChannel('com.example.screen_recorder/recorder').invokeMethod('requestRecordAudioPermission'); } catch (_) {}
                    }
                  },
                ),
                const SizedBox(width: 16),
                InputChip(
                  avatar: const Icon(Icons.timer, size: 18),
                  label: Text('Countdown: ${s.countdownSeconds}s'),
                  onPressed: () async {
                    final v = await showDialog<int>(context: context, builder: (_) => _CountdownDialog(initial: s.countdownSeconds));
                    if (v != null) {
                      model.updateSettings((s) => s.countdownSeconds = v);
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
            Text('After initial run, a persistent notification with quick actions (Start, Pause/Resume, Stop) will be available once the record starts.', style: textStyle),
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
  final IconData? icon;

  const _ChipDropdown({required this.label, required this.value, required this.items, required this.onChanged, this.icon});

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
        avatar: icon != null ? Icon(icon, size: 18) : null,
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

// Local helpers for this screen
String _formatDuration(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  if (h > 0) {
    return '$h:$m:$s';
  }
  return '$m:$s';
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
