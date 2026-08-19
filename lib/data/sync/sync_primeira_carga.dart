import 'dart:math' as math;

import '../objectbox.dart';
import 'sync_cursor_storage.dart';

/// Progresso da carga inicial (bootstrap) para a UI.
class SyncPrimeiraCargaProgresso {
  const SyncPrimeiraCargaProgresso({
    this.pagina = 0,
    this.registrosPagina = 0,
    this.registrosAcumulados = 0,
    this.revisionLocal = 0,
    this.revisionRemota,
    this.produtosLocais = 0,
    this.percentual = 0,
    this.mensagem = 'Preparando sincronizacao...',
    this.concluido = false,
    this.erro,
  });

  final int pagina;
  final int registrosPagina;
  final int registrosAcumulados;
  final int revisionLocal;
  final int? revisionRemota;
  final int produtosLocais;

  /// 0..100 sempre definido para a barra/% (nunca indeterminado na carga).
  final double percentual;
  final String mensagem;
  final bool concluido;
  final String? erro;

  /// 0..1 para [LinearProgressIndicator.value].
  double get fracao => (percentual / 100).clamp(0.0, 1.0);

  /// Calcula % estavel: prioriza revision remota; senao estima por paginas.
  static double calcularPercentual({
    required int revisionLocal,
    int? revisionRemota,
    required bool hasMore,
    required int pagina,
    required int registrosAcumulados,
  }) {
    if (!hasMore) return 100;
    final remota = revisionRemota;
    if (remota != null && remota > 0) {
      if (revisionLocal <= 0) return 1;
      // Cap 99 enquanto hasMore — 100 so no fim.
      return ((revisionLocal / remota) * 100).clamp(1.0, 99.0);
    }
    // Sem /version: curva assintotica (pagina 1 ~12%, pagina 10 ~72%, etc.).
    final porPagina = 100 * (1 - math.pow(0.88, math.max(pagina, 1)));
    final porRegistros = registrosAcumulados <= 0
        ? 0.0
        : math.min(85.0, 8.0 + math.log(registrosAcumulados + 1) * 12);
    return math.max(porPagina, porRegistros).toDouble().clamp(1.0, 92.0);
  }

  SyncPrimeiraCargaProgresso copyWith({
    int? pagina,
    int? registrosPagina,
    int? registrosAcumulados,
    int? revisionLocal,
    int? revisionRemota,
    int? produtosLocais,
    double? percentual,
    String? mensagem,
    bool? concluido,
    String? erro,
  }) {
    return SyncPrimeiraCargaProgresso(
      pagina: pagina ?? this.pagina,
      registrosPagina: registrosPagina ?? this.registrosPagina,
      registrosAcumulados: registrosAcumulados ?? this.registrosAcumulados,
      revisionLocal: revisionLocal ?? this.revisionLocal,
      revisionRemota: revisionRemota ?? this.revisionRemota,
      produtosLocais: produtosLocais ?? this.produtosLocais,
      percentual: percentual ?? this.percentual,
      mensagem: mensagem ?? this.mensagem,
      concluido: concluido ?? this.concluido,
      erro: erro,
    );
  }
}

/// Detecta se o aparelho *poderia* hidratar do servidor (uso opcional em UI).
/// O app nao bloqueia mais o login/menu por causa disso — configure em Rede.
abstract final class SyncPrimeiraCarga {
  SyncPrimeiraCarga._();

  /// Cliente com banco vazio ou sem cursor de sync — candidato a pull inicial.
  /// Servidor local (PC modo servidor) nao precisa.
  static Future<bool> precisa({
    required ObjectBox objectBox,
    required bool redeSincronizacaoAtiva,
    required bool redeModoServidor,
    required String redeServidorUrl,
  }) async {
    if (redeModoServidor) return false;
    if (!redeSincronizacaoAtiva) return false;
    if (redeServidorUrl.trim().isEmpty) return false;

    final revision = await SyncCursorStorage().carregarUltimaRevision();
    final produtos = objectBox.produtoBox.count();
    return revision == 0 || produtos == 0;
  }

  /// Banco sem produtos / sem cursor.
  static Future<bool> precisaPorBanco(ObjectBox objectBox) async {
    final revision = await SyncCursorStorage().carregarUltimaRevision();
    return revision == 0 || objectBox.produtoBox.count() == 0;
  }

  /// Cliente com sync ativa, URL do servidor e banco vazio.
  /// (Nao trava o app; so indica que um "Sync agora" faz sentido.)
  static bool deveForcarGateCliente({
    required bool redeModoServidor,
    required bool redeSincronizacaoAtiva,
    required String redeServidorUrl,
    required bool bancoVazio,
  }) {
    if (redeModoServidor) return false;
    if (!bancoVazio) return false;
    if (!redeSincronizacaoAtiva) return false;
    return redeServidorUrl.trim().isNotEmpty;
  }
}
