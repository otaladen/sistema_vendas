import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_vendas/data/nfe_inutilizacao_store.dart';
import 'package:sistema_vendas/data/nfe_saida_fiscal_store.dart';
import 'package:sistema_vendas/domain/fiscal/nfe_carta_correcao_registro.dart';
import 'package:sistema_vendas/domain/fiscal/nfe_numeracao_fiscal_helper.dart';
import 'package:sistema_vendas/domain/fiscal/nfe_registro_focus_merge.dart';
import 'package:sistema_vendas/services/focus_nfe_service.dart';

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('fiscal_v2_test_');
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('NfeNumeracaoFiscalHelper', () {
    test('detecta conflito com NF-e autorizada na faixa', () {
      final store = NfeSaidaFiscalStore(tempDir.path);
      store.gravar(
        NfeSaidaFiscalRegistro(
          id: '1',
          vendaId: 10,
          numeroOrcamento: 1,
          clienteNome: 'Cliente',
          referenciaFocus: 'venda_10',
          statusFocus: 'autorizado',
          emitidaEm: DateTime(2026, 5, 1),
          statusSefaz: '100',
          numero: '150',
          serie: '1',
        ),
      );

      final erro = NfeNumeracaoFiscalHelper.validarInutilizacao(
        store: store,
        serie: '1',
        numeroInicial: 140,
        numeroFinal: 160,
      );
      expect(erro, contains('Conflito'));
    });

    test('detecta sobreposicao com inutilizacao anterior', () {
      final nfeStore = NfeSaidaFiscalStore(tempDir.path);
      final inutStore = NfeInutilizacaoStore(tempDir.path);
      inutStore.gravar(
        NfeInutilizacaoRegistro(
          id: 'a',
          serie: '1',
          numeroInicial: 100,
          numeroFinal: 110,
          justificativa: 'Quebra sequencial operacional',
          usuarioLogin: 'admin',
          sucesso: true,
          protocolo: '123',
        ),
      );

      final erro = NfeNumeracaoFiscalHelper.validarInutilizacao(
        store: nfeStore,
        serie: '1',
        numeroInicial: 105,
        numeroFinal: 115,
        inutilizacaoStore: inutStore,
      );
      expect(erro, contains('sobrepoe inutilizacao'));
    });
  });

  group('NfeSaidaFiscalRegistro CC-e', () {
    test('comNovaCartaCorrecao atualiza sequencia existente', () {
      final reg = NfeSaidaFiscalRegistro(
        id: '1',
        vendaId: 1,
        numeroOrcamento: 1,
        clienteNome: 'Loja',
        referenciaFocus: 'ref',
        statusFocus: 'autorizado',
        emitidaEm: DateTime(2026, 1, 1),
        cartasCorrecao: [
          NfeCartaCorrecaoRegistro(
            numeroSequencia: 1,
            textoCorrecao: 'Texto original',
            statusFocus: 'processando_autorizacao',
          ),
        ],
      );

      final atualizado = reg.comNovaCartaCorrecao(
        NfeCartaCorrecaoRegistro(
          numeroSequencia: 1,
          textoCorrecao: 'Texto original',
          urlXml: 'http://xml/cce1',
          statusFocus: 'autorizado',
          protocolo: '999',
        ),
      );

      expect(atualizado.totalCartasCorrecao, 1);
      expect(atualizado.cartasCorrecao.single.urlXml, 'http://xml/cce1');
      expect(atualizado.cartasCorrecao.single.processando, isFalse);
    });

    test('fromJson migra campos legados de CC-e', () {
      final reg = NfeSaidaFiscalRegistro.fromJson({
        'id': '1',
        'vendaId': 2,
        'numeroOrcamento': 3,
        'clienteNome': 'Cliente',
        'referenciaFocus': 'ref',
        'statusFocus': 'autorizado',
        'emitidaEm': '2026-01-01T00:00:00.000Z',
        'numeroCartaCorrecao': 2,
        'urlPdfCartaCorrecao': 'http://pdf/cce',
        'urlXmlCartaCorrecao': 'http://xml/cce',
      });

      expect(reg.totalCartasCorrecao, 1);
      expect(reg.cartasCorrecao.single.numeroSequencia, 2);
      expect(reg.urlPdfCartaCorrecao, 'http://pdf/cce');
      expect(reg.numeroCartaCorrecao, 2);
    });
  });

  group('mesclarRegistroComResultadoFocus', () {
    test('preserva CC-e e logistica local', () {
      final base = NfeSaidaFiscalRegistro(
        id: '1',
        vendaId: 5,
        numeroOrcamento: 99,
        clienteNome: 'Loja',
        referenciaFocus: 'venda_5_nfe',
        statusFocus: 'autorizado',
        emitidaEm: DateTime(2026, 1, 1),
        statusSefaz: '100',
        volumes: 3,
        pesoBrutoKg: 12.5,
        cartasCorrecao: [
          NfeCartaCorrecaoRegistro(
            numeroSequencia: 1,
            textoCorrecao: 'Correcao teste',
            urlPdf: 'http://cce/pdf',
          ),
        ],
      );
      final resultado = FocusNfeEmissaoResultado(
        autorizada: false,
        rejeitada: false,
        processando: false,
        statusFocus: 'cancelado',
        statusSefaz: '135',
        urlXmlCancelamento: 'http://xml/cancel',
        mensagem: 'Cancelamento homologado',
        referencia: 'venda_5_nfe',
      );

      final m = mesclarRegistroComResultadoFocus(base, resultado);
      expect(m.cancelada, isTrue);
      expect(m.volumes, 3);
      expect(m.pesoBrutoKg, 12.5);
      expect(m.urlPdfCartaCorrecao, 'http://cce/pdf');
      expect(m.numeroCartaCorrecao, 1);
      expect(m.urlXmlEventoCancelamento, 'http://xml/cancel');
    });

    test('mescla CC-e do payload bruto da Focus', () {
      final base = NfeSaidaFiscalRegistro(
        id: '1',
        vendaId: 1,
        numeroOrcamento: 1,
        clienteNome: 'Loja',
        referenciaFocus: 'ref',
        statusFocus: 'autorizado',
        emitidaEm: DateTime(2026, 1, 1),
        cartasCorrecao: [
          NfeCartaCorrecaoRegistro(
            numeroSequencia: 1,
            textoCorrecao: 'Correcao local',
            statusFocus: 'processando_autorizacao',
          ),
        ],
      );
      final resultado = FocusNfeEmissaoResultado(
        autorizada: true,
        rejeitada: false,
        processando: false,
        statusFocus: 'autorizado',
        statusSefaz: '100',
        referencia: 'ref',
        payloadBruto: {
          'numero_carta_correcao': 1,
          'caminho_xml_carta_correcao': 'http://xml/cce1',
          'status': 'autorizado',
          'protocolo': '12345',
        },
      );

      final m = mesclarRegistroComResultadoFocus(base, resultado);
      expect(m.cartasCorrecao.single.urlXml, 'http://xml/cce1');
      expect(m.cartasCorrecao.single.processando, isFalse);
      expect(m.cartasCorrecao.single.textoCorrecao, 'Correcao local');
    });
  });
}
