import '../services/fiscal_config_store.dart';
import '../config/focus_nfe_runtime.dart';
import '../data/cliente_repository.dart';
import '../data/devolucao_fiscal_store.dart';
import '../data/nfe_saida_fiscal_store.dart';
import '../data/venda_repository.dart';
import '../domain/fiscal/endereco_fiscal_ibge_resolver.dart';
import '../domain/fiscal/nfe_registro_focus_merge.dart';
import '../domain/produto_nome_exibicao.dart';
import '../model/cliente.dart';
import '../model/item_venda.dart';
import '../model/venda.dart';
import 'focus_nfe_reconsulta_helper.dart';
import 'focus_nfe_service.dart';

/// Resultado de operacao fiscal vinculada a venda (cancelamento ou devolucao).
class VendaFiscalOperacaoResultado {
  const VendaFiscalOperacaoResultado({
    required this.sucesso,
    this.mensagem = '',
    this.nfceCancelada = false,
    this.nfeCancelada = false,
    this.nfeDevolucaoAutorizada = false,
    this.chaveDevolucao = '',
    this.urlDanfeDevolucao = '',
    this.referenciaDevolucao = '',
    this.numeroDevolucao = '',
    this.serieDevolucao = '',
    this.urlXmlDevolucao = '',
    this.statusFocusDevolucao = '',
  });

  final bool sucesso;
  final String mensagem;
  final bool nfceCancelada;
  final bool nfeCancelada;
  final bool nfeDevolucaoAutorizada;
  final String chaveDevolucao;
  final String urlDanfeDevolucao;
  final String referenciaDevolucao;
  final String numeroDevolucao;
  final String serieDevolucao;
  final String urlXmlDevolucao;
  final String statusFocusDevolucao;

  factory VendaFiscalOperacaoResultado.erro(String msg) =>
      VendaFiscalOperacaoResultado(sucesso: false, mensagem: msg);

  factory VendaFiscalOperacaoResultado.ok({
    String mensagem = '',
    bool nfceCancelada = false,
    bool nfeCancelada = false,
    bool nfeDevolucaoAutorizada = false,
    String chaveDevolucao = '',
    String urlDanfeDevolucao = '',
    String referenciaDevolucao = '',
    String numeroDevolucao = '',
    String serieDevolucao = '',
    String urlXmlDevolucao = '',
    String statusFocusDevolucao = '',
  }) =>
      VendaFiscalOperacaoResultado(
        sucesso: true,
        mensagem: mensagem,
        nfceCancelada: nfceCancelada,
        nfeCancelada: nfeCancelada,
        nfeDevolucaoAutorizada: nfeDevolucaoAutorizada,
        chaveDevolucao: chaveDevolucao,
        urlDanfeDevolucao: urlDanfeDevolucao,
        referenciaDevolucao: referenciaDevolucao,
        numeroDevolucao: numeroDevolucao,
        serieDevolucao: serieDevolucao,
        urlXmlDevolucao: urlXmlDevolucao,
        statusFocusDevolucao: statusFocusDevolucao,
      );
}

/// Cancelamento SEFAZ + NF-e de devolucao integrados ao ERP.
class VendaFiscalService {
  VendaFiscalService({
    required this.vendaRepository,
    required this.clienteRepository,
    FocusNfeService? focusNfe,
  }) : _focus = focusNfe ?? FocusNfeService(config: criarFocusNfeConfigPadrao());

  final VendaRepository vendaRepository;
  final ClienteRepository clienteRepository;
  final FocusNfeService _focus;

  NfeSaidaFiscalStore get _nfeStore =>
      NfeSaidaFiscalStore(vendaRepository.objectBox.storeDirectoryPath);

  DevolucaoFiscalStore get _devolucaoStore => DevolucaoFiscalStore(
        vendaRepository.objectBox.storeDirectoryPath,
      );

  static String validarJustificativa(String justificativa) {
    final just = justificativa.trim();
    if (just.length < 15) {
      return 'Justificativa fiscal deve ter no minimo 15 caracteres.';
    }
    if (just.length > 255) {
      return 'Justificativa fiscal deve ter no maximo 255 caracteres.';
    }
    return '';
  }

  bool vendaExigeCancelamentoFiscal(Venda venda) =>
      venda.nfceAutorizadaAtiva || venda.nfe55Autorizada;

  bool vendaExigeNfeDevolucao(Venda venda) =>
      venda.nfceAutorizadaAtiva || venda.nfe55Autorizada;

  /// Cancela NFC-e e/ou NF-e 55 na SEFAZ antes de cancelar a venda no ERP.
  Future<VendaFiscalOperacaoResultado> cancelarDocumentosFiscaisVenda({
    required Venda venda,
    required String justificativa,
  }) async {
    if (!FiscalConfigStore.configurado) {
      return VendaFiscalOperacaoResultado.erro(
        'Focus NFe nao configurada. Configure em Configuracoes antes de cancelar '
        'venda com nota fiscal.',
      );
    }

    final erroJust = validarJustificativa(justificativa);
    if (erroJust.isNotEmpty) {
      return VendaFiscalOperacaoResultado.erro(erroJust);
    }

    if (!vendaExigeCancelamentoFiscal(venda)) {
      return VendaFiscalOperacaoResultado.ok(
        mensagem: 'Venda sem documento fiscal ativo.',
      );
    }

    _focus.validarConfiguracao();

    var nfceCancelada = false;
    var nfeCancelada = false;
    final mensagens = <String>[];

    if (venda.nfceAutorizadaAtiva) {
      final ref = FocusNfeService.referenciaVendaNfce(venda);
      var resultado = await _focus.cancelarNfce(
        ref,
        justificativa: justificativa,
      );
      if (resultado.rejeitada && !resultado.cancelada) {
        resultado = await FocusNfeReconsultaHelper.recuperarSePossivel(
          original: resultado,
          reconsultar: () => _focus.consultarNfce(ref),
        );
        if (!resultado.cancelada && !resultado.autorizada) {
          final consulta = await _focus.consultarNfce(ref);
          if (consulta.cancelada) {
            resultado = consulta;
          } else {
            return VendaFiscalOperacaoResultado.erro(
              resultado.mensagem.isNotEmpty
                  ? resultado.mensagem
                  : 'SEFAZ nao aceitou o cancelamento da NFC-e.',
            );
          }
        }
      }
      if (!resultado.cancelada) {
        if (resultado.processando) {
          return VendaFiscalOperacaoResultado.erro(
            'Cancelamento da NFC-e em processamento na SEFAZ. '
            'Aguarde a confirmacao e tente novamente.',
          );
        }
        return VendaFiscalOperacaoResultado.erro(
          resultado.mensagem.isNotEmpty
              ? resultado.mensagem
              : 'Cancelamento da NFC-e nao confirmado pela SEFAZ.',
        );
      }

      vendaRepository.registrarNfceCancelada(
        vendaId: venda.id,
        statusFocus: resultado.statusFocus.isNotEmpty
            ? resultado.statusFocus
            : 'cancelado',
        urlXmlCancelamento: resultado.urlXmlCancelamento,
        protocolo: resultado.protocolo,
      );
      nfceCancelada = true;
      mensagens.add('NFC-e cancelada na SEFAZ.');
    }

    if (venda.nfe55Autorizada) {
      final reg = _nfeStore.ultimaAutorizadaPorVenda(venda.id);
      final ref = (reg?.referenciaFocus.trim().isNotEmpty == true)
          ? reg!.referenciaFocus
          : (venda.nfeReferenciaFocus.trim().isNotEmpty
              ? venda.nfeReferenciaFocus
              : FocusNfeService.referenciaVendaNfe(venda));

      var resultado = await _focus.cancelarNfe(ref, justificativa: justificativa);
      if (resultado.rejeitada && !resultado.cancelada) {
        resultado = await FocusNfeReconsultaHelper.recuperarSePossivel(
          original: resultado,
          reconsultar: () => _focus.consultarNfe(ref),
        );
      }
      if (!resultado.cancelada) {
        if (resultado.processando) {
          return VendaFiscalOperacaoResultado.erro(
            'Cancelamento da NF-e em processamento na SEFAZ. '
            'Aguarde a confirmacao e tente novamente.',
          );
        }
        return VendaFiscalOperacaoResultado.erro(
          resultado.mensagem.isNotEmpty
              ? resultado.mensagem
              : 'SEFAZ nao aceitou o cancelamento da NF-e.',
        );
      }

      if (reg != null) {
        _nfeStore.gravar(mesclarRegistroComResultadoFocus(reg, resultado));
      }
      vendaRepository.registrarNfe55Situacao(
        vendaId: venda.id,
        referenciaFocus: ref,
        statusFocus: resultado.statusFocus.isNotEmpty
            ? resultado.statusFocus
            : 'cancelado',
        urlXmlCancelamento: resultado.urlXmlCancelamento,
        chaveAcesso: venda.nfeChaveAcesso,
      );
      nfeCancelada = true;
      mensagens.add('NF-e cancelada na SEFAZ.');
    }

    return VendaFiscalOperacaoResultado.ok(
      mensagem: mensagens.join(' '),
      nfceCancelada: nfceCancelada,
      nfeCancelada: nfeCancelada,
    );
  }

  /// Emite NF-e de devolucao (finalidade 4) para itens devolvidos pelo cliente.
  Future<VendaFiscalOperacaoResultado> emitirNfeDevolucaoVenda({
    required Venda venda,
    required List<({ItemVenda item, int quantidade})> itensDevolvidos,
    required String motivo,
    required int registroDevolucaoId,
  }) async {
    if (!FiscalConfigStore.configurado) {
      return VendaFiscalOperacaoResultado.erro(
        'Focus NFe nao configurada. Configure em Configuracoes.',
      );
    }
    if (itensDevolvidos.isEmpty) {
      return VendaFiscalOperacaoResultado.erro(
        'Nenhum item informado para devolucao fiscal.',
      );
    }
    if (!vendaExigeNfeDevolucao(venda)) {
      return VendaFiscalOperacaoResultado.ok(
        mensagem: 'Venda sem NFC-e/NF-e — devolucao apenas operacional.',
      );
    }

    final chaveOriginal = _resolverChaveNotaOriginal(venda);
    if (chaveOriginal == null) {
      return VendaFiscalOperacaoResultado.erro(
        'Chave da nota original nao encontrada. Reconsulte a NFC-e/NF-e '
        'no painel fiscal antes de registrar a devolucao.',
      );
    }

    final cliente = await _resolverClienteDestinatario(venda);
    if (cliente == null) {
      return VendaFiscalOperacaoResultado.erro(
        'Cadastre o cliente da venda com endereco completo (CEP, IBGE) '
        'para emitir NF-e de devolucao.',
      );
    }

    final ibge = await EnderecoFiscalIbgeResolver.resolverParaCliente(cliente);
    if (!ibge.sucesso || ibge.codigoIbge.trim().isEmpty) {
      return VendaFiscalOperacaoResultado.erro(
        ibge.mensagem.isNotEmpty
            ? ibge.mensagem
            : 'Nao foi possivel resolver o codigo IBGE do cliente.',
      );
    }

    final destinatario = FocusNfeDestinatarioNfe.fromCliente(
      cliente,
      codigoMunicipioIbge: ibge.codigoIbge,
      enderecoOverride: ibge.endereco,
    );

    final itensFiscais = <FocusNfeItemDevolucao>[];
    for (final linha in itensDevolvidos) {
      final produto = linha.item.produto.target;
      if (produto == null) {
        return VendaFiscalOperacaoResultado.erro(
          'Item "${linha.item.nomeProduto}" sem produto vinculado.',
        );
      }
      itensFiscais.add(
        FocusNfeItemDevolucao(
          produto: produto,
          descricao: ProdutoNomeExibicao.paraImpressaoItem(linha.item),
          quantidade: linha.quantidade,
          valorUnitario: linha.item.precoUnitario,
        ),
      );
    }

    final referencia = registroDevolucaoId > 0
        ? FocusNfeService.referenciaDevolucaoVenda(
            vendaId: venda.id,
            registroDevolucaoId: registroDevolucaoId,
          )
        : 'venda_${venda.id}_dev_${DateTime.now().millisecondsSinceEpoch}';

    _focus.validarConfiguracao();
    var resultado = await _focus.emitirNfeDevolucao(
      referencia: referencia,
      chaveNotaOriginal: chaveOriginal,
      destinatario: destinatario,
      itensDevolucao: itensFiscais,
      motivo: motivo,
    );

    if (!resultado.autorizada && !resultado.processando) {
      resultado = await FocusNfeReconsultaHelper.recuperarSePossivel(
        original: resultado,
        reconsultar: () => _focus.consultarNfe(referencia),
      );
    }

    if (!resultado.autorizada && !resultado.processando) {
      return VendaFiscalOperacaoResultado.erro(
        resultado.mensagem.isNotEmpty
            ? resultado.mensagem
            : 'NF-e de devolucao rejeitada pela SEFAZ.',
      );
    }

    if (registroDevolucaoId > 0) {
      _devolucaoStore.salvar(
        DevolucaoFiscalRegistro(
          registroDevolucaoId: registroDevolucaoId,
          vendaId: venda.id,
          referenciaFocus: referencia,
          chaveNfe: resultado.chaveNfe,
          numero: resultado.numero,
          serie: resultado.serie,
          urlDanfe: resultado.urlDanfe,
          urlXml: resultado.urlXml,
          statusFocus: resultado.statusFocus.isNotEmpty
              ? resultado.statusFocus
              : 'autorizado',
          motivo: motivo,
        ),
      );
    }

    return VendaFiscalOperacaoResultado.ok(
      mensagem: resultado.autorizada
          ? 'NF-e de devolucao autorizada (nº ${resultado.numero}).'
          : 'NF-e de devolucao enviada — aguardando autorizacao.',
      nfeDevolucaoAutorizada: resultado.autorizada,
      chaveDevolucao: resultado.chaveNfe,
      urlDanfeDevolucao: resultado.urlDanfe,
      referenciaDevolucao: referencia,
      numeroDevolucao: resultado.numero,
      serieDevolucao: resultado.serie,
      urlXmlDevolucao: resultado.urlXml,
      statusFocusDevolucao: resultado.statusFocus.isNotEmpty
          ? resultado.statusFocus
          : 'autorizado',
    );
  }

  void salvarDevolucaoFiscalLocal({
    required int registroDevolucaoId,
    required int vendaId,
    required String referenciaFocus,
    required String chaveNfe,
    String numero = '',
    String serie = '',
    String urlDanfe = '',
    String urlXml = '',
    String statusFocus = 'autorizado',
    String motivo = '',
  }) {
    _devolucaoStore.salvar(
      DevolucaoFiscalRegistro(
        registroDevolucaoId: registroDevolucaoId,
        vendaId: vendaId,
        referenciaFocus: referenciaFocus,
        chaveNfe: chaveNfe,
        numero: numero,
        serie: serie,
        urlDanfe: urlDanfe,
        urlXml: urlXml,
        statusFocus: statusFocus,
        motivo: motivo,
      ),
    );
  }

  List<DevolucaoFiscalRegistro> listarDevolucoesFiscaisPorVenda(int vendaId) =>
      _devolucaoStore.listarPorVenda(vendaId);

  DevolucaoFiscalRegistro? devolucaoFiscalPorRegistro(int registroDevolucaoId) =>
      _devolucaoStore.porRegistroDevolucao(registroDevolucaoId);

  String? _resolverChaveNotaOriginal(Venda venda) {
    if (venda.nfe55Autorizada) {
      final chave = venda.nfeChaveAcesso.replaceAll(RegExp(r'\D'), '');
      if (chave.length == 44) return chave;
      final reg = _nfeStore.ultimaAutorizadaPorVenda(venda.id);
      final chReg = reg?.chaveNfe.replaceAll(RegExp(r'\D'), '') ?? '';
      if (chReg.length == 44) return chReg;
    }
    if (venda.nfceAutorizadaAtiva) {
      final chave = venda.nfceChaveAcesso.replaceAll(RegExp(r'\D'), '');
      if (chave.length == 44) return chave;
    }
    return null;
  }

  Future<Cliente?> _resolverClienteDestinatario(Venda venda) async {
    final alvo = venda.cliente.target;
    if (alvo != null) return alvo;
    final id = venda.cliente.targetId;
    if (id > 0) {
      return clienteRepository.obterPorId(id);
    }
    return null;
  }
}
