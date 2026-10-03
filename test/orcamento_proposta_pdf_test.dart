import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';

import 'package:sistema_vendas/data/app_config_repository.dart';
import 'package:sistema_vendas/domain/pagamento_orcamento.dart';
import 'package:sistema_vendas/model/cliente.dart';
import 'package:sistema_vendas/model/item_venda.dart';
import 'package:sistema_vendas/model/venda.dart';
import 'package:sistema_vendas/model/vendedor.dart';
import 'package:sistema_vendas/services/orcamento_proposta_pdf.dart';

void main() {
  test('proposta do cliente sai em A4 e cabe varios itens', () async {
    final itens = List<ItemVenda>.generate(
      28,
      (i) => ItemVenda(
        nomeProduto: 'Calha Tigre ${i + 1} — condutor',
        quantidade: i + 1,
        precoUnitario: 12.5,
        precoCustoUnitario: 4,
        escalaQuantidade: ItemVenda.escalaQuantidadeLiteral,
      ),
    );
    final subtotal = itens.fold<double>(0, (s, i) => s + i.subtotal);
    final venda = Venda(
      id: 9,
      numeroOrcamento: 2422,
      total: subtotal + 80,
      valorFrete: 80,
      formaPagamento: PagamentoMeio.cartaoCredito,
      quantidadeParcelas: 5,
    );

    final pdf = await OrcamentoPropostaPdf.gerar(
      venda: venda,
      itens: itens,
      empresa: const EmpresaConfig(
        nomeLoja: 'Ruy Morales Materiais',
        endereco: 'Rua das Telhas, 120 — Centro',
        telefone: '75999998888',
        rodapeOrcamento: 'Valores sujeitos à confirmação de estoque.',
      ),
      validadeDias: 7,
      cliente: Cliente(
        nomeRazao: 'Construtora São Francisco',
        telefone: '75988887777',
      ),
      vendedor: Vendedor(
        codigoInterno: '03',
        nomeCompleto: 'Otávio Carvalho',
        apelido: 'Otávio',
      ),
      produtosPorItem: {for (var i = 0; i < itens.length; i++) i: null},
      cnpjEmitente: '32662298000191',
    );

    expect(pdf.pageFormat, PdfPageFormat.a4);
    expect(String.fromCharCodes(pdf.bytes.take(5)), '%PDF-');
    expect(pdf.bytes.length, greaterThan(2000));
  });
}
