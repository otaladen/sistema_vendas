import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_vendas/data/nfe_saida_fiscal_store.dart';
import 'package:sistema_vendas/domain/fiscal/nfe_painel_resumo.dart';
import 'package:sistema_vendas/domain/fiscal/nfe_pendencias_service.dart';
import 'package:sistema_vendas/model/cliente.dart';
import 'package:sistema_vendas/model/venda.dart';

void main() {
  test('NfePainelResumoBuilder conta status', () {
    final historico = [
      NfeSaidaFiscalRegistro(
        id: '1',
        vendaId: 1,
        numeroOrcamento: 10,
        clienteNome: 'A',
        referenciaFocus: 'r1',
        statusFocus: 'autorizado',
        emitidaEm: DateTime.now(),
        statusSefaz: '100',
      ),
      NfeSaidaFiscalRegistro(
        id: '2',
        vendaId: 2,
        numeroOrcamento: 11,
        clienteNome: 'B',
        referenciaFocus: 'r2',
        statusFocus: 'processando_autorizacao',
        emitidaEm: DateTime.now(),
      ),
      NfeSaidaFiscalRegistro(
        id: '3',
        vendaId: 3,
        numeroOrcamento: 12,
        clienteNome: 'C',
        referenciaFocus: 'r3',
        statusFocus: 'erro_autorizacao',
        emitidaEm: DateTime.now(),
      ),
    ];
    final r = NfePainelResumoBuilder.calcular(
      historico: historico,
      vendasSemNfe: 5,
    );
    expect(r.autorizadas, 1);
    expect(r.processando, 1);
    expect(r.rejeitadas, 1);
    expect(r.vendasSemNfeAutorizada, 5);
  });

  test('NfePainelResumo ignora rejeicao superada por NF-e autorizada', () {
    final historico = [
      NfeSaidaFiscalRegistro(
        id: 'rej',
        vendaId: 124,
        numeroOrcamento: 117,
        clienteNome: 'Otavio',
        referenciaFocus: 'venda_124_nfe',
        statusFocus: 'erro_autorizacao',
        emitidaEm: DateTime.now().subtract(const Duration(hours: 1)),
      ),
      NfeSaidaFiscalRegistro(
        id: 'ok',
        vendaId: 124,
        numeroOrcamento: 117,
        clienteNome: 'Otavio',
        referenciaFocus: 'venda_124_nfe',
        statusFocus: 'autorizado',
        emitidaEm: DateTime.now(),
        statusSefaz: '100',
      ),
    ];
    final r = NfePainelResumoBuilder.calcular(
      historico: historico,
      vendasSemNfe: 0,
      vendasComNfeAutorizada: {124},
    );
    expect(r.autorizadas, 1);
    expect(r.rejeitadas, 0);
  });

  test('idsVendasComNfeAutorizada ignora rejeitadas', () {
    final store = NfeSaidaFiscalStore('');
    // Store sem arquivo: listar vazio — testar logica estatica via lista manual
    final regs = [
      NfeSaidaFiscalRegistro(
        id: '1',
        vendaId: 99,
        numeroOrcamento: 1,
        clienteNome: 'X',
        referenciaFocus: 'r',
        statusFocus: 'autorizado',
        emitidaEm: DateTime.now(),
        statusSefaz: '100',
      ),
      NfeSaidaFiscalRegistro(
        id: '2',
        vendaId: 100,
        numeroOrcamento: 2,
        clienteNome: 'Y',
        referenciaFocus: 'r2',
        statusFocus: 'erro_autorizacao',
        emitidaEm: DateTime.now(),
      ),
    ];
    final ids = <int>{};
    for (final r in regs) {
      if (r.vendaId > 0 && r.autorizada) ids.add(r.vendaId);
    }
    expect(ids, {99});
    expect(NfePendenciasService.listarProcessando(store), isEmpty);
  });

  test('rejeitada some da fila quando a venda ja tem NF-e autorizada', () {
    final regs = [
      NfeSaidaFiscalRegistro(
        id: 'rej',
        vendaId: 124,
        numeroOrcamento: 117,
        clienteNome: 'Otavio',
        referenciaFocus: 'venda_124_nfe',
        statusFocus: 'erro_autorizacao',
        emitidaEm: DateTime.now().subtract(const Duration(hours: 2)),
        mensagemSefaz: 'Rejeicao 487',
      ),
      NfeSaidaFiscalRegistro(
        id: 'ok',
        vendaId: 124,
        numeroOrcamento: 117,
        clienteNome: 'Otavio',
        referenciaFocus: 'venda_124_nfe',
        statusFocus: 'autorizado',
        emitidaEm: DateTime.now(),
        statusSefaz: '100',
        numero: '1',
      ),
    ];
    final comAuth = <int>{};
    for (final r in regs) {
      if (r.vendaId > 0 && r.autorizada) comAuth.add(r.vendaId);
    }
    final rejeitadas = regs.where(
      (r) =>
          r.rejeitada &&
          !NfePendenciasService.registroSuperadoPorNfeAutorizada(
            r,
            vendasComNfeAutorizada: comAuth,
          ),
    );
    expect(rejeitadas, isEmpty);
  });

  test('fila NF-e 55 ignora venda com NFC-e autorizada', () {
    final comNfce = Venda()
      ..nfceChaveAcesso = '29260632662298000191650010000000051626070139';
    final semDocumento = Venda();
    final processandoNfce = Venda()
      ..nfceStatusFocus = 'processando_autorizacao'
      ..nfceProtocolo = 'focus_pendente:abc';

    expect(NfePendenciasService.ocultaPorNfce(comNfce), isTrue);
    expect(NfePendenciasService.ocultaPorNfce(semDocumento), isFalse);
    expect(NfePendenciasService.ocultaPorNfce(processandoNfce), isTrue);
  });

  test('fila NF-e 55 so entra cliente CNPJ sem documento de saida', () {
    final pf = Cliente(id: 1, nomeRazao: 'Miguel', documento: '12345678901');
    final pj = Cliente(
      id: 2,
      nomeRazao: 'Construtora',
      tipoPessoa: 'juridica',
      documento: '00756455000131',
    );
    final vendaPfCupom = Venda(id: 10, formaPagamento: 'dinheiro')
      ..cupomNaoFiscalEmitidoEm = DateTime.now();
    final vendaPjPix = Venda(id: 11, formaPagamento: 'pix');
    final vendaPjDinheiro = Venda(id: 14, formaPagamento: 'dinheiro');
    final vendaPjComNfce = Venda(id: 12, formaPagamento: 'pix')
      ..nfceChaveAcesso = '29260632662298000191650010000000051626070139';

    expect(
      NfePendenciasService.entraNaFilaVendasSemNfe55(vendaPfCupom, cliente: pf),
      isFalse,
    );
    expect(
      NfePendenciasService.entraNaFilaVendasSemNfe55(vendaPjPix, cliente: pj),
      isTrue,
    );
    expect(
      NfePendenciasService.entraNaFilaVendasSemNfe55(
        vendaPjDinheiro,
        cliente: pj,
      ),
      isFalse,
    );
    expect(
      NfePendenciasService.entraNaFilaVendasSemNfe55(
        vendaPjComNfce,
        cliente: pj,
      ),
      isFalse,
    );
    final pjNomeCnpj = Cliente(
      id: 3,
      nomeRazao: '00756455000131',
      tipoPessoa: 'fisica',
      documento: '',
    );
    expect(
      NfePendenciasService.entraNaFilaVendasSemNfe55(
        Venda(id: 13, formaPagamento: 'dinheiro'),
        cliente: pjNomeCnpj,
      ),
      isFalse,
    );
  });
}
