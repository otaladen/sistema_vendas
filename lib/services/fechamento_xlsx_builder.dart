import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

/// Gera `.xlsx` (Open XML) com duas planilhas, sem dependencia do pacote `excel`.
class FechamentoXlsxBuilder {
  FechamentoXlsxBuilder._();

  static Uint8List build({
    required String sheet1Name,
    required List<List<String>> sheet1Rows,
    required String sheet2Name,
    required List<List<String>> sheet2Rows,
  }) {
    final archive = Archive();
    void add(String path, String content) {
      final bytes = utf8.encode(content);
      archive.addFile(ArchiveFile(path, bytes.length, bytes));
    }

    add('[Content_Types].xml', _contentTypes());
    add('_rels/.rels', _rootRels());
    add('xl/workbook.xml', _workbook(sheet1Name, sheet2Name));
    add('xl/_rels/workbook.xml.rels', _workbookRels());
    add('xl/worksheets/sheet1.xml', _worksheet(sheet1Rows));
    add('xl/worksheets/sheet2.xml', _worksheet(sheet2Rows));

    final zip = ZipEncoder().encode(archive);
    return Uint8List.fromList(zip);
  }

  static String _contentTypes() => '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
  <Default Extension="xml" ContentType="application/xml"/>
  <Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>
  <Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>
  <Override PartName="/xl/worksheets/sheet2.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>
</Types>''';

  static String _rootRels() => '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>
</Relationships>''';

  static String _workbook(String s1, String s2) => '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
  <sheets>
    <sheet name="${_escAttr(s1)}" sheetId="1" r:id="rId1"/>
    <sheet name="${_escAttr(s2)}" sheetId="2" r:id="rId2"/>
  </sheets>
</workbook>''';

  static String _workbookRels() => '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>
  <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet2.xml"/>
</Relationships>''';

  static String _worksheet(List<List<String>> rows) {
    final buf = StringBuffer('''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
  <sheetData>
''');
    for (var r = 0; r < rows.length; r++) {
      final rowNum = r + 1;
      buf.write('<row r="$rowNum">');
      final linha = rows[r];
      for (var c = 0; c < linha.length; c++) {
        final ref = '${_colLetter(c)}$rowNum';
        final valor = linha[c];
        final num = double.tryParse(valor.replaceAll(',', '.'));
        if (num != null && valor.trim().isNotEmpty && _pareceNumero(valor)) {
          buf.write('<c r="$ref"><v>$num</v></c>');
        } else {
          buf.write(
            '<c r="$ref" t="inlineStr"><is><t>${_escText(valor)}</t></is></c>',
          );
        }
      }
      buf.write('</row>');
    }
    buf.write('''
  </sheetData>
</worksheet>''');
    return buf.toString();
  }

  static bool _pareceNumero(String s) {
    final t = s.trim();
    if (t.isEmpty) return false;
    return RegExp(r'^-?\d+([.,]\d+)?$').hasMatch(t);
  }

  static String _colLetter(int index) {
    var dividend = index + 1;
    var name = '';
    while (dividend > 0) {
      final mod = (dividend - 1) % 26;
      name = String.fromCharCode(65 + mod) + name;
      dividend = (dividend - mod) ~/ 26;
    }
    return name;
  }

  static String _escText(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');

  static String _escAttr(String s) => _escText(s);
}
