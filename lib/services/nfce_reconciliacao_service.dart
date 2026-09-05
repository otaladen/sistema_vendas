import '../data/venda_repository.dart';
import '../model/venda.dart';
import 'focus_nfe_service.dart';

/// Reconsulta NFC-e pendente na Focus (processando / timeout no caixa).
class NfceReconciliacaoService {
  NfceReconciliacaoService({
    required VendaRepository vendaRepository,
    required FocusNfeService focusNfe,
  })  : _vendaRepository = vendaRepository,
        _focusNfe = focusNfe;

  final VendaRepository _vendaRepository;
  final FocusNfeService _focusNfe;

  List<Venda> listarPendentes({int limite = 80}) =>
      _vendaRepository.listarComNfcePendenteFocus(limite: limite);

  Future<NfceReconciliacaoResultado> reconsultarVenda(Venda venda) async {
    final ref = FocusNfeService.referenciaVendaNfce(venda);
    final resultado = await _focusNfe.consultarNfce(ref);
    return _aplicarResultado(venda, resultado);
  }

  Future<NfceReconciliacaoLote> reconsultarTodasPendentes({
    int limite = 80,
  }) async {
    final pendentes = listarPendentes(limite: limite);
    var autorizadas = 0;
    var aindaProcessando = 0;
    var atualizadas = 0;
    for (final venda in pendentes) {
      final r = await reconsultarVenda(venda);
      switch (r.tipo) {
        case NfceReconciliacaoTipo.autorizada:
          autorizadas++;
          atualizadas++;
          break;
        case NfceReconciliacaoTipo.processando:
          aindaProcessando++;
          atualizadas++;
          break;
        case NfceReconciliacaoTipo.semAlteracao:
        case NfceReconciliacaoTipo.erro:
          break;
      }
    }
    return NfceReconciliacaoLote(
      total: pendentes.length,
      autorizadas: autorizadas,
      aindaProcessando: aindaProcessando,
      atualizadas: atualizadas,
    );
  }

  NfceReconciliacaoResultado _aplicarResultado(
    Venda venda,
    FocusNfeEmissaoResultado resultado,
  ) {
    if (resultado.autorizada) {
      try {
        _vendaRepository.registrarNfceEmitidaComBaixaEstoque(
          vendaId: venda.id,
          chaveAcesso: resultado.chaveNfe,
          numero: resultado.numero,
          serie: resultado.serie,
          protocolo: resultado.protocolo,
          urlDanfe: resultado.urlDanfe,
          urlXml: resultado.urlXml,
          statusFocus: resultado.cancelada
              ? 'cancelado'
              : (resultado.statusFocus.isNotEmpty
                  ? resultado.statusFocus
                  : 'autorizado'),
          urlXmlCancelamento: resultado.urlXmlCancelamento,
        );
      } catch (e) {
        return NfceReconciliacaoResultado(
          tipo: NfceReconciliacaoTipo.erro,
          mensagem:
              'NFC-e autorizada na Focus, mas falhou ao salvar venda/estoque: $e',
          vendaId: venda.id,
          cupomInternoRegistrado: false,
        );
      }
      return NfceReconciliacaoResultado(
        tipo: NfceReconciliacaoTipo.autorizada,
        mensagem: resultado.mensagem,
        vendaId: venda.id,
        cupomInternoRegistrado: true,
      );
    }
    if (resultado.processando) {
      _vendaRepository.registrarNfcePendenteFocus(
        vendaId: venda.id,
        referencia: resultado.referencia.isNotEmpty
            ? resultado.referencia
            : FocusNfeService.referenciaVendaNfce(venda),
        protocolo: resultado.protocolo,
        statusFocus: resultado.statusFocus.isNotEmpty
            ? resultado.statusFocus
            : 'processando_autorizacao',
      );
      return NfceReconciliacaoResultado(
        tipo: NfceReconciliacaoTipo.processando,
        mensagem: resultado.mensagem,
        vendaId: venda.id,
      );
    }
    if (resultado.rejeitada) {
      final msg = resultado.mensagem.isEmpty
          ? 'NFC-e rejeitada na reconsulta.'
          : resultado.mensagem;
      _vendaRepository.registrarNfceErroEmissao(
        vendaId: venda.id,
        mensagem: msg,
        statusFocus: resultado.statusFocus.isNotEmpty
            ? resultado.statusFocus
            : 'erro_autorizacao',
      );
      return NfceReconciliacaoResultado(
        tipo: NfceReconciliacaoTipo.erro,
        mensagem: msg,
        vendaId: venda.id,
      );
    }
    return const NfceReconciliacaoResultado(
      tipo: NfceReconciliacaoTipo.semAlteracao,
    );
  }
}

enum NfceReconciliacaoTipo {
  autorizada,
  processando,
  semAlteracao,
  erro,
}

class NfceReconciliacaoResultado {
  const NfceReconciliacaoResultado({
    required this.tipo,
    this.mensagem = '',
    this.vendaId = 0,
    this.cupomInternoRegistrado = true,
  });

  final NfceReconciliacaoTipo tipo;
  final String mensagem;
  final int vendaId;
  final bool cupomInternoRegistrado;
}

class NfceReconciliacaoLote {
  const NfceReconciliacaoLote({
    required this.total,
    required this.autorizadas,
    required this.aindaProcessando,
    required this.atualizadas,
  });

  final int total;
  final int autorizadas;
  final int aindaProcessando;
  final int atualizadas;
}
