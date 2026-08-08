/// The native "open file" dialog for loading a netlist from disk.
///
/// Isolated to this one file, the same way `serial_transport.dart` isolates
/// `flutter_libserialport`: `AppState.pickNetlistFile` is an injectable
/// function typed as a plain record — not a class defined here — so
/// `app_state.dart` and its tests never import `file_picker` or touch its
/// platform channel (see `AppState.listPorts`/`PortEntry` for the identical
/// pattern with the serial port list). Only `main.dart` wires this in, for
/// the real app.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

/// Opens the native file-open dialog filtered to spreadsheet netlists, reads
/// the chosen file and returns its name and bytes. Null means the operator
/// cancelled — never thrown for that case, only for a read failure once a
/// file was actually chosen.
Future<(String name, Uint8List bytes)?> pickNetlistFile() async {
  final result = await FilePicker.pickFiles(
    dialogTitle: 'Select a netlist file',
    type: FileType.custom,
    allowedExtensions: ['xlsx', 'xls'],
  );
  if (result == null) return null; // operator cancelled
  final picked = result.files.single;
  final path = picked.path;
  final bytes = picked.bytes ?? (path != null ? await File(path).readAsBytes() : null);
  if (bytes == null) return null;
  return (picked.name, bytes);
}
