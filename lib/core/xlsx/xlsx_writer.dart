import 'dart:convert';

import 'package:archive/archive.dart';

/// A worksheet to write: the first row is treated as a bold, frozen header.
class XlsxSheetData {
  XlsxSheetData(this.name, this.rows, {this.columnWidths = const []});
  final String name;
  final List<List<String>> rows;
  final List<double> columnWidths;
}

/// Minimal .xlsx writer (inline strings, one bold header style, wrapped text).
/// Output opens in Excel, LibreOffice and Google Sheets.
class XlsxWriter {
  static List<int> write(List<XlsxSheetData> sheets) {
    final archive = Archive();
    void add(String name, String content) {
      final bytes = utf8.encode(content);
      archive.addFile(ArchiveFile(name, bytes.length, bytes));
    }

    final sheetEntries = StringBuffer();
    final relEntries = StringBuffer();
    final overrides = StringBuffer();
    for (var i = 0; i < sheets.length; i++) {
      final n = i + 1;
      sheetEntries.write(
          '<sheet name="${_attr(_sheetName(sheets[i].name, i))}" sheetId="$n" r:id="rId$n"/>');
      relEntries.write(
          '<Relationship Id="rId$n" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet$n.xml"/>');
      overrides.write(
          '<Override PartName="/xl/worksheets/sheet$n.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>');
      add('xl/worksheets/sheet$n.xml', _sheetXml(sheets[i]));
    }
    final stylesRel = sheets.length + 1;

    add('[Content_Types].xml',
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
        '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
        '<Default Extension="xml" ContentType="application/xml"/>'
        '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>'
        '<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>'
        '$overrides'
        '</Types>');
    add('_rels/.rels',
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>'
        '</Relationships>');
    add('xl/workbook.xml',
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" '
        'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
        '<sheets>$sheetEntries</sheets></workbook>');
    add('xl/_rels/workbook.xml.rels',
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '$relEntries'
        '<Relationship Id="rId$stylesRel" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>'
        '</Relationships>');
    add('xl/styles.xml',
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
        '<fonts count="2"><font><sz val="11"/><name val="Calibri"/></font>'
        '<font><b/><sz val="11"/><name val="Calibri"/></font></fonts>'
        '<fills count="3"><fill><patternFill patternType="none"/></fill>'
        '<fill><patternFill patternType="gray125"/></fill>'
        '<fill><patternFill patternType="solid"><fgColor rgb="FFDCE6F2"/><bgColor indexed="64"/></patternFill></fill></fills>'
        '<borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders>'
        '<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>'
        '<cellXfs count="3">'
        '<xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>'
        '<xf numFmtId="0" fontId="1" fillId="2" borderId="0" xfId="0" applyFont="1" applyFill="1"/>'
        '<xf numFmtId="49" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1" applyAlignment="1"><alignment wrapText="1" vertical="top"/></xf>'
        '</cellXfs>'
        '<cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles>'
        '</styleSheet>');

    final out = ZipEncoder().encode(archive);
    if (out == null) throw StateError('Could not create the Excel file.');
    return out;
  }

  static String _sheetXml(XlsxSheetData s) {
    final b = StringBuffer()
      ..write('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>')
      ..write('<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">')
      ..write('<sheetViews><sheetView workbookViewId="0">'
          '<pane ySplit="1" topLeftCell="A2" activePane="bottomLeft" state="frozen"/>'
          '</sheetView></sheetViews>');
    if (s.columnWidths.isNotEmpty) {
      b.write('<cols>');
      for (var i = 0; i < s.columnWidths.length; i++) {
        b.write('<col min="${i + 1}" max="${i + 1}" width="${s.columnWidths[i]}" customWidth="1"/>');
      }
      b.write('</cols>');
    }
    b.write('<sheetData>');
    for (var r = 0; r < s.rows.length; r++) {
      final rowNo = r + 1;
      b.write('<row r="$rowNo">');
      final row = s.rows[r];
      for (var c = 0; c < row.length; c++) {
        final v = row[c];
        if (v.isEmpty) continue;
        final style = r == 0 ? 1 : 2;
        b.write('<c r="${columnName(c)}$rowNo" t="inlineStr" s="$style"><is><t xml:space="preserve">${_text(v)}</t></is></c>');
      }
      b.write('</row>');
    }
    b.write('</sheetData></worksheet>');
    return b.toString();
  }

  static String columnName(int index) {
    var n = index + 1;
    var s = '';
    while (n > 0) {
      final m = (n - 1) % 26;
      s = String.fromCharCode(65 + m) + s;
      n = (n - 1) ~/ 26;
    }
    return s;
  }

  static String _sheetName(String name, int i) {
    var n = name.replaceAll(RegExp(r'[\\/?*\[\]:]'), ' ').trim();
    if (n.isEmpty) n = 'Sheet${i + 1}';
    return n.length > 31 ? n.substring(0, 31) : n;
  }

  // Removes characters that are illegal in XML 1.0 and escapes markup.
  static String _text(String v) => v
      .replaceAll(RegExp('[\u0000-\u0008\u000B\u000C\u000E-\u001F]'), '')
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');

  static String _attr(String v) => _text(v).replaceAll('"', '&quot;');
}
