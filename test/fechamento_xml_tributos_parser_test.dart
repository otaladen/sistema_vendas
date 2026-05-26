import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_vendas/services/fechamento_xml_tributos_parser.dart';

void main() {
  test('extrai CFOP e totais ICMSTot do XML', () {
    const xml = '''
    <nfeProc><NFe><infNFe>
      <det><prod><CFOP>5102</CFOP></prod></det>
      <total><ICMSTot>
        <vBC>100.00</vBC><vICMS>18.00</vICMS>
        <vPIS>1.65</vPIS><vCOFINS>7.60</vCOFINS>
      </ICMSTot></total>
    </infNFe></NFe></nfeProc>
    ''';
    final t = FechamentoXmlTributosParser.parse(xml);
    expect(t.cfopPredominante, '5102');
    expect(t.baseIcms, 100);
    expect(t.valorIcms, 18);
    expect(t.valorPis, closeTo(1.65, 0.01));
    expect(t.valorCofins, closeTo(7.6, 0.01));
  });
}
