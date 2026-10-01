import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'widgets/common.dart';

/// Native file dialogs that fail politely: some Linux setups have no
/// desktop portal to show one, and the plugin throws instead.
Future<List<PlatformFile>> pickFilesSafely(
  BuildContext context, {
  String? dialogTitle,
  FileType type = FileType.any,
  List<String>? allowedExtensions,
}) async {
  try {
    return await FilePicker.pickFiles(dialogTitle: dialogTitle, type: type, allowedExtensions: allowedExtensions);
  } catch (e) {
    if (context.mounted) _explain(context, e);
    return const [];
  }
}

Future<String?> pickDirectorySafely(BuildContext context, {String? dialogTitle, String? initialDirectory}) async {
  try {
    return await FilePicker.getDirectoryPath(dialogTitle: dialogTitle, initialDirectory: initialDirectory);
  } catch (e) {
    if (context.mounted) _explain(context, e);
    return null;
  }
}

void _explain(BuildContext context, Object error) {
  debugPrint('File dialog failed: $error');
  showMessage(
    context,
    "This system couldn't open a file dialog. Drag files onto the window instead "
    '(on Linux, installing xdg-desktop-portal enables the dialog).',
    error: true,
  );
}
