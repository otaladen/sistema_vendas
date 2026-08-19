import '../model/venda.dart';
import 'entrega_baixa_pendente.dart';

enum EntregaBaixaUiStatus { ativa, aguardandoSync, sincronizada, recusada }

class EntregaBaixaFalha {
  const EntregaBaixaFalha({
    required this.vendaId,
    required this.numeroOrcamento,
    required this.mensagem,
  });

  final int vendaId;
  final int numeroOrcamento;
  final String mensagem;
}

class EntregaBaixaLinhaVisao {
  const EntregaBaixaLinhaVisao({
    required this.venda,
    required this.sync,
    this.clienteNome = '',
    this.naoEntregue = false,
    this.mensagemFalha = '',
  });

  final Venda venda;
  final EntregaBaixaUiStatus sync;
  final String clienteNome;
  final bool naoEntregue;
  final String mensagemFalha;

  bool get aguardandoSync => sync == EntregaBaixaUiStatus.aguardandoSync;
  bool get sincronizada => sync == EntregaBaixaUiStatus.sincronizada;
  bool get recusada => sync == EntregaBaixaUiStatus.recusada;

  String get rotuloStatusSync {
    switch (sync) {
      case EntregaBaixaUiStatus.aguardandoSync:
        return naoEntregue
            ? 'Nao entregue (Aguardando Sync)'
            : 'Entregue (Aguardando Sync)';
      case EntregaBaixaUiStatus.sincronizada:
        return naoEntregue ? 'Nao entregue · sincronizada' : 'Sincronizada';
      case EntregaBaixaUiStatus.recusada:
        return mensagemFalha.isEmpty
            ? 'Baixa recusada pela loja'
            : mensagemFalha;
      case EntregaBaixaUiStatus.ativa:
        return '';
    }
  }
}

/// Junta entregas ativas da API com a fila local do aparelho.
abstract final class EntregaBaixaMotoristaVisao {
  static List<EntregaBaixaLinhaVisao> montar({
    required List<Venda> entregasAtivas,
    required List<EntregaBaixaPendente> pendentes,
    required List<Venda> sincronizadasRecentes,
    List<EntregaBaixaFalha> recusadas = const [],
    Map<int, String> clientePorVendaId = const {},
  }) {
    final pendentePorId = <int, EntregaBaixaPendente>{
      for (final p in pendentes.where((e) => e.vendaId > 0)) p.vendaId: p,
    };
    final syncPorId = <int, Venda>{
      for (final v in sincronizadasRecentes.where((e) => e.id > 0)) v.id: v,
    };
    final falhaPorId = <int, EntregaBaixaFalha>{
      for (final f in recusadas.where((e) => e.vendaId > 0)) f.vendaId: f,
    };
    final seen = <int>{};
    final out = <EntregaBaixaLinhaVisao>[];

    for (final v in entregasAtivas) {
      if (v.id <= 0) continue;
      final p = pendentePorId[v.id];
      if (p != null) {
        out.add(
          EntregaBaixaLinhaVisao(
            venda: v,
            sync: EntregaBaixaUiStatus.aguardandoSync,
            clienteNome: p.clienteNome,
            naoEntregue: p.ehNaoEntregue,
          ),
        );
      } else if (syncPorId.containsKey(v.id)) {
        out.add(
          EntregaBaixaLinhaVisao(
            venda: v,
            sync: EntregaBaixaUiStatus.sincronizada,
            clienteNome: clientePorVendaId[v.id] ?? '',
            naoEntregue: v.statusEntrega == 'reagendada',
          ),
        );
      } else if (falhaPorId.containsKey(v.id)) {
        final f = falhaPorId[v.id]!;
        out.add(
          EntregaBaixaLinhaVisao(
            venda: v,
            sync: EntregaBaixaUiStatus.recusada,
            clienteNome: clientePorVendaId[v.id] ?? '',
            mensagemFalha: f.mensagem,
          ),
        );
      } else {
        out.add(
          EntregaBaixaLinhaVisao(
            venda: v,
            sync: EntregaBaixaUiStatus.ativa,
            clienteNome: clientePorVendaId[v.id] ?? '',
          ),
        );
      }
      seen.add(v.id);
    }

    for (final p in pendentes) {
      if (p.vendaId <= 0 || seen.contains(p.vendaId)) continue;
      out.add(
        EntregaBaixaLinhaVisao(
          venda: p.paraVendaStub(),
          sync: EntregaBaixaUiStatus.aguardandoSync,
          clienteNome: p.clienteNome,
          naoEntregue: p.ehNaoEntregue,
        ),
      );
      seen.add(p.vendaId);
    }

    for (final v in sincronizadasRecentes) {
      if (v.id <= 0 || seen.contains(v.id)) continue;
      out.add(
        EntregaBaixaLinhaVisao(
          venda: v,
          sync: EntregaBaixaUiStatus.sincronizada,
          clienteNome: clientePorVendaId[v.id] ?? '',
          naoEntregue: v.statusEntrega == 'reagendada',
        ),
      );
      seen.add(v.id);
    }

    for (final f in recusadas) {
      if (f.vendaId <= 0 || seen.contains(f.vendaId)) continue;
      out.add(
        EntregaBaixaLinhaVisao(
          venda: Venda(
            id: f.vendaId,
            numeroOrcamento: f.numeroOrcamento,
            statusEntrega: 'saiu_entrega',
          ),
          sync: EntregaBaixaUiStatus.recusada,
          mensagemFalha: f.mensagem,
        ),
      );
    }
    return out;
  }
}

