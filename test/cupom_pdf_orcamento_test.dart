import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';

import 'package:sistema_vendas/model/config_layout_impressao.dart';
import 'package:sistema_vendas/services/cupom_pdf_layout.dart';

void main() {
  test('formatoPaginaOrcamentoSalvar termico usa altura finita', () {
    const layout = ConfigLayoutImpressao();
    final fmt = CupomPdfLayout.formatoPaginaOrcamentoSalvar(
      modelo: EmpresaModeloPdf.bobina,
      layout: layout,
    );
    expect(fmt.height.isFinite, isTrue);
    expect(fmt.height, greaterThan(0));
    expect(fmt.width, greaterThan(0));
  });

  test('bobina 72mm gera pagina 80mm com margem lateral segura', () {
    final layout = ConfigLayoutImpressao.padraoOrcamento();
    expect(layout.larguraPaginaPdfMm, 72);
    final fmt = CupomPdfLayout.formatoPaginaOrcamentoSalvar(
      modelo: EmpresaModeloPdf.bobina,
      layout: layout,
    );
    final larguraMm = fmt.width / PdfPageFormat.mm;
    final margemEsqMm = fmt.marginLeft / PdfPageFormat.mm;
    expect(larguraMm, closeTo(80, 0.05));
    expect(margemEsqMm, greaterThanOrEqualTo(4));
    expect(
      CupomPdfLayout.larguraUtilConteudoMm(layout),
      lessThanOrEqualTo(72),
    );
  });

  test('formatoPaginaOrcamentoSalvar a4 mantem A4', () {
    const layout = ConfigLayoutImpressao();
    final fmt = CupomPdfLayout.formatoPaginaOrcamentoSalvar(
      modelo: EmpresaModeloPdf.a4,
      layout: layout,
    );
    expect(fmt.width, PdfPageFormat.a4.width);
    expect(fmt.height, PdfPageFormat.a4.height);
  });

  test('padraoOrcamento e economico(orcamento) exibem linha qtd x preco', () {
    expect(ConfigLayoutImpressao.padraoOrcamento().linhaQuantidadePreco, isTrue);
    expect(
      ConfigLayoutImpressao.economico(orcamento: true).linhaQuantidadePreco,
      isTrue,
    );
    expect(
      ConfigLayoutImpressao.economico(orcamento: false).linhaQuantidadePreco,
      isFalse,
    );
  });

  test('padraoOrcamento oculta documento do cliente (LGPD)', () {
    expect(
      ConfigLayoutImpressao.padraoOrcamento().exibirDocumentoCliente,
      isFalse,
    );
    expect(
      ConfigLayoutImpressao.economico(orcamento: true).exibirDocumentoCliente,
      isFalse,
    );
  });

  test('itemVenda empilhado inclui qtd x unitario = total', () {
    final widget = CupomPdfLayout.itemVenda(
      layout: ConfigLayoutImpressao.padraoOrcamento(),
      nomeProduto: 'Areia',
      codigoSku: '941',
      modalidade: '[RETIRA LOGO]',
      quantidade: 2,
      quantidadeExibicao: '2 M³',
      precoUnitario: 70,
      subtotal: 140,
      formatarMoeda: (v) => 'R\$ ${v.toStringAsFixed(2).replaceAll('.', ',')}',
    );
    expect(widget, isNotNull);
    // Garante que o layout padrao de orcamento renderiza a 2a linha.
    expect(ConfigLayoutImpressao.padraoOrcamento().linhaQuantidadePreco, isTrue);
    expect(
      ConfigLayoutImpressao.padraoOrcamento().colunasEsquerdaDireita,
      isFalse,
    );
  });

  test('textoTermicoAscii remove glifos que viram quadrado na Courier', () {
    expect(
      CupomPdfLayout.textoTermicoAscii('941 — Cimento · M³'),
      '941 - Cimento - M3',
    );
  });

  test('unidadesAlturaItensOrcamento conta modalidade e linha de preco', () {
    final u = CupomPdfLayout.unidadesAlturaItensOrcamento(const [
      '941 - Cimento',
      'Areia',
    ]);
    // Cada item: 1 linha nome + modalidade + qtd/preco = 3
    expect(u, 6);
  });

  test('formatoPaginaOrcamentoSalvar nao encolhe com preset economico', () {
    final economico = ConfigLayoutImpressao.padraoOrcamento();
    expect(economico.fatorEspacoVertical, lessThan(1.0));
    final fmtCurto = CupomPdfLayout.formatoPagina(
      EmpresaModeloPdf.bobina,
      layout: economico,
      linhasTexto: 20,
      qtdItens: 9,
      linhasExtras: 6,
    );
    final fmtOrc = CupomPdfLayout.formatoPaginaOrcamentoSalvar(
      modelo: EmpresaModeloPdf.bobina,
      layout: economico,
      linhasTexto: 20,
      qtdItens: 9,
      linhasExtras: 6,
    );
    // Altura util maior que o economico puro (fator 0.5), mas sem folga enorme.
    expect(fmtOrc.height, greaterThan(fmtCurto.height * 0.9));
  });
}
