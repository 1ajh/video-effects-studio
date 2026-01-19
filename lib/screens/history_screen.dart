import 'package:flutter/material.dart';
import '../services/preferences_service.dart';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';

/// Model for a processing history entry
class HistoryEntry {
  final String id;
  final String fileName;
  final String effectName;
  final String effectId;
  final String outputPath;
  final DateTime timestamp;
  final bool success;
  final String? errorMessage;

  HistoryEntry({
    required this.id,
    required this.fileName,
    required this.effectName,
    required this.effectId,
    required this.outputPath,
    required this.timestamp,
    required this.success,
    this.errorMessage,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'fileName': fileName,
    'effectName': effectName,
    'effectId': effectId,
    'outputPath': outputPath,
    'timestamp': timestamp.toIso8601String(),
    'success': success,
    'errorMessage': errorMessage,
  };

  factory HistoryEntry.fromJson(Map<String, dynamic> json) => HistoryEntry(
    id: json['id'],
    fileName: json['fileName'],
    effectName: json['effectName'],
    effectId: json['effectId'],
    outputPath: json['outputPath'],
    timestamp: DateTime.parse(json['timestamp']),
    success: json['success'],
    errorMessage: json['errorMessage'],
  );

  String toStorageString() => jsonEncode(toJson());
  
  factory HistoryEntry.fromStorageString(String str) => 
    HistoryEntry.fromJson(jsonDecode(str));
}

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  PreferencesService? _prefs;
  List<HistoryEntry> _entries = [];
  bool _isLoading = true;
  String _filter = 'all'; // 'all', 'success', 'failed'

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    _prefs = await PreferencesService.getInstance();
    _parseHistory();
    setState(() => _isLoading = false);
  }

  void _parseHistory() {
    _entries = _prefs?.processingHistory.map((str) {
      try {
        return HistoryEntry.fromStorageString(str);
      } catch (_) {
        return null;
      }
    }).whereType<HistoryEntry>().toList() ?? [];
  }

  List<HistoryEntry> get _filteredEntries {
    switch (_filter) {
      case 'success':
        return _entries.where((e) => e.success).toList();
      case 'failed':
        return _entries.where((e) => !e.success).toList();
      default:
        return _entries;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Processing History'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.filter_list),
            onSelected: (value) {
              setState(() => _filter = value);
            },
            itemBuilder: (context) => [
              CheckedPopupMenuItem(
                value: 'all',
                checked: _filter == 'all',
                child: const Text('All'),
              ),
              CheckedPopupMenuItem(
                value: 'success',
                checked: _filter == 'success',
                child: const Text('Successful'),
              ),
              CheckedPopupMenuItem(
                value: 'failed',
                checked: _filter == 'failed',
                child: const Text('Failed'),
              ),
            ],
          ),
          if (_entries.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep),
              tooltip: 'Clear History',
              onPressed: _showClearDialog,
            ),
        ],
      ),
      body: _filteredEntries.isEmpty
          ? _buildEmptyState()
          : _buildHistoryList(),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.history,
            size: 72,
            color: Colors.grey[600],
          ),
          const SizedBox(height: 16),
          Text(
            _entries.isEmpty
                ? 'No processing history yet'
                : 'No ${_filter == 'success' ? 'successful' : 'failed'} items',
            style: TextStyle(
              fontSize: 18,
              color: Colors.grey[500],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _entries.isEmpty
                ? 'Process some videos to see them here'
                : 'Try a different filter',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryList() {
    // Group entries by date
    final groupedEntries = <String, List<HistoryEntry>>{};
    for (final entry in _filteredEntries) {
      final dateKey = _formatDateHeader(entry.timestamp);
      groupedEntries.putIfAbsent(dateKey, () => []).add(entry);
    }

    return ListView.builder(
      itemCount: groupedEntries.length,
      itemBuilder: (context, index) {
        final dateKey = groupedEntries.keys.elementAt(index);
        final entries = groupedEntries[dateKey]!;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(
                dateKey,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ),
            ...entries.map((entry) => _buildHistoryItem(entry)),
          ],
        );
      },
    );
  }

  Widget _buildHistoryItem(HistoryEntry entry) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: entry.success
                ? Colors.green.withOpacity(0.1)
                : Colors.red.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            entry.success ? Icons.check_circle : Icons.error,
            color: entry.success ? Colors.green : Colors.red,
          ),
        ),
        title: Text(
          entry.fileName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              entry.effectName,
              style: TextStyle(color: Colors.grey[400]),
            ),
            Text(
              _formatTime(entry.timestamp),
              style: TextStyle(
                fontSize: 11,
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
        isThreeLine: true,
        trailing: entry.success
            ? IconButton(
                icon: const Icon(Icons.folder_open),
                tooltip: 'Open Location',
                onPressed: () => _openFileLocation(entry.outputPath),
              )
            : IconButton(
                icon: const Icon(Icons.info_outline),
                tooltip: 'View Error',
                onPressed: () => _showErrorDialog(entry),
              ),
        onTap: entry.success ? () => _showDetailsDialog(entry) : null,
      ),
    );
  }

  String _formatDateHeader(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final entryDate = DateTime(date.year, date.month, date.day);

    if (entryDate == today) {
      return 'Today';
    } else if (entryDate == yesterday) {
      return 'Yesterday';
    } else if (now.difference(date).inDays < 7) {
      return _weekday(date.weekday);
    } else {
      return '${date.month}/${date.day}/${date.year}';
    }
  }

  String _weekday(int day) {
    const days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    return days[day - 1];
  }

  String _formatTime(DateTime date) {
    final hour = date.hour > 12 ? date.hour - 12 : (date.hour == 0 ? 12 : date.hour);
    final period = date.hour >= 12 ? 'PM' : 'AM';
    final minute = date.minute.toString().padLeft(2, '0');
    return '$hour:$minute $period';
  }

  void _showClearDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear History'),
        content: const Text('Are you sure you want to clear all processing history?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.of(context).pop();
              await _prefs?.clearHistory();
              setState(() {
                _entries.clear();
              });
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
  }

  void _showErrorDialog(HistoryEntry entry) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Processing Error'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('File: ${entry.fileName}'),
            const SizedBox(height: 8),
            Text('Effect: ${entry.effectName}'),
            const SizedBox(height: 8),
            const Text('Error:', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFF2A2A2A),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                entry.errorMessage ?? 'Unknown error',
                style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _showDetailsDialog(HistoryEntry entry) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Processing Details'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildDetailRow('Input File', entry.fileName),
            _buildDetailRow('Effect', entry.effectName),
            _buildDetailRow('Output Path', entry.outputPath),
            _buildDetailRow('Processed', '${entry.timestamp.month}/${entry.timestamp.day}/${entry.timestamp.year} at ${_formatTime(entry.timestamp)}'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
          ElevatedButton.icon(
            icon: const Icon(Icons.folder_open, size: 18),
            label: const Text('Open Location'),
            onPressed: () {
              Navigator.of(context).pop();
              _openFileLocation(entry.outputPath);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[500],
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: const TextStyle(fontSize: 14),
          ),
        ],
      ),
    );
  }

  Future<void> _openFileLocation(String filePath) async {
    if (kIsWeb) return;

    try {
      final file = File(filePath);
      final directory = file.parent.path;

      if (Platform.isWindows) {
        await Process.run('explorer', ['/select,', filePath]);
      } else if (Platform.isMacOS) {
        await Process.run('open', ['-R', filePath]);
      } else if (Platform.isLinux) {
        await Process.run('xdg-open', [directory]);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open file location: $e')),
        );
      }
    }
  }
}
