import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:provider/provider.dart';
import 'package:desktop_drop/desktop_drop.dart';
import '../services/app_state.dart';

class FileDropZone extends StatefulWidget {
  final Function(List<String>) onFilesDropped;
  final VoidCallback onTap;

  const FileDropZone({
    super.key,
    required this.onFilesDropped,
    required this.onTap,
  });

  @override
  State<FileDropZone> createState() => _FileDropZoneState();
}

class _FileDropZoneState extends State<FileDropZone> {
  bool _isDragOver = false;

  void _handleDrop(DropDoneDetails details) {
    final paths = details.files
        .map((file) => file.path)
        .where((path) => _isVideoFile(path))
        .toList();
    
    if (paths.isNotEmpty) {
      widget.onFilesDropped(paths);
    }
  }

  bool _isVideoFile(String path) {
    final ext = path.toLowerCase().split('.').last;
    return ['mp4', 'mov', 'avi', 'mkv', 'webm', 'wmv', 'flv', 'm4v'].contains(ext);
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final hasFiles = appState.selectedFiles.isNotEmpty;

    return GestureDetector(
      onTap: widget.onTap,
      child: DropTarget(
        onDragEntered: (details) {
          setState(() => _isDragOver = true);
        },
        onDragExited: (details) {
          setState(() => _isDragOver = false);
        },
        onDragDone: (details) {
          setState(() => _isDragOver = false);
          _handleDrop(details);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          decoration: BoxDecoration(
            color: _isDragOver
                ? Theme.of(context).colorScheme.primary.withOpacity(0.1)
                : const Color(0xFF1A1A1A),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _isDragOver
                  ? Theme.of(context).colorScheme.primary
                  : Colors.grey.withOpacity(0.3),
              width: _isDragOver ? 2 : 1,
              style: BorderStyle.solid,
            ),
          ),
          child: hasFiles
              ? _buildFilesPreview(appState)
              : _buildEmptyState(),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            _isDragOver ? Icons.file_download : Icons.cloud_upload_outlined,
            size: 48,
            color: _isDragOver
                ? Theme.of(context).colorScheme.primary
                : Colors.grey.withOpacity(0.5),
          ),
          const SizedBox(height: 16),
          Text(
            _isDragOver ? 'Drop files here' : 'Drag & Drop Videos',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: _isDragOver
                  ? Theme.of(context).colorScheme.primary
                  : Colors.grey.withOpacity(0.8),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'or click to browse',
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey.withOpacity(0.6),
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFF2A2A2A),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              'MP4, MOV, AVI, MKV, WebM',
              style: TextStyle(
                fontSize: 11,
                color: Colors.grey.withOpacity(0.5),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilesPreview(AppState appState) {
    final files = appState.selectedFiles;
    final displayCount = files.length > 4 ? 4 : files.length;

    return Stack(
      children: [
        // File Grid Preview
        Padding(
          padding: const EdgeInsets.all(12),
          child: GridView.builder(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
            ),
            itemCount: displayCount,
            itemBuilder: (context, index) {
              return Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF252525),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.video_file,
                        color: Colors.grey,
                        size: 24,
                      ),
                      const SizedBox(height: 4),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Text(
                          files[index].split('/').last.split('\\').last,
                          style: const TextStyle(fontSize: 10),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),

        // Overlay for more files
        if (files.length > 4)
          Positioned(
            right: 12,
            bottom: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '+${files.length - 4} more',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
          ),

        // Add More Button
        Positioned(
          left: 12,
          bottom: 12,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFF2A2A2A),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.add, size: 14),
                SizedBox(width: 4),
                Text(
                  'Add more',
                  style: TextStyle(fontSize: 11),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
