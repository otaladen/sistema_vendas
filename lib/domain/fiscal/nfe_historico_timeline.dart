import '../../data/nfe_saida_fiscal_store.dart';

/// Evento da linha do tempo fiscal (historico NF-e).
class NfeHistoricoTimelineItem {
  const NfeHistoricoTimelineItem({
    required this.titulo,
    required this.subtitulo,
    required this.concluido,
    this.erro = false,
  });

  final String titulo;
  final String subtitulo;
  final bool concluido;
  final bool erro;
}

abstract final class NfeHistoricoTimelineBuilder {
  NfeHistoricoTimelineBuilder._();

  static List<NfeHistoricoTimelineItem> fromRegistro(NfeSaidaFiscalRegistro r) {
    final itens = <NfeHistoricoTimelineItem>[
      NfeHistoricoTimelineItem(
        titulo: 'Enviado a Focus NFe',
        subtitulo: 'Ref. ${r.referenciaFocus}',
        concluido: true,
      ),
    ];

    if (r.processando && !r.autorizada && !r.rejeitada && !r.cancelada) {
      itens.add(
        const NfeHistoricoTimelineItem(
          titulo: 'Aguardando SEFAZ',
          subtitulo: 'Processando autorizacao',
          concluido: false,
        ),
      );
    }

    if (r.autorizada) {
      itens.add(
        NfeHistoricoTimelineItem(
          titulo: 'Autorizada pela SEFAZ',
          subtitulo: r.numero.isNotEmpty
              ? 'NF-e ${r.numero}${r.serie.isNotEmpty ? " serie ${r.serie}" : ""}'
              : (r.chaveNfe.isNotEmpty ? 'Chave emitida' : 'Autorizada'),
          concluido: true,
        ),
      );
    }

    if (r.rejeitada) {
      itens.add(
        NfeHistoricoTimelineItem(
          titulo: 'Rejeitada',
          subtitulo: r.mensagemSefaz.isNotEmpty
              ? r.mensagemSefaz
              : 'Verifique o erro e reemita',
          concluido: true,
          erro: true,
        ),
      );
    }

    if (r.numeroCartaCorrecao > 0) {
      itens.add(
        NfeHistoricoTimelineItem(
          titulo: 'Carta de Correcao (CC-e)',
          subtitulo: 'Sequencia ${r.numeroCartaCorrecao}',
          concluido: true,
        ),
      );
    }

    if (r.cancelada) {
      itens.add(
        NfeHistoricoTimelineItem(
          titulo: 'Cancelada',
          subtitulo: r.mensagemSefaz.isNotEmpty
              ? r.mensagemSefaz
              : 'Evento de cancelamento registrado',
          concluido: true,
          erro: true,
        ),
      );
    }

    return itens;
  }
}
