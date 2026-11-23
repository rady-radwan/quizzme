import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

/// One worksheet as a grid of strings. `rows[i][j]` is the text of row i,
/// column j (both 0-based). Missing cells are empty strings.
class XlsxSheet {
  XlsxSheet(this.name, this.rows);
  final String name;
  final List<XlsxRow> rows;
}

class XlsxRow {
  XlsxRow(this.rowNumber, this.cells);

  /// 1-based row number as shown in Excel.
  final int rowNumber;
  final List<String> cells;

  String cell(int i) => i >= 0 && i < cells.length ? cells[i] : '';
  bool get isBlank => cells.every((c) => c.trim().isEmpty);
}

class XlsxFormatException implements Exception {
  XlsxFormatException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Minimal, dependency-light reader for Office Open XML workbooks (.xlsx).
/// Reads every worksheet, shared strings, inline strings, booleans and
/// numbers. Formulas are read from their cached value. Styles and dates are
/// not interpreted (question files are text).
class XlsxReader {
  static const int maxUncompressedBytes = 200 * 1024 * 1024;

  static List<XlsxSheet> read(List<int> bytes) {
    final archive = decodeZip(bytes);
    var total = 0;
    for (final f in archive.files) {
      total += f.size;
    }
    if (total > maxUncompressedBytes) {
      throw XlsxFormatException('The workbook is too large to import safely.');
    }

    String? part(String name) {
      final n = name.startsWith('/') ? name.substring(1) : name;
      final f = archive.findFile(n);
      if (f == null || !f.isFile) return null;
      return utf8.decode(f.content as List<int>, allowMalformed: true);
    }

    final workbookXml = part('xl/workbook.xml');
    if (workbookXml == null) {
      throw XlsxFormatException(
          'The selected file could not be read. Please check that it is a valid Excel workbook (.xlsx).');
    }

    // Relationship id -> target path.
    final rels = <String, String>{};
    final relsXml = part('xl/_rels/workbook.xml.rels');
    if (relsXml != null) {
      final doc = XmlDocument.parse(relsXml);
      for (final r in doc.findAllElements('Relationship')) {
        final id = r.getAttribute('Id');
        final target = r.getAttribute('Target');
        if (id != null && target != null) rels[id] = target;
      }
    }

    final shared = <String>[];
    final sstXml = part('xl/sharedStrings.xml');
    if (sstXml != null) {
      final doc = XmlDocument.parse(sstXml);
      for (final si in doc.findAllElements('si')) {
        shared.add(_stringItemText(si));
      }
    }

    final sheets = <XlsxSheet>[];
    final wb = XmlDocument.parse(workbookXml);
    var index = 0;
    for (final s in wb.findAllElements('sheet')) {
      index++;
      final name = s.getAttribute('name') ?? 'Sheet$index';
      String? rid;
      for (final a in s.attributes) {
        if (a.name.local == 'id') rid = a.value;
      }
      var target = rid != null ? rels[rid] : null;
      target ??= 'worksheets/sheet$index.xml';
      final path = target.startsWith('/')
          ? target.substring(1)
          : (target.startsWith('xl/') ? target : 'xl/$target');
      final xml = part(path);
      if (xml == null) continue;
      sheets.add(XlsxSheet(name, _readSheet(xml, shared)));
    }
    if (sheets.isEmpty) {
      throw XlsxFormatException('The workbook does not contain any worksheets.');
    }
    return sheets;
  }

  /// Concatenates the text runs of a shared-string or inline-string item,
  /// skipping phonetic (ruby) runs.
  static String _stringItemText(XmlElement si) {
    final b = StringBuffer();
    for (final t in si.findAllElements('t')) {
      final parent = t.parentElement;
      if (parent != null && parent.name.local == 'rPh') continue;
      b.write(t.innerText);
    }
    return b.toString();
  }

  static List<XlsxRow> _readSheet(String xml, List<String> shared) {
    final doc = XmlDocument.parse(xml);
    final rows = <XlsxRow>[];
    var implicitRow = 0;
    for (final row in doc.findAllElements('row')) {
      implicitRow++;
      final rn = int.tryParse(row.getAttribute('r') ?? '') ?? implicitRow;
      implicitRow = rn;
      final cells = <String>[];
      var implicitCol = -1;
      for (final c in row.findElements('c')) {
        implicitCol++;
        final ref = c.getAttribute('r');
        final col = ref != null ? columnIndex(ref) : implicitCol;
        implicitCol = col;
        final t = c.getAttribute('t');
        String value;
        if (t == 'inlineStr') {
          final inl = c.getElement('is');
          value = inl == null ? '' : _stringItemText(inl);
        } else {
          final v = c.getElement('v')?.innerText ?? '';
          if (t == 's') {
            final i = int.tryParse(v);
            value = (i != null && i >= 0 && i < shared.length) ? shared[i] : '';
          } else if (t == 'b') {
            value = v == '1' ? 'TRUE' : 'FALSE';
          } else if (t == 'str' || t == 'e') {
            value = v;
          } else {
            value = _formatNumber(v);
          }
        }
        while (cells.length < col) {
          cells.add('');
        }
        if (cells.length == col) {
          cells.add(value);
        } else {
          cells[col] = value;
        }
      }
      rows.add(XlsxRow(rn, cells));
    }
    return rows;
  }

  /// Unzips [bytes] or throws a friendly [XlsxFormatException].
  static Archive decodeZip(List<int> bytes) {
    try {
      return ZipDecoder().decodeBytes(bytes);
    } catch (_) {
      throw XlsxFormatException(
          'The selected file could not be read. Please check that it is a valid Excel workbook (.xlsx).');
    }
  }

  /// "3.0" -> "3", "1E3" -> "1000". Leaves non-numbers untouched.
  static String _formatNumber(String v) {
    final d = double.tryParse(v);
    if (d == null) return v;
    if (d == d.truncateToDouble() && d.abs() < 1e15) return d.toInt().toString();
    return v;
  }

  /// "A1" -> 0, "B7" -> 1, "AA3" -> 26.
  static int columnIndex(String cellRef) {
    var n = 0;
    for (final ch in cellRef.toUpperCase().codeUnits) {
      if (ch < 65 || ch > 90) break;
      n = n * 26 + (ch - 64);
    }
    return n - 1;
  }
}
