/// Netlist file formats beyond `.xlsx`: **CSV** and **XLS** in, and all three
/// out.
///
/// The netlist parser (`netlist_file.dart`) reads one thing: an `.xlsx`
/// workbook. Rather than teach it three readers, [toXlsxBytes] turns whatever
/// the operator picked into `.xlsx` bytes first, and [encodeSheet] writes a
/// header + rows grid as `.csv`, `.xls` or `.xlsx`.
///
/// **XLS.** `.xls` is written as *SpreadsheetML 2003* (an XML workbook that
/// Excel opens as `.xls`), and read back the same way. A genuine binary
/// (BIFF, "Excel 97-2003") `.xls` cannot be read here — there is no BIFF
/// reader in the app — and is refused with a message telling the operator to
/// save it as `.xlsx` or `.csv`. An `.xls` that is really an `.xlsx` renamed
/// is detected by its content and read normally.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:excel/excel.dart';

/// The three spreadsheet formats a netlist can be loaded from or saved as.
const List<String> kNetlistExtensions = ['xlsx', 'xls', 'csv'];

/// Lower-case extension of [path] without the dot; `''` if it has none.
String extensionOf(String path) {
  final name = path.split(RegExp(r'[\\/]')).last;
  final i = name.lastIndexOf('.');
  return i < 0 ? '' : name.substring(i + 1).toLowerCase();
}

/// [path] with its extension forced to one of [kNetlistExtensions]
/// (`.xlsx` when it has none or an unknown one).
String withNetlistExtension(String path) {
  final e = extensionOf(path);
  return kNetlistExtensions.contains(e) ? path : '$path.xlsx';
}

bool _isZip(Uint8List b) => b.length > 3 && b[0] == 0x50 && b[1] == 0x4B;

bool _isBiff(Uint8List b) =>
    b.length > 7 &&
    b[0] == 0xD0 &&
    b[1] == 0xCF &&
    b[2] == 0x11 &&
    b[3] == 0xE0;

String _decode(Uint8List b) {
  var s = utf8.decode(b, allowMalformed: true);
  if (s.isNotEmpty && s.codeUnitAt(0) == 0xFEFF) s = s.substring(1);
  return s;
}

/// [bytes] of a netlist file named [fileName], as `.xlsx` bytes the parser can
/// read. Throws [FormatException] (with an operator-readable message) if the
/// content is a format that cannot be read.
Uint8List toXlsxBytes(Uint8List bytes, String fileName) {
  if (_isZip(bytes)) return bytes; // .xlsx, whatever it was named
  if (_isBiff(bytes)) {
    throw FormatException(
        '$fileName is a binary Excel 97-2003 .xls, which this app cannot '
        'read. Open it in Excel and save it as .xlsx or .csv, then load that.');
  }
  final text = _decode(bytes);
  final head = text.trimLeft();
  if (head.startsWith('<?xml') || head.startsWith('<Workbook')) {
    return _gridToXlsx(_parseSpreadsheetMl(text));
  }
  if (extensionOf(fileName) == 'xls' && !text.contains(',') &&
      !text.contains('\t') && !text.contains(';')) {
    throw FormatException('$fileName is not a readable .xls file.');
  }
  return _gridToXlsx(parseCsv(text));
}

// ---------------------------------------------------------------------------
// CSV
// ---------------------------------------------------------------------------

/// Parses CSV [text] (RFC 4180 quoting; the delimiter — comma, semicolon or
/// tab — is whichever the header line uses most) into a grid of strings.
List<List<String>> parseCsv(String text) {
  final firstLine = text.split(RegExp(r'\r?\n')).firstWhere(
        (l) => l.trim().isNotEmpty,
        orElse: () => '',
      );
  var delim = ',';
  var best = -1;
  for (final d in const [',', ';', '\t']) {
    final n = d.allMatches(firstLine).length;
    if (n > best) {
      best = n;
      delim = d;
    }
  }
  final rows = <List<String>>[];
  var row = <String>[];
  final cell = StringBuffer();
  var quoted = false;
  var i = 0;
  void endCell() {
    row.add(cell.toString());
    cell.clear();
  }

  void endRow() {
    endCell();
    if (row.any((c) => c.trim().isNotEmpty)) rows.add(row);
    row = <String>[];
  }

  while (i < text.length) {
    final ch = text[i];
    if (quoted) {
      if (ch == '"') {
        if (i + 1 < text.length && text[i + 1] == '"') {
          cell.write('"');
          i++;
        } else {
          quoted = false;
        }
      } else {
        cell.write(ch);
      }
    } else if (ch == '"') {
      quoted = true;
    } else if (ch == delim) {
      endCell();
    } else if (ch == '\n') {
      endRow();
    } else if (ch == '\r') {
      // swallowed: \r\n and a lone \r both end the row at the \n / next char
      if (i + 1 >= text.length || text[i + 1] != '\n') endRow();
    } else {
      cell.write(ch);
    }
    i++;
  }
  if (cell.isNotEmpty || row.isNotEmpty) endRow();
  return rows;
}

String _csvField(Object? v) {
  final s = v == null ? '' : '$v';
  return s.contains(RegExp(r'[",\r\n]')) ? '"${s.replaceAll('"', '""')}"' : s;
}

// ---------------------------------------------------------------------------
// SpreadsheetML 2003 (.xls written by this app)
// ---------------------------------------------------------------------------

String _xml(Object? v) => (v == null ? '' : '$v')
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;');

String _unxml(String s) => s
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&apos;', "'")
    .replaceAll('&amp;', '&');

List<List<String>> _parseSpreadsheetMl(String xml) {
  final rows = <List<String>>[];
  final rowRe = RegExp(r'<(?:\w+:)?Row\b[^>]*?(?:/>|>(.*?)</(?:\w+:)?Row>)',
      dotAll: true);
  final cellRe = RegExp(
      r'<(?:\w+:)?Cell\b([^>]*?)(?:/>|>(.*?)</(?:\w+:)?Cell>)',
      dotAll: true);
  final dataRe =
      RegExp(r'<(?:\w+:)?Data\b[^>]*>(.*?)</(?:\w+:)?Data>', dotAll: true);
  final idxRe = RegExp(r'Index="(\d+)"');
  for (final r in rowRe.allMatches(xml)) {
    final body = r.group(1) ?? '';
    final row = <String>[];
    for (final c in cellRe.allMatches(body)) {
      final idx = idxRe.firstMatch(c.group(1) ?? '');
      if (idx != null) {
        final want = int.parse(idx.group(1)!) - 1;
        while (row.length < want) {
          row.add('');
        }
      }
      final d = dataRe.firstMatch(c.group(2) ?? '');
      row.add(d == null ? '' : _unxml(d.group(1) ?? ''));
    }
    if (row.any((c) => c.trim().isNotEmpty)) rows.add(row);
  }
  if (rows.isEmpty) {
    throw const FormatException('The .xls file has no rows.');
  }
  return rows;
}

String _spreadsheetMl(List<List<Object?>> rows) {
  final b = StringBuffer()
    ..writeln('<?xml version="1.0" encoding="UTF-8"?>')
    ..writeln('<?mso-application progid="Excel.Sheet"?>')
    ..writeln('<Workbook xmlns="urn:schemas-microsoft-com:office:spreadsheet" '
        'xmlns:ss="urn:schemas-microsoft-com:office:spreadsheet">')
    ..writeln('<Worksheet ss:Name="Netlist"><Table>');
  for (final r in rows) {
    b.write('<Row>');
    for (final v in r) {
      final isNum = v is num;
      b.write('<Cell><Data ss:Type="${isNum ? 'Number' : 'String'}">'
          '${_xml(v)}</Data></Cell>');
    }
    b.writeln('</Row>');
  }
  b.writeln('</Table></Worksheet></Workbook>');
  return b.toString();
}

// ---------------------------------------------------------------------------
// grid <-> xlsx
// ---------------------------------------------------------------------------

CellValue _cell(Object? v) {
  if (v == null) return TextCellValue('');
  if (v is int) return IntCellValue(v);
  if (v is double) return DoubleCellValue(v);
  final s = '$v';
  final t = s.trim();
  final i = int.tryParse(t);
  if (i != null) return IntCellValue(i);
  final d = double.tryParse(t);
  if (d != null) return DoubleCellValue(d);
  return TextCellValue(s);
}

Uint8List _gridToXlsx(List<List<Object?>> rows) {
  final book = Excel.createExcel();
  final sheet = book.getDefaultSheet()!;
  for (final r in rows) {
    book.appendRow(sheet, [for (final v in r) _cell(v)]);
  }
  return Uint8List.fromList(book.encode()!);
}

/// Writes a header + rows grid in the format [ext] (`csv`, `xls`; anything
/// else is `xlsx`). Cell values may be `int`, `double` or `String`.
Uint8List encodeSheet(List<List<Object?>> rows, String ext) {
  switch (ext.toLowerCase()) {
    case 'csv':
      final text = [for (final r in rows) r.map(_csvField).join(',')].join('\r\n');
      return Uint8List.fromList(utf8.encode('﻿$text\r\n'));
    case 'xls':
      return Uint8List.fromList(utf8.encode(_spreadsheetMl(rows)));
    default:
      return _gridToXlsx(rows);
  }
}
