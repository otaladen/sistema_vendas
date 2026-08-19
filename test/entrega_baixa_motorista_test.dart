import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_vendas/domain/entrega_baixa_motorista_visao.dart';
import 'package:sistema_vendas/domain/entrega_baixa_pendente.dart';
import 'package:sistema_vendas/domain/entrega_baixa_sync_regras.dart';
import 'package:sistema_vendas/domain/entrega_nao_entregue.dart';
import 'package:sistema_vendas/model/venda.dart';

void main() {
  EntregaBaixaPendente pendente({
    int vendaId = 10,
    String recebidoPor = 'Maria',
  }) {
    return EntregaBaixaPendente(
      vendaId: vendaId,
      recebidoPor: recebidoPor,
      usuarioLogin: 'joao',
      numeroOrcamento: 44,
      clienteNome: 'Cliente X',
      enderecoEntrega: 'Rua A',
      motoristaEntrega: 'Joao',
      statusAnterior: 'saiu_entrega',
      cargaSeparada: true,
      cargaCarregada: true,
      cargaSaiu: true,
      criadoEmIso: '2026-08-13T12:00:00.000Z',
    );
  }

  group('EntregaBaixaFila', () {
    test('upsert substitui pelo mesmo vendaId', () {
      final a = pendente(recebidoPor: 'Ana');
      final b = pendente(recebidoPor: 'Bia');
      final lista = EntregaBaixaFila.upsert(EntregaBaixaFila.upsert([], a), b);
      expect(lista, hasLength(1));
      expect(lista.single.recebidoPor, 'Bia');
    });

    test('remover tira so o id pedido', () {
      final lista = EntregaBaixaFila.remover(
        [pendente(vendaId: 1), pendente(vendaId: 2)],
        1,
      );
      expect(lista.map((e) => e.vendaId).toList(), [2]);
    });

    test('ignora item sem recebedor', () {
      final lista = EntregaBaixaFila.upsert(
        [],
        pendente(recebidoPor: '  '),
      );
      expect(lista, isEmpty);
    });
  });

  group('EntregaBaixaMotoristaVisao', () {
    test('marca entrega ativa como aguardando sync', () {
      final v = Venda(id: 10, numeroOrcamento: 44, statusEntrega: 'saiu_entrega');
      final linhas = EntregaBaixaMotoristaVisao.montar(
        entregasAtivas: [v],
        pendentes: [pendente()],
        sincronizadasRecentes: const [],
      );
      expect(linhas, hasLength(1));
      expect(linhas.single.aguardandoSync, isTrue);
      expect(linhas.single.rotuloStatusSync, 'Entregue (Aguardando Sync)');
    });

    test('recoloca pendente se a API ainda nao devolveu a venda', () {
      final linhas = EntregaBaixaMotoristaVisao.montar(
        entregasAtivas: const [],
        pendentes: [pendente()],
        sincronizadasRecentes: const [],
      );
      expect(linhas, hasLength(1));
      expect(linhas.single.venda.numeroOrcamento, 44);
      expect(linhas.single.clienteNome, 'Cliente X');
      expect(linhas.single.aguardandoSync, isTrue);
    });

    test('apos 200 OK mostra Sincronizada', () {
      final v = Venda(id: 10, numeroOrcamento: 44, statusEntrega: 'entregue');
      final linhas = EntregaBaixaMotoristaVisao.montar(
        entregasAtivas: const [],
        pendentes: const [],
        sincronizadasRecentes: [v],
      );
      expect(linhas.single.sincronizada, isTrue);
      expect(linhas.single.rotuloStatusSync, 'Sincronizada');
    });

    test('baixa recusada permanece visivel com recado', () {
      final v = Venda(id: 10, numeroOrcamento: 44, statusEntrega: 'saiu_entrega');
      final linhas = EntregaBaixaMotoristaVisao.montar(
        entregasAtivas: [v],
        pendentes: const [],
        sincronizadasRecentes: const [],
        recusadas: const [
          EntregaBaixaFalha(
            vendaId: 10,
            numeroOrcamento: 44,
            mensagem: 'A loja ja alterou esta entrega. Fale com a expedicao.',
          ),
        ],
      );
      expect(linhas.single.recusada, isTrue);
      expect(linhas.single.rotuloStatusSync, contains('expedicao'));
    });
  });

  test('roundtrip do mapa da fila', () {
    final original = pendente();
    final copia = EntregaBaixaPendente.fromMap(original.toMap());
    expect(copia.vendaId, original.vendaId);
    expect(copia.recebidoPor, original.recebidoPor);
    expect(copia.cargaSaiu, isTrue);
  });

  group('EntregaBaixaSyncRegras', () {
    test('nao remove baixa com foto local sem path no servidor', () {
      expect(
        EntregaBaixaSyncRegras.podeConfirmarRemocao(
          servidorConfirmou: true,
          ehNaoEntregue: false,
          fotoPathLocal: '/tmp/venda_1.jpg',
          fotoPathServidor: '',
          arquivoLocalExiste: true,
        ),
        isFalse,
      );
    });

    test('remove quando texto e fotoPathServidor chegaram', () {
      expect(
        EntregaBaixaSyncRegras.podeConfirmarRemocao(
          servidorConfirmou: true,
          ehNaoEntregue: false,
          fotoPathLocal: '/tmp/venda_1.jpg',
          fotoPathServidor: 'pod_entrega/venda_1_20260813_120000.jpg',
          arquivoLocalExiste: true,
        ),
        isTrue,
      );
    });

    test('insucesso remove so com confirmacao do servidor', () {
      expect(
        EntregaBaixaSyncRegras.podeConfirmarRemocao(
          servidorConfirmou: true,
          ehNaoEntregue: true,
          fotoPathLocal: '',
          fotoPathServidor: '',
          arquivoLocalExiste: false,
        ),
        isTrue,
      );
      expect(
        EntregaBaixaSyncRegras.podeConfirmarRemocao(
          servidorConfirmou: false,
          ehNaoEntregue: true,
          fotoPathLocal: '',
          fotoPathServidor: '',
          arquivoLocalExiste: false,
        ),
        isFalse,
      );
    });

    test('precisa enviar foto pela LAN antes da baixa', () {
      expect(
        EntregaBaixaSyncRegras.precisaEnviarFoto(
          ehNaoEntregue: false,
          fotoPathLocal: '/tmp/a.jpg',
          fotoPathServidor: '',
          arquivoLocalExiste: true,
        ),
        isTrue,
      );
      expect(
        EntregaBaixaSyncRegras.precisaEnviarFoto(
          ehNaoEntregue: false,
          fotoPathLocal: '/tmp/a.jpg',
          fotoPathServidor: 'pod_entrega/a.jpg',
          arquivoLocalExiste: true,
        ),
        isFalse,
      );
    });

    test('erro permanente vira recado para o motorista', () {
      expect(
        EntregaBaixaSyncRegras.mensagemErroPermanente(
          'entrega_status_terminal conflito',
        ),
        contains('expedicao'),
      );
      expect(
        EntregaBaixaSyncRegras.mensagemErroPermanente('venda nao encontrada'),
        contains('nao foi encontrada'),
      );
    });
  });

  test('roundtrip inclui retornouParaLoja', () {
    final original = EntregaBaixaPendente.deNaoEntregue(
      venda: Venda(id: 9, statusEntrega: 'saiu_entrega'),
      usuarioLogin: 'joao',
      motivoCodigo: EntregaNaoEntregueMotivo.ausente,
      clienteNome: 'X',
      retornouParaLoja: true,
    );
    final copia = EntregaBaixaPendente.fromMap(original.toMap());
    expect(copia.retornouParaLoja, isTrue);
    expect(copia.ehNaoEntregue, isTrue);
  });

  group('nao entregue', () {
    test('fila aceita item sem recebedor quando e insucesso', () {
      final item = EntregaBaixaPendente(
        vendaId: 7,
        recebidoPor: '',
        usuarioLogin: 'joao',
        tipo: EntregaMotoristaAcao.naoEntregue,
        motivoCodigo: EntregaNaoEntregueMotivo.ausente,
        criadoEmIso: '2026-08-13T12:00:00.000Z',
      );
      final lista = EntregaBaixaFila.upsert([], item);
      expect(lista, hasLength(1));
      expect(lista.single.ehNaoEntregue, isTrue);
    });

    test('chip de aguardando sync no insucesso', () {
      final v = Venda(id: 7, statusEntrega: 'saiu_entrega');
      final p = EntregaBaixaPendente(
        vendaId: 7,
        recebidoPor: '',
        usuarioLogin: 'joao',
        tipo: EntregaMotoristaAcao.naoEntregue,
        motivoCodigo: EntregaNaoEntregueMotivo.recusou,
        criadoEmIso: '2026-08-13T12:00:00.000Z',
      );
      final linhas = EntregaBaixaMotoristaVisao.montar(
        entregasAtivas: [v],
        pendentes: [p],
        sincronizadasRecentes: const [],
      );
      expect(linhas.single.naoEntregue, isTrue);
      expect(
        linhas.single.rotuloStatusSync,
        'Nao entregue (Aguardando Sync)',
      );
    });

    test('observacao do motorista ignora log de ocorrencia', () {
      const raw =
          'Deixar na portaria\nMotorista: Joao\n[13/08/2026 10:00] SAIU_ENTREGA por caixa: ok';
      expect(EntregaObservacaoMotorista.visivel(raw), 'Deixar na portaria');
    });

    test('whatsapp prefixa 55 em numero local', () {
      expect(
        EntregaContatoMotorista.uriWhatsApp('11987654321'),
        'https://wa.me/5511987654321',
      );
      expect(EntregaContatoMotorista.uriTelefone('11 98765-4321'), 'tel:11987654321');
    });
  });
}
