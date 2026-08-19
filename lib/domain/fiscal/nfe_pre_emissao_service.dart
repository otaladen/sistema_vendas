import '../../config/fiscal_config.dart';
import 'fiscal_regime_padrao.dart';
import '../../services/fiscal_config_store.dart';
import '../../data/nfe_saida_fiscal_store.dart';
import '../../model/cliente.dart';
import '../../model/item_venda.dart';
import '../../model/produto.dart';
import '../../model/venda.dart';
import '../../services/focus_nfe_service.dart';
import '../entregas/romaneio_carga_merge.dart';
import '../pagamento_orcamento.dart';
import 'endereco_fiscal_ibge_resolver.dart';
import 'fiscal_emissao_lock.dart';
import 'nfe_cobranca_helper.dart';
import 'nfe_fiscal_helpers.dart';
import 'nfe_item_fiscal_preview.dart';
import 'venda_documento_fiscal_mutex.dart';

enum NfeChecklistSeveridade { ok, aviso, bloqueio }

class NfeChecklistItem {
  const NfeChecklistItem({
    required this.titulo,
    required this.severidade,
    this.detalhe,
  });

  final String titulo;
  final String? detalhe;
  final NfeChecklistSeveridade severidade;

  bool get bloqueia => severidade == NfeChecklistSeveridade.bloqueio;
}

/// Resultado da conferencia pre-emissao (checklist + itens fiscais).
class NfePreEmissaoResultado {
  const NfePreEmissaoResultado({
    required this.checklist,
    required this.linhasFiscais,
    required this.ufDestinatario,
    required this.consumidorFinal,
    required this.interestadual,
    this.destinatarioPreview,
    this.valorCobrancaPrazo = 0,
    this.quantidadeDuplicatas = 0,
  });

  final List<NfeChecklistItem> checklist;
  final List<NfeItemFiscalPreview> linhasFiscais;
  final String ufDestinatario;
  final bool consumidorFinal;
  final bool interestadual;
  final FocusNfeDestinatarioNfe? destinatarioPreview;
  final double valorCobrancaPrazo;
  final int quantidadeDuplicatas;

  int get totalBloqueios =>
      checklist.where((c) => c.bloqueia).length +
      linhasFiscais.where((l) => l.bloqueiaEmissao).length;

  int get totalAvisos => checklist
      .where((c) => c.severidade == NfeChecklistSeveridade.aviso)
      .length;

  bool get podeEmitir => totalBloqueios == 0 && linhasFiscais.isNotEmpty;
}

abstract final class NfePreEmissaoService {
  NfePreEmissaoService._();

  static NfePreEmissaoResultado avaliar({
    required Venda venda,
    required Cliente? cliente,
    required EnderecoIbgeResolvido? ibge,
    NfeSaidaFiscalRegistro? nfeAutorizada,
    NfeSaidaFiscalRegistro? nfeUltima,
    String? deviceIdAtual,
    /// Terminal leve: Focus/SEFAZ rodam no PC servidor.
    bool emissaoNoServidor = false,
    List<ItemVenda>? itens,
    Produto? Function(int produtoId)? resolverProduto,
  }) {
    final checklist = <NfeChecklistItem>[];
    FocusNfeDestinatarioNfe? destPreview;
    var ufDest = FiscalConfig.ufEmitente;
    var consumidorFinal = true;
    final listaItens =
        itens ?? RomaneioCargaMerge.itensDaVendaSafe(venda);

    if (!FiscalConfigStore.configurado) {
      if (emissaoNoServidor) {
        checklist.add(
          const NfeChecklistItem(
            titulo: 'Focus NFe / emitente',
            detalhe:
                'Emissao sera executada no PC servidor (token Focus local nao e necessario).',
            severidade: NfeChecklistSeveridade.ok,
          ),
        );
      } else {
        checklist.add(
          const NfeChecklistItem(
            titulo: 'Focus NFe / emitente',
            detalhe: 'Configure token, CNPJ e IE em Configuracoes > Fiscal.',
            severidade: NfeChecklistSeveridade.bloqueio,
          ),
        );
      }
    } else {
      checklist.add(
        NfeChecklistItem(
          titulo:
              'Focus NFe (${FiscalConfigStore.efetivo.homologacao ? "homologacao" : "producao"})',
          detalhe:
              'Emitente ${FiscalConfigStore.efetivo.cnpjEmitente} · '
              'UF ${FiscalConfigStore.efetivo.ufEmitente} · '
              '${FiscalRegimePadrao.rotuloRegime(FiscalRegimePadrao.regimeEfetivo())} · '
              '${FiscalRegimePadrao.resumoPadroesEmissao(FiscalRegimePadrao.regimeEfetivo())}',
          severidade: NfeChecklistSeveridade.ok,
        ),
      );
    }

    if (cliente == null) {
      checklist.add(
        const NfeChecklistItem(
          titulo: 'Cliente da venda',
          detalhe: 'Vincule um cliente ao orcamento antes da NF-e.',
          severidade: NfeChecklistSeveridade.bloqueio,
        ),
      );
    } else {
      checklist.add(
        NfeChecklistItem(
          titulo: 'Cliente: ${cliente.nomeRazao}',
          severidade: NfeChecklistSeveridade.ok,
        ),
      );
    }

    if (ibge == null || !ibge.sucesso) {
      checklist.add(
        NfeChecklistItem(
          titulo: 'Codigo IBGE do municipio',
          detalhe: ibge?.mensagem ?? 'Aguardando resolucao do endereco.',
          severidade: NfeChecklistSeveridade.bloqueio,
        ),
      );
    } else {
      checklist.add(
        NfeChecklistItem(
          titulo: 'IBGE ${ibge.codigoIbge}',
          detalhe: ibge.origem,
          severidade: NfeChecklistSeveridade.ok,
        ),
      );
      ufDest = ibge.endereco?.uf.trim().toUpperCase() ?? ufDest;
      if (cliente != null) {
        try {
          destPreview = FocusNfeDestinatarioNfe.fromCliente(
            cliente,
            codigoMunicipioIbge: ibge.codigoIbge,
            enderecoOverride: ibge.endereco,
          );
          destPreview.validar();
          consumidorFinal = NfeFiscalHelpers.consumidorFinalDestinatario(
            destPreview,
          );
          checklist.add(
            NfeChecklistItem(
              titulo: destPreview.indicadorInscricaoEstadual == '1'
                  ? 'Contribuinte ICMS (IE informada)'
                  : 'Destinatario ${destPreview.indicadorInscricaoEstadual == "9" ? "nao contribuinte" : "isento/outro"}',
              severidade: NfeChecklistSeveridade.ok,
            ),
          );
        } on FocusNfeValidacaoException catch (e) {
          checklist.add(
            NfeChecklistItem(
              titulo: 'Dados fiscais do destinatario',
              detalhe: e.message,
              severidade: NfeChecklistSeveridade.bloqueio,
            ),
          );
        }
      }
    }

    final emitente = FiscalConfig.ufEmitente.toUpperCase();
    final interestadual = ufDest.isNotEmpty && ufDest != emitente;
    if (interestadual) {
      checklist.add(
        NfeChecklistItem(
          titulo: 'Operacao interestadual ($emitente → $ufDest)',
          detalhe: 'CFOPs 61xx/64xx nos itens.',
          severidade: NfeChecklistSeveridade.aviso,
        ),
      );
    } else if (!consumidorFinal) {
      checklist.add(
        NfeChecklistItem(
          titulo: 'Venda estadual a contribuinte (construtora)',
          detalhe: 'CFOPs 5101/5401 nos itens tributados/ST.',
          severidade: NfeChecklistSeveridade.ok,
        ),
      );
    }

    if (venda.nfe55Autorizada ||
        (nfeAutorizada != null && nfeAutorizada.autorizada)) {
      final ref = venda.nfeReferenciaFocus.isNotEmpty
          ? venda.nfeReferenciaFocus
          : (nfeAutorizada?.referenciaFocus ?? '');
      final num = venda.nfeNumero.isNotEmpty
          ? venda.nfeNumero
          : (nfeAutorizada?.numero ?? '');
      checklist.add(
        NfeChecklistItem(
          titulo: 'NF-e ja autorizada',
          detalhe: 'Nota ${num.isNotEmpty ? num : ref}',
          severidade: NfeChecklistSeveridade.bloqueio,
        ),
      );
    } else if (venda.nfe55Processando || nfeUltima?.processando == true) {
      checklist.add(
        const NfeChecklistItem(
          titulo: 'NF-e em processamento',
          detalhe: 'Reconsulte no historico antes de reenviar.',
          severidade: NfeChecklistSeveridade.bloqueio,
        ),
      );
    }

    final bloqueioNfePorNfce = VendaDocumentoFiscalMutex.mensagemBloqueioNovaNfe55(
      venda,
    );
    if (bloqueioNfePorNfce != null) {
      checklist.add(
        NfeChecklistItem(
          titulo: 'NFC-e ja emitida nesta venda',
          detalhe: bloqueioNfePorNfce,
          severidade: NfeChecklistSeveridade.bloqueio,
        ),
      );
    }

    final deviceId = deviceIdAtual?.trim() ?? '';
    if (deviceId.isNotEmpty &&
        FiscalEmissaoLock.nfceBloqueadaPorOutroDispositivo(
          venda,
          deviceId,
        )) {
      checklist.add(
        const NfeChecklistItem(
          titulo: 'NFC-e em emissao em outro PC',
          detalhe:
              'Aguarde a conclusao da emissao no outro caixa ou tente novamente em alguns minutos.',
          severidade: NfeChecklistSeveridade.bloqueio,
        ),
      );
    }

    if (deviceId.isNotEmpty &&
        FiscalEmissaoLock.nfeBloqueadaPorOutroDispositivo(
          venda,
          deviceId,
        )) {
      checklist.add(
        const NfeChecklistItem(
          titulo: 'NF-e em emissao em outro PC',
          detalhe:
              'Aguarde a conclusao da emissao na outra estacao antes de continuar.',
          severidade: NfeChecklistSeveridade.bloqueio,
        ),
      );
    }

    if (listaItens.where((i) => i.quantidade > 0).isEmpty) {
      checklist.add(
        const NfeChecklistItem(
          titulo: 'Itens da venda',
          detalhe: 'Nenhum item com quantidade para faturar.',
          severidade: NfeChecklistSeveridade.bloqueio,
        ),
      );
    }

    if (venda.formaPagamento == 'misto') {
      final linhas = PagamentoOrcamentoCodec.decode(venda.pagamentosJson);
      final soma = PagamentoOrcamentoCodec.soma(linhas);
      if ((soma - venda.total).abs() > 0.02) {
        checklist.add(
          NfeChecklistItem(
            titulo: 'Pagamento misto',
            detalhe:
                'Soma dos meios (${soma.toStringAsFixed(2)}) difere do total (${venda.total.toStringAsFixed(2)}).',
            severidade: NfeChecklistSeveridade.aviso,
          ),
        );
      }
    }

    var valorCobranca = 0.0;
    var qtdDup = 0;
    if (NfeCobrancaHelper.vendaExigeBlocoCobranca(venda)) {
      valorCobranca = NfeCobrancaHelper.valorCobrancaVenda(venda);
      final parcelas = NfeCobrancaHelper.resolverParcelas(venda, valorCobranca);
      qtdDup = parcelas.length;
      if (parcelas.isEmpty || valorCobranca <= 0) {
        checklist.add(
          const NfeChecklistItem(
            titulo: 'Cobranca a prazo',
            detalhe: 'Defina parcelas (fiado/boleto) no PDV antes da NF-e.',
            severidade: NfeChecklistSeveridade.bloqueio,
          ),
        );
      } else {
        checklist.add(
          NfeChecklistItem(
            titulo: 'Fatura na NF-e',
            detalhe:
                '$qtdDup duplicata(s) · R\$ ${valorCobranca.toStringAsFixed(2)}',
            severidade: NfeChecklistSeveridade.ok,
          ),
        );
      }
    }

    final linhasFiscais = NfeItemFiscalPreviewBuilder.fromVenda(
      venda,
      consumidorFinal: consumidorFinal,
      ufDestinatario: ufDest,
      itens: listaItens,
      resolverProduto: resolverProduto,
    );

    if (linhasFiscais.isEmpty && listaItens.isNotEmpty) {
      checklist.add(
        const NfeChecklistItem(
          titulo: 'Itens fiscais',
          detalhe: 'Nenhuma linha valida para a nota.',
          severidade: NfeChecklistSeveridade.bloqueio,
        ),
      );
    } else if (linhasFiscais.every((l) => !l.bloqueiaEmissao)) {
      checklist.add(
        NfeChecklistItem(
          titulo: '${linhasFiscais.length} item(ns) fiscal(is) conferido(s)',
          severidade: NfeChecklistSeveridade.ok,
        ),
      );
    }

    return NfePreEmissaoResultado(
      checklist: checklist,
      linhasFiscais: linhasFiscais,
      ufDestinatario: ufDest,
      consumidorFinal: consumidorFinal,
      interestadual: interestadual,
      destinatarioPreview: destPreview,
      valorCobrancaPrazo: valorCobranca,
      quantidadeDuplicatas: qtdDup,
    );
  }
}
