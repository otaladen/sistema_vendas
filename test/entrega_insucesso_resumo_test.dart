import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_vendas/domain/entrega_nao_entregue.dart';

void main() {
  group('EntregaInsucessoResumo.deVenda', () {
    test('ignora venda que nao esta reagendada', () {
      final r = EntregaInsucessoResumo.deVenda(
        statusEntrega: 'saiu_entrega',
        observacaoEntrega:
            '[13/08/2026 10:00] ENTREGA_EVENTO_NAO_ENTREGUE por joao: Cliente ausente. Carga retornou para a loja.',
      );
      expect(r, isNull);
    });

    test('le motivo do motorista e carga que voltou', () {
      final r = EntregaInsucessoResumo.deVenda(
        statusEntrega: 'reagendada',
        observacaoEntrega:
            '[13/08/2026 10:00] ENTREGA_EVENTO_NAO_ENTREGUE por joao: Cliente ausente. Carga retornou para a loja.',
      );
      expect(r, isNotNull);
      expect(r!.motivo, 'Cliente ausente');
      expect(r.retornouParaLoja, isTrue);
      expect(r.linhaPatio, 'Cliente ausente · voltou a loja');
    });

    test('le endereco errado com carga no caminhao', () {
      final r = EntregaInsucessoResumo.deVenda(
        statusEntrega: 'reagendada',
        observacaoEntrega:
            '[13/08/2026 11:00] ENTREGA_EVENTO_NAO_ENTREGUE por joao: Endereco errado. Carga permanece no caminhao.',
      );
      expect(r!.motivo, 'Endereco errado');
      expect(r.retornouParaLoja, isFalse);
      expect(r.linhaPatio, 'Endereco errado · no caminhao');
    });

    test('le recusa em linha REAGENDADA do patio', () {
      final r = EntregaInsucessoResumo.deVenda(
        statusEntrega: 'reagendada',
        observacaoEntrega:
            '[13/08/2026 12:00] REAGENDADA por maria: Cliente recusou. Carga retornou para a loja.',
      );
      expect(r!.motivo, 'Cliente recusou');
      expect(r.retornouParaLoja, isTrue);
    });

    test('usa o ultimo evento quando ha varias linhas', () {
      final r = EntregaInsucessoResumo.deVenda(
        statusEntrega: 'reagendada',
        observacaoEntrega: [
          '[12/08/2026 09:00] ENTREGA_EVENTO_NAO_ENTREGUE por joao: Cliente ausente. Carga permanece no caminhao.',
          '[13/08/2026 14:00] ENTREGA_EVENTO_NAO_ENTREGUE por joao: Cliente recusou. Carga retornou para a loja.',
        ].join('\n'),
      );
      expect(r!.motivo, 'Cliente recusou');
      expect(r.retornouParaLoja, isTrue);
    });

    test('reagendada sem linha de motivo mostra Insucesso', () {
      final r = EntregaInsucessoResumo.deVenda(
        statusEntrega: 'reagendada',
        observacaoEntrega: 'Deixar na portaria',
      );
      expect(r!.motivo, 'Insucesso');
      expect(r.retornouParaLoja, isNull);
      expect(r.linhaPatio, 'Insucesso');
    });
  });
}
