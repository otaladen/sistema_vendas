import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_vendas/data/app_config_repository.dart';
import 'package:sistema_vendas/domain/observacao_nota.dart';
import 'package:sistema_vendas/model/item_venda.dart';
import 'package:sistema_vendas/model/produto.dart';
import 'package:sistema_vendas/model/venda.dart';
import 'package:sistema_vendas/services/esc_pos_commands.dart';
import 'package:sistema_vendas/services/esc_pos_cupom_builder.dart';

String _ascii(List<int> bytes) =>
    String.fromCharCodes(bytes.where((b) => b >= 32 && b < 127));

/// Titulo do cupom usa CP850 (`EscPosCommands.text`); acentos viram bytes >127
/// e somem no [_ascii]. No cupom aparece como `OBSERVAO DA VENDA:`.
String get _marcadorTituloObsCupomAscii => 'DA VENDA:';

int _primeiroIndice(String texto, List<String> marcadores) {
  var menor = -1;
  for (final m in marcadores) {
    final i = texto.indexOf(m);
    if (i < 0) continue;
    if (menor < 0 || i < menor) menor = i;
  }
  return menor;
}

CupomBalcaoDados _dadosCupom({
  required Venda venda,
  double totalRecebido = 5.8,
}) {
  final produto = Produto(
    id: 92,
    codigoInterno: '92',
    nome: 'Cimento Branco 1kg',
    precoCusto: 4,
    precoVenda: 5.8,
    preco1: 5.8,
    quantidadeMinima: 0,
    unidade: 'UN',
  );
  final item = ItemVenda(
    nomeProduto: 'Cimento Branco 1kg',
    quantidade: 1,
    precoUnitario: 5.8,
    precoCustoUnitario: 4,
  )..produto.target = produto;
  return CupomBalcaoDados(
    venda: venda,
    config: const EmpresaConfig(
      nomeLoja: 'Loja Teste',
      telefone: '0000-0000',
      endereco: 'Rua Teste',
    ),
    itens: [item],
    totalRecebido: totalRecebido,
  );
}

void main() {
  group('Cupom DANFE NFC-e — posicao da observacao da venda', () {
    test('ESC/POS: observacao entre pagamento e bloco fiscal/QR', () {
      const obs = 'vai querer por no saco';
      final venda = Venda(
        id: 2238,
        numeroControle: 2238,
        status: 'finalizada',
        total: 5.8,
        formaPagamento: 'dinheiro',
        observacaoNota: obs,
      );

      final ascii = _ascii(
        EscPosCupomBuilder.montar(
          _dadosCupom(venda: venda),
          largura: EscPosLarguraBobina.mm80,
          abrirGaveta: false,
        ),
      );

      final idxPagamento = ascii.indexOf('FORMA DE PAGAMENTO');
      expect(idxPagamento, greaterThan(-1));

      // Ignora bytes do QR (podem conter substrings fiscais por acaso).
      final aposPagamento = ascii.substring(idxPagamento);

      final idxTituloObs = aposPagamento.indexOf(_marcadorTituloObsCupomAscii);
      expect(idxTituloObs, greaterThan(0));

      expect(aposPagamento.indexOf(obs), greaterThan(idxTituloObs));

      final idxFiscal = _primeiroIndice(
        aposPagamento,
        const [
          'CONTIGENCIA',
          'CHAVE DE ACESSO',
          'Consulte pela Chave',
          'Emissao:',
        ],
      );
      expect(idxFiscal, greaterThan(-1));
      expect(idxFiscal, greaterThan(idxTituloObs));

      final idxQr = aposPagamento.indexOf('Consulta via leitor de QR Code');
      if (idxQr >= 0) {
        expect(idxQr, greaterThan(idxTituloObs));
      }

      expect(ascii, isNot(contains('Obs.:')));
    });

    test('ESC/POS: cupom sem observacao nao imprime bloco nem Obs. no rodape', () {
      final venda = Venda(
        id: 1,
        numeroControle: 1,
        status: 'finalizada',
        total: 5.8,
        formaPagamento: 'dinheiro',
      );
      final ascii = _ascii(
        EscPosCupomBuilder.montar(
          _dadosCupom(venda: venda),
          largura: EscPosLarguraBobina.mm80,
          abrirGaveta: false,
        ),
      );
      expect(ascii, isNot(contains(_marcadorTituloObsCupomAscii)));
      expect(ascii, isNot(contains('Obs.:')));
    });

    test('titulo do bloco cupom DANFE e texto natural', () {
      expect(
        ObservacaoNota.tituloCupomDanfe,
        'OBSERVAÇÃO DA VENDA:',
      );
      final v = Venda(observacaoNota: 'Cor RAL 9003');
      expect(ObservacaoNota.linhasRodapeCupom(v), ['Cor RAL 9003']);
    });
  });
}
