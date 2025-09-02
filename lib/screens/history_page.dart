import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../main.dart';
import 'video_player_page.dart';

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
                      subtitle: Text('${_resLabel(s.resolution)} • ${s.fps} FPS • ${(s.bitrateKbps / 1000).toStringAsFixed(0)} Mbps${s.includeAudio ? ' • Audio' : ''}${s.filePath != null ? '\n${s.filePath}' : ''}'),
                      isThreeLine: s.filePath != null,
                      trailing: FilledButton.icon(
                        onPressed: () async {
                          var path = s.filePath;
                          // Try resolve from native if missing
                          if (path == null) {
                            try {
                              const ch = MethodChannel('com.example.screen_recorder/recorder');
                              path = await ch.invokeMethod<String>('resolveLastRecordingPath');
                              if (path != null) {
                                AppScope.of(context).model.setHistoryFilePath(i, path);
                              }
                            } catch (_) {}
                          }
                          if (path != null && context.mounted) {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => VideoPlayerPage(
                                  pathOrUri: path!,
                                  title: _formatDateTime(s.startedAt),
                                ),
                              ),
                            );
                          }
                        },
                        icon: const Icon(Icons.play_arrow_rounded),
                        label: const Text('Play'),
                      ),
                      onTap: () async {
                        var path = s.filePath;
                        // Try resolve from native if missing
                        if (path == null) {
                          try {
                            const ch = MethodChannel('com.example.screen_recorder/recorder');
                            // Use a lookup by timestamp if you implement it natively
                            path = await ch.invokeMethod<String>('resolveLastRecordingPath');
                            if (path != null) {
                              // Persist back into the model for future use
                              AppScope.of(context).model.setHistoryFilePath(i, path);
                            }
                          } catch (_) {}
                        }
                        if (path != null && context.mounted) {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => VideoPlayerPage(
                                pathOrUri: path!,
                                title: _formatDateTime(s.startedAt),
                              ),
                            ),
                          );
                        }
                      },
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

// Helper to check if file exists
bool _fileExists(String? path) {
  if (path == null) return true; // Can be resolved later
  if (path.startsWith('content://')) return true; // Assume content URIs are valid
  return File(path).existsSync();
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

