import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import '../services/app_state.dart';
import '../widgets/effect_card.dart';
import '../widgets/file_drop_zone.dart';
import '../widgets/processing_dialog.dart';
import '../widgets/parameter_editor.dart';
import '../widgets/update_banner.dart';
import 'settings_screen.dart';
import 'history_screen.dart';
import 'about_screen.dart';
import 'help_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _pickFiles() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.video,
      allowMultiple: true,
    );

    if (result != null && mounted) {
      final paths = result.paths.whereType<String>().toList();
      context.read<AppState>().addFiles(paths);
    }
  }

  void _startProcessing() {
    final appState = context.read<AppState>();
    
    if (appState.selectedFiles.isEmpty) {
      _showSnackBar('Please select at least one video file');
      return;
    }

    if (appState.selectedEffect == null) {
      _showSnackBar('Please select an effect mode');
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const ProcessingDialog(),
    );

    appState.startProcessing();
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // Update Banner
            Consumer<AppState>(
              builder: (context, appState, _) {
                if (appState.updateInfo?.isUpdateAvailable == true) {
                  return UpdateBanner(updateInfo: appState.updateInfo!);
                }
                return const SizedBox.shrink();
              },
            ),

            // App Bar
            _buildAppBar(),

            // Main Content
            Expanded(
              child: Row(
                children: [
                  // Left Panel - File Selection
                  Expanded(
                    flex: 3,
                    child: _buildFilePanel(),
                  ),

                  // Middle Panel - Effects Grid
                  Expanded(
                    flex: 5,
                    child: _buildEffectsPanel(),
                  ),

                  // Right Panel - Parameters & Actions
                  Expanded(
                    flex: 3,
                    child: _buildControlPanel(),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAppBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Row(
        children: [
          // Logo & Title
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Theme.of(context).colorScheme.primary,
                      Theme.of(context).colorScheme.secondary,
                    ],
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.video_settings, color: Colors.white, size: 24),
              ),
              const SizedBox(width: 12),
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Video Effects Studio',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    'by AJH',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey,
                    ),
                  ),
                ],
              ),
            ],
          ),

          const Spacer(),

          // Search Bar
          SizedBox(
            width: 300,
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search effects...',
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 20),
                        onPressed: () {
                          _searchController.clear();
                          context.read<AppState>().setSearchQuery('');
                        },
                      )
                    : null,
              ),
              onChanged: (value) {
                context.read<AppState>().setSearchQuery(value);
              },
            ),
          ),

          const SizedBox(width: 16),

          // History Button
          IconButton(
            icon: const Icon(Icons.history_outlined),
            tooltip: 'Processing History',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const HistoryScreen()),
              );
            },
          ),

          // Help Button
          IconButton(
            icon: const Icon(Icons.help_outline),
            tooltip: 'Help',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const HelpScreen()),
              );
            },
          ),

          // Settings Button
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            tooltip: 'More options',
            onSelected: (value) {
              switch (value) {
                case 'settings':
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const SettingsScreen()),
                  );
                  break;
                case 'about':
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const AboutScreen()),
                  );
                  break;
                case 'updates':
                  context.read<AppState>().checkForUpdates(force: true);
                  _showSnackBar('Checking for updates...');
                  break;
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'settings',
                child: ListTile(
                  leading: Icon(Icons.settings),
                  title: Text('Settings'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuItem(
                value: 'updates',
                child: ListTile(
                  leading: Icon(Icons.update),
                  title: Text('Check for Updates'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuItem(
                value: 'about',
                child: ListTile(
                  leading: Icon(Icons.info_outline),
                  title: Text('About'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFilePanel() {
    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.folder_open, size: 20),
                const SizedBox(width: 8),
                const Text(
                  'Input Files',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                Consumer<AppState>(
                  builder: (context, appState, _) {
                    if (appState.selectedFiles.isNotEmpty) {
                      return TextButton.icon(
                        icon: const Icon(Icons.clear_all, size: 18),
                        label: const Text('Clear'),
                        onPressed: appState.clearFiles,
                      );
                    }
                    return const SizedBox.shrink();
                  },
                ),
              ],
            ),
            const SizedBox(height: 16),

            // File Drop Zone
            Expanded(
              child: FileDropZone(
                onFilesDropped: (files) {
                  context.read<AppState>().addFiles(files);
                },
                onTap: _pickFiles,
              ),
            ),

            const SizedBox(height: 16),

            // Selected Files List
            Consumer<AppState>(
              builder: (context, appState, _) {
                if (appState.selectedFiles.isEmpty) {
                  return const SizedBox.shrink();
                }

                return Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${appState.selectedFiles.length} file(s) selected',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Expanded(
                        child: ListView.builder(
                          itemCount: appState.selectedFiles.length,
                          itemBuilder: (context, index) {
                            final file = appState.selectedFiles[index];
                            final fileName = file.split('/').last.split('\\').last;
                            
                            return ListTile(
                              dense: true,
                              leading: const Icon(Icons.video_file, size: 20),
                              title: Text(
                                fileName,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 13),
                              ),
                              trailing: IconButton(
                                icon: const Icon(Icons.close, size: 18),
                                onPressed: () => appState.removeFile(file),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEffectsPanel() {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Category Filter
            Consumer<AppState>(
              builder: (context, appState, _) {
                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _buildCategoryChip('All', '', appState),
                      ...appState.categories.map((cat) => 
                        _buildCategoryChip(cat, cat, appState)
                      ),
                    ],
                  ),
                );
              },
            ),

            const SizedBox(height: 16),

            // Effects Grid
            Expanded(
              child: Consumer<AppState>(
                builder: (context, appState, _) {
                  final effects = appState.filteredEffects;

                  if (effects.isEmpty) {
                    return const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.search_off, size: 48, color: Colors.grey),
                          SizedBox(height: 16),
                          Text(
                            'No effects found',
                            style: TextStyle(color: Colors.grey),
                          ),
                        ],
                      ),
                    );
                  }

                  return GridView.builder(
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      childAspectRatio: 1.3,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                    ),
                    itemCount: effects.length,
                    itemBuilder: (context, index) {
                      final effect = effects[index];
                      final isSelected = appState.selectedEffect?.id == effect.id;

                      return EffectCard(
                        effect: effect,
                        isSelected: isSelected,
                        onTap: () => appState.selectEffect(effect),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoryChip(String label, String value, AppState appState) {
    final isSelected = appState.categoryFilter == value;
    
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Text(label),
        selected: isSelected,
        onSelected: (_) => appState.setCategoryFilter(value),
        backgroundColor: const Color(0xFF2A2A2A),
        selectedColor: Theme.of(context).colorScheme.primary.withOpacity(0.3),
        checkmarkColor: Theme.of(context).colorScheme.primary,
      ),
    );
  }

  Widget _buildControlPanel() {
    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.tune, size: 20),
                SizedBox(width: 8),
                Text(
                  'Effect Settings',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // Selected Effect Info
            Consumer<AppState>(
              builder: (context, appState, _) {
                if (appState.selectedEffect == null) {
                  return const Expanded(
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.touch_app, size: 48, color: Colors.grey),
                          SizedBox(height: 16),
                          Text(
                            'Select an effect',
                            style: TextStyle(color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                final effect = appState.selectedEffect!;

                return Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Effect Title
                      Text(
                        effect.name,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        effect.description,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[400],
                        ),
                      ),

                      if (effect.requiresDesktop) ...[
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.orange.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.computer, size: 14, color: Colors.orange),
                              SizedBox(width: 4),
                              Text(
                                'Desktop Only',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.orange,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],

                      const SizedBox(height: 16),
                      const Divider(),
                      const SizedBox(height: 16),

                      // Parameters
                      if (effect.parameters.isNotEmpty) ...[
                        const Text(
                          'Parameters',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Expanded(
                          child: ListView.builder(
                            itemCount: effect.parameters.length,
                            itemBuilder: (context, index) {
                              final param = effect.parameters[index];
                              return ParameterEditor(
                                parameter: param,
                                value: appState.effectParameters[param.id],
                                onChanged: (value) {
                                  appState.setParameter(param.id, value);
                                },
                              );
                            },
                          ),
                        ),
                      ] else ...[
                        const Expanded(
                          child: Center(
                            child: Text(
                              'No adjustable parameters',
                              style: TextStyle(
                                color: Colors.grey,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                );
              },
            ),

            const SizedBox(height: 16),

            // Process Button
            Consumer<AppState>(
              builder: (context, appState, _) {
                final canProcess = appState.selectedFiles.isNotEmpty &&
                    appState.selectedEffect != null &&
                    !appState.isProcessing;

                return SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: canProcess ? _startProcessing : null,
                    icon: const Icon(Icons.play_arrow),
                    label: Text(
                      appState.selectedFiles.length > 1
                          ? 'Process ${appState.selectedFiles.length} Files'
                          : 'Process Video',
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
