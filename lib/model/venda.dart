import 'package:objectbox/objectbox.dart';

import 'cliente.dart';
import 'historico_entrega.dart';
import 'item_venda.dart';
import 'vendedor.dart';

@Entity()
class Venda {
  Venda({
    this.id = 0,
    DateTime? data,
    this.total = 0,
    this.custoTotal = 0,
    this.lucroTotal = 0,
    this.status = 'orcamento',
    this.numeroOrcamento = 0,
    this.formaPagamento = 'dinheiro',
    this.quantidadeParcelas = 1,
    this.pagamentosJson = '',
    this.planoFiadoJson = '',
    this.tipoEntrega = 'retirada',
    this.valorFrete = 0,
    this.enderecoEntrega = '',
    this.observacaoEntrega = '',
    this.motoristaEntrega = '',
    this.statusEntrega = 'nao_aplicavel',
    this.prioridadeEntrega = 'normal',
    this.janelaEntrega = 'nao_definida',
    this.dataEntregaMarcada,
    this.cargaSeparada = false,
    this.cargaCarregada = false,
    this.cargaSaiu = false,
    this.carretoReservaAteSaida = false,
    this.entregaPendente = false,
    this.cancelada = false,
    this.motivoCancelamento = '',
    this.canceladaPor = '',
    this.canceladaEm,
    this.finalizadaEm,
    this.vendaOrigemFreteRetiradaId = 0,
    this.idOrcamentoFreteRetiradaAberto = 0,
    this.grupoEntregaFreteId = 0,
    this.ordemEntrega = 0,
    this.caminhaoEntrega = '',
    this.lojaOrigemMercadoria = '',
    this.complementoEntregaJson = '',
    this.nfceChaveAcesso = '',
    this.nfceNumero = '',
    this.nfceSerie = '',
    this.nfceProtocolo = '',
    this.nfceUrlDanfe = '',
    this.nfceUrlXml = '',
    this.nfceStatusFocus = '',
    this.nfceUrlXmlCancelamento = '',
    this.nfceUltimoErro = '',
    this.nfceEmitidaEm,
    this.nfeReferenciaFocus = '',
    this.nfeChaveAcesso = '',
    this.nfeNumero = '',
    this.nfeSerie = '',
    this.nfeProtocolo = '',
    this.nfeUrlDanfe = '',
    this.nfeUrlXml = '',
    this.nfeStatusFocus = '',
    this.nfeUrlXmlCancelamento = '',
    this.nfeEmitidaEm,
    this.estoqueBaixadoCupom = false,
    this.cupomNaoFiscalEmitidoEm,
    this.podRecebidoPor = '',
    this.podRegistradoPor = '',
    this.podFotoPath = '',
    this.podFotoPathServidor = '',
    this.podRegistradoEm,
    this.uuidLocal = '',
  }) : data = data ?? DateTime.now();

  @Id(assignable: true)
  int id;

  @Property(type: PropertyType.dateUtc)
  @Index()
  DateTime data;

  double total;
  double custoTotal;
  double lucroTotal;

  @Index()
  String status;

  @Index()
  int numeroOrcamento;

  String formaPagamento;
  int quantidadeParcelas;
  /// JSON lista [PagamentoOrcamentoLinha]; vazio se pagamento unico (legado).
  String pagamentosJson;

  /// JSON lista [PlanoFiadoParcela]; plano de quitação definido no PDV.
  String planoFiadoJson;

  String tipoEntrega;
  double valorFrete;
  String enderecoEntrega;
  String observacaoEntrega;
  String motoristaEntrega;
  String statusEntrega;
  String prioridadeEntrega;
  String janelaEntrega;
  @Property(type: PropertyType.dateUtc)
  DateTime? dataEntregaMarcada;
  bool cargaSeparada;
  bool cargaCarregada;
  bool cargaSaiu;

  /// Carreto com estoque reservado na finalizacao; baixa fisica ao marcar [cargaSaiu].
  /// `false` em vendas antigas (baixa no caixa) e em migracoes retirada futura > carreto.
  bool carretoReservaAteSaida;

  bool entregaPendente;

  @Index()
  bool cancelada;
  String motivoCancelamento;
  String canceladaPor;
  @Property(type: PropertyType.dateUtc)
  DateTime? canceladaEm;

  @Property(type: PropertyType.dateUtc)
  DateTime? finalizadaEm;

  /// Orcamento filho (somente frete) pendente no caixa; zerado apos pagamento.
  int idOrcamentoFreteRetiradaAberto;

  /// Na venda filha: ID da venda mae (retirada futura) que contratou o carreto.
  int vendaOrigemFreteRetiradaId;

  /// ID comum do grupo logistico na aba Entregas (mesmo valor = mesmo carro).
  /// Define-se manualmente ao agrupar notas; 0 = sem grupo.
  int grupoEntregaFreteId;

  /// Sequencia de parada no mesmo carro (1 = primeira entrega). 0 fora de grupo.
  int ordemEntrega;

  /// Legado (nao usado na UI). Expedicao identifica o veiculo pelo [motoristaEntrega].
  String caminhaoEntrega;

  /// Resumo da origem da mercadoria. Vazio ou [LojaOrigemMercadoria.outraLoja] =
  /// padrao carreto (sem baixa fisica aqui). [LojaOrigemMercadoria.local] = desta
  /// loja. [LojaOrigemMercadoria.misto] quando os itens diferem.
  String lojaOrigemMercadoria;

  /// JSON: lista de itens em falta na ida (`ComplementoEntregaCodec`).
  /// Usado com [statusEntrega] `entregue_complemento_pendente` ou pendencia em aberto.
  String complementoEntregaJson;

  /// Chave de acesso da NFC-e emitida para esta venda (apos pagamento no caixa).
  String nfceChaveAcesso;
  String nfceNumero;
  String nfceSerie;
  String nfceProtocolo;
  /// URL do PDF DANFE retornada pela API fiscal.
  String nfceUrlDanfe;

  /// URL do XML da NFC-e (Focus NFe) para fechamento contabil.
  String nfceUrlXml;

  /// Status Focus da NFC-e (autorizado, cancelado, etc.).
  String nfceStatusFocus;

  /// URL do XML de evento de cancelamento (Focus), quando houver.
  String nfceUrlXmlCancelamento;

  /// Ultima mensagem de rejeicao/erro da SEFAZ ou validacao Focus (NFC-e).
  String nfceUltimoErro;

  @Property(type: PropertyType.dateUtc)
  DateTime? nfceEmitidaEm;

  /// Ultima referencia Focus da NF-e modelo 55 (`venda_{id}_nfe` ou `venda_{id}_nfe_2`).
  String nfeReferenciaFocus;

  /// Dados da NF-e 55 sincronizados na LAN (mesmo padrao da NFC-e).
  String nfeChaveAcesso;
  String nfeNumero;
  String nfeSerie;
  String nfeProtocolo;
  String nfeUrlDanfe;
  String nfeUrlXml;
  String nfeStatusFocus;
  String nfeUrlXmlCancelamento;

  @Property(type: PropertyType.dateUtc)
  DateTime? nfeEmitidaEm;

  /// Baixa fisica de retirada imediata registrada pelo cupom nao fiscal.
  bool estoqueBaixadoCupom;

  @Property(type: PropertyType.dateUtc)
  DateTime? cupomNaoFiscalEmitidoEm;

  /// Prova de entrega (POD): quem recebeu na obra/cliente.
  String podRecebidoPor;

  /// Login do [UsuarioSistema] que registrou o POD.
  String podRegistradoPor;

  /// Caminho local do JPEG (este PC).
  String podFotoPath;

  /// Caminho relativo na pasta POD do PC servidor (sync LAN fase 2).
  String podFotoPathServidor;

  @Property(type: PropertyType.dateUtc)
  DateTime? podRegistradoEm;

  /// Chave de idempotencia do cliente (UUID) para evitar orcamento duplicado
  /// em retry apos timeout de rede. Vazio em registros legados.
  @Index()
  String uuidLocal;

  final cliente = ToOne<Cliente>();
  final vendedor = ToOne<Vendedor>();

  @Backlink('venda')
  final itens = ToMany<ItemVenda>();

  @Backlink('venda')
  final historicoEntrega = ToMany<HistoricoEntrega>();

  /// Soma dos subtotais das linhas (precos nas linhas do pedido).
  double get somaSubtotalItens =>
      itens.fold<double>(0, (s, ItemVenda i) => s + i.subtotal);

  /// NFC-e ja autorizada e registrada nesta venda.
  bool get nfceEmitida =>
      nfceChaveAcesso.trim().isNotEmpty || nfceUrlDanfe.trim().isNotEmpty;

  bool get nfceCancelada =>
      nfceStatusFocus == 'cancelado' ||
      nfceUrlXmlCancelamento.trim().isNotEmpty;

  /// NFC-e autorizada e ainda nao cancelada na SEFAZ.
  bool get nfceAutorizadaAtiva => nfceEmitida && !nfceCancelada;

  /// NFC-e enviada a Focus, aguardando retorno da SEFAZ (reconsulta automatica).
  bool get nfceProcessandoPendenteFocus {
    if (nfceEmitida) return false;
    final status = nfceStatusFocus.trim().toLowerCase();
    if (status == 'processando_autorizacao') return true;
    return nfceProtocolo.trim().contains('focus_pendente');
  }

  /// Outro passo da emissao NFC-e em curso neste PC ou na rede.
  bool get nfceEmissaoEmAndamento =>
      nfceStatusFocus.trim() == 'emissao_em_andamento';

  bool get nfe55Cancelada =>
      nfeStatusFocus == 'cancelado' ||
      nfeUrlXmlCancelamento.trim().isNotEmpty;

  /// NF-e modelo 55 autorizada (campo replicado na venda para sync multi-PC).
  bool get nfe55Autorizada =>
      !nfe55Cancelada &&
      (nfeStatusFocus == 'autorizado' ||
          (nfeChaveAcesso.trim().length >= 40));

  bool get nfe55Processando => nfeStatusFocus == 'processando_autorizacao';

  bool get nfe55Rejeitada =>
      !nfe55Autorizada &&
      !nfe55Cancelada &&
      !nfe55Processando &&
      (nfeStatusFocus == 'erro_autorizacao' || nfeStatusFocus == 'denegado');

  /// Desconto aplicado sobre o bruto (itens + frete) ate chegar em [total], quando
  /// [total] foi reduzido sem alterar [precoUnitario] nas linhas (ex.: PDV e caixa).
  double get descontoImplicitoTotal {
    final bruto = somaSubtotalItens + valorFrete;
    final d = bruto - total;
    if (d <= 0.009) {
      return 0;
    }
    return d;
  }
}
