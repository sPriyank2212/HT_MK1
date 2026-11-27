/// The font the PDF reports fall back to for symbols the default font lacks.
///
/// The reports are drawn in the `pdf` package's default core font (Helvetica,
/// like the customer's own reports), which has no glyph for the Greek capital
/// omega, so "mΩ" would print as a missing-glyph box. Roboto (bundled in
/// `assets/fonts/`, Apache 2.0 licence next to it) has it; it is added as the
/// FALLBACK font, so every character Helvetica has is still drawn in Helvetica
/// and only the omega comes from Roboto.
library;

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/widgets.dart' as pw;

/// The report theme (Helvetica + Roboto fallback), or null when the asset
/// cannot be read (e.g. a `flutter test` that never initialised the binding) -
/// the report is then drawn in the default font alone, as it was before.
Future<pw.ThemeData?> loadPdfTheme() async {
  try {
    final roboto = await rootBundle.load('assets/fonts/Roboto-Regular.ttf');
    return pw.ThemeData.withFont(fontFallback: [pw.Font.ttf(roboto)]);
  } catch (_) {
    return null;
  }
}
