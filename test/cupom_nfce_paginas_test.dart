import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_vendas/data/app_config_repository.dart';
import 'package:sistema_vendas/model/config_layout_impressao.dart';
import 'package:sistema_vendas/model/item_venda.dart';
import 'package:sistema_vendas/model/produto.dart';
import 'package:sistema_vendas/model/venda.dart';
import 'package:sistema_vendas/domain/fiscal/pdf_documento_util.dart';
import 'package:sistema_vendas/services/cupom_nao_fiscal_venda_pdf.dart';

void main() {
  test('cupom NFC-e com chave e QR gera apenas uma pagina', () async {
    final layout = ConfigLayoutImpressao.padraoCupom().copyWith(
      estiloCupomNfce: true,
    );
    final config = EmpresaConfig(
      nomeLoja: 'Loja Teste',
      telefone: '(71) 99999-9999',
      endereco: 'Rua Teste, 1 - Lauro de Freitas - BA',
      modeloPdf: 'cupom',
      layoutImpressaoJson: LayoutImpressaoEmpresa(
        cupom: layout,
        orcamento: ConfigLayoutImpressao.padraoOrcamento(),
      ).toJsonString(),
    );

    final produto = Produto(
      codigoInterno: 'P1',
      nome: 'Produto teste',
      ncm: '25232910',
      quantidadeMinima: 1,
      precoCusto: 10,
      precoVenda: 53.5,
    );
    final item = ItemVenda(
      nomeProduto: 'Produto teste',
      quantidade: 1,
      precoUnitario: 53.5,
      precoCustoUnitario: 10,
    )..produto.target = produto;

    final venda = Venda()
      ..id = 116
      ..numeroOrcamento = 116
      ..formaPagamento = 'dinheiro'
      ..nfceChaveAcesso =
          '29260632662298000191650010000000049658499436'
      ..nfceNumero = '4'
      ..nfceSerie = '1'
      ..nfceEmitidaEm = DateTime(2026, 6, 6, 9, 8)
      ..itens.add(item);

    final pdf = await CupomNaoFiscalVendaPdf.gerar(
      venda: venda,
      config: config,
      totalRecebido: 53.5,
      troco: 0,
    );

    expect(
      PdfDocumentoUtil.contarPaginas(pdf.bytes),
      1,
      reason: 'Cupom NFC-e nao deve duplicar o documento em duas paginas',
    );
  });
}
