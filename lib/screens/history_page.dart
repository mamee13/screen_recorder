import 'package:flutter/material.dart';
import '../main.dart';

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

// Local helpers (since private helpers in main.dart are not visible here)
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
