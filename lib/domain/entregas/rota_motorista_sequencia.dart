import '../../model/venda.dart';
import '../entrega_baixa_motorista_visao.dart';

/// Numeracao das paradas na rota do motorista.
///
/// Parada = entrega que ele ainda precisa visitar. O que ja foi baixado no
/// aparelho sai da contagem mesmo esperando sync: ele nao volta la. Baixa
/// recusada pela loja continua contando, porque o material ainda esta no carro.
class ParadaRotaMotorista {
  const ParadaRotaMotorista({
    required this.linha,
    required this.posicao,
    required this.total,
    required this.proxima,
  });

  final EntregaBaixaLinhaVisao linha;

  /// 1..[total] enquanto falta visitar; 0 quando ja foi baixada.
  final int posicao;

  /// Quantas paradas ainda faltam na rota inteira.
  final int total;

  final bool proxima;

  bool get pendente => posicao > 0;

  /// Com uma parada so, numerar e apontar a proxima e ruido.
  bool get mostrarSequencia => pendente && total > 1;

  bool get destacarProxima => proxima && total > 1;

  String get rotulo => mostrarSequencia ? 'Parada $posicao de $total' : '';
}

abstract final class RotaMotorista {
  RotaMotorista._();

  static bool paradaPendente(EntregaBaixaLinhaVisao linha) =>
      linha.sync == EntregaBaixaUiStatus.ativa ||
      linha.sync == EntregaBaixaUiStatus.recusada;

  /// Mantem a ordem recebida (que ja vem por `Venda.ordemEntrega`) e so
  /// numera por cima dela.
  static List<ParadaRotaMotorista> montar(
    List<EntregaBaixaLinhaVisao> linhas,
  ) {
    final total = linhas.where(paradaPendente).length;
    final out = <ParadaRotaMotorista>[];
    var posicao = 0;
    for (final linha in linhas) {
      if (paradaPendente(linha)) {
        posicao++;
        out.add(
          ParadaRotaMotorista(
            linha: linha,
            posicao: posicao,
            total: total,
            proxima: posicao == 1,
          ),
        );
      } else {
        out.add(
          ParadaRotaMotorista(
            linha: linha,
            posicao: 0,
            total: total,
            proxima: false,
          ),
        );
      }
    }
    return out;
  }

  static int totalPendentes(List<ParadaRotaMotorista> paradas) =>
      paradas.where((p) => p.pendente).length;

  /// Paradas que faltam, na ordem, para montar a rota no mapa.
  static List<Venda> vendasParaMapa(List<ParadaRotaMotorista> paradas) => [
        for (final p in paradas)
          if (p.pendente && p.linha.venda.enderecoEntrega.trim().isNotEmpty)
            p.linha.venda,
      ];
}
