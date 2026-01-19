import 'package:flutter_test/flutter_test.dart';
import 'package:video_effects_studio/services/preferences_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('PreferencesService', () {
    late PreferencesService preferencesService;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      preferencesService = PreferencesService();
      await preferencesService.init();
    });

    test('initializes with default values', () async {
      expect(preferencesService.isDarkMode, true);
      expect(preferencesService.outputDirectory, '');
      expect(preferencesService.defaultQuality, 'high');
      expect(preferencesService.autoCheckUpdates, true);
      expect(preferencesService.showNotifications, true);
      expect(preferencesService.recentFiles, isEmpty);
      expect(preferencesService.favoriteEffects, isEmpty);
      expect(preferencesService.processingHistory, isEmpty);
    });

    test('saves and loads dark mode preference', () async {
      await preferencesService.setDarkMode(false);
      expect(preferencesService.isDarkMode, false);

      await preferencesService.setDarkMode(true);
      expect(preferencesService.isDarkMode, true);
    });

    test('saves and loads output directory', () async {
      const testPath = '/test/output/path';
      await preferencesService.setOutputDirectory(testPath);
      expect(preferencesService.outputDirectory, testPath);
    });

    test('saves and loads default quality', () async {
      await preferencesService.setDefaultQuality('medium');
      expect(preferencesService.defaultQuality, 'medium');

      await preferencesService.setDefaultQuality('low');
      expect(preferencesService.defaultQuality, 'low');
    });

    test('saves and loads auto check updates', () async {
      await preferencesService.setAutoCheckUpdates(false);
      expect(preferencesService.autoCheckUpdates, false);

      await preferencesService.setAutoCheckUpdates(true);
      expect(preferencesService.autoCheckUpdates, true);
    });

    test('saves and loads show notifications', () async {
      await preferencesService.setShowNotifications(false);
      expect(preferencesService.showNotifications, false);

      await preferencesService.setShowNotifications(true);
      expect(preferencesService.showNotifications, true);
    });

    test('adds and retrieves recent files', () async {
      const file1 = '/path/to/video1.mp4';
      const file2 = '/path/to/video2.mp4';

      await preferencesService.addRecentFile(file1);
      expect(preferencesService.recentFiles, contains(file1));

      await preferencesService.addRecentFile(file2);
      expect(preferencesService.recentFiles, contains(file2));
      expect(preferencesService.recentFiles.length, 2);
    });

    test('limits recent files to maximum count', () async {
      // Add more than the max limit of recent files
      for (int i = 0; i < 25; i++) {
        await preferencesService.addRecentFile('/path/to/video$i.mp4');
      }

      // Should be limited to 20
      expect(preferencesService.recentFiles.length, lessThanOrEqualTo(20));
    });

    test('clears recent files', () async {
      await preferencesService.addRecentFile('/path/to/video.mp4');
      expect(preferencesService.recentFiles, isNotEmpty);

      await preferencesService.clearRecentFiles();
      expect(preferencesService.recentFiles, isEmpty);
    });

    test('adds and removes favorite effects', () async {
      const effectId = 'vocoder';

      await preferencesService.addFavoriteEffect(effectId);
      expect(preferencesService.favoriteEffects, contains(effectId));
      expect(preferencesService.isFavoriteEffect(effectId), true);

      await preferencesService.removeFavoriteEffect(effectId);
      expect(preferencesService.favoriteEffects, isNot(contains(effectId)));
      expect(preferencesService.isFavoriteEffect(effectId), false);
    });

    test('toggles favorite effect', () async {
      const effectId = 'g_major';

      // Toggle on
      await preferencesService.toggleFavoriteEffect(effectId);
      expect(preferencesService.isFavoriteEffect(effectId), true);

      // Toggle off
      await preferencesService.toggleFavoriteEffect(effectId);
      expect(preferencesService.isFavoriteEffect(effectId), false);
    });

    test('adds processing history entries', () async {
      await preferencesService.addProcessingHistoryEntry(
        inputFile: '/input/video.mp4',
        outputFile: '/output/video_processed.mp4',
        effectId: 'vocoder',
        effectName: 'Vocoder',
        success: true,
      );

      expect(preferencesService.processingHistory, isNotEmpty);
      
      final entry = preferencesService.processingHistory.first;
      expect(entry['inputFile'], '/input/video.mp4');
      expect(entry['outputFile'], '/output/video_processed.mp4');
      expect(entry['effectId'], 'vocoder');
      expect(entry['effectName'], 'Vocoder');
      expect(entry['success'], true);
      expect(entry['timestamp'], isNotNull);
    });

    test('clears processing history', () async {
      await preferencesService.addProcessingHistoryEntry(
        inputFile: '/input/video.mp4',
        outputFile: '/output/video.mp4',
        effectId: 'test',
        effectName: 'Test',
        success: true,
      );
      expect(preferencesService.processingHistory, isNotEmpty);

      await preferencesService.clearProcessingHistory();
      expect(preferencesService.processingHistory, isEmpty);
    });

    test('clears all data', () async {
      await preferencesService.setDarkMode(false);
      await preferencesService.setOutputDirectory('/test');
      await preferencesService.addRecentFile('/video.mp4');
      await preferencesService.addFavoriteEffect('vocoder');

      await preferencesService.clearAllData();

      expect(preferencesService.isDarkMode, true);
      expect(preferencesService.outputDirectory, '');
      expect(preferencesService.recentFiles, isEmpty);
      expect(preferencesService.favoriteEffects, isEmpty);
    });
  });
}
