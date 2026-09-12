import 'dart:io';

import 'package:objectbox/objectbox.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../data/models/conta_pagar.dart';
import '../model/item_venda.dart';
import '../model/linha_devolucao_entrada.dart';
import '../model/linha_troca_saida.dart';
import '../model/registro_devolucao.dart';
import '../model/uso_vale_credito.dart';
import '../model/vale_credito.dart';
import '../model/cliente.dart';
import '../model/fornecedor_nfe.dart';
import '../model/historico_entrada.dart';
import '../model/movimento_estoque.dart';
import '../model/lote_produto.dart';
import '../model/fechamento_rh_funcionario.dart';
import '../model/funcionario.dart';
import '../model/lancamento_funcionario.dart';
import '../model/recebimento_fiado.dart';
import '../model/titulo_receber.dart';
import '../model/historico_entrega.dart';
import '../model/motorista.dart';
import '../model/produto.dart';
import '../model/vinculo_fornecedor_produto.dart';
import '../model/kit_orcamento.dart';
import '../model/promocao.dart';
import '../model/promocao_combo_item.dart';
import '../model/promocao_item.dart';
import '../model/auditoria_evento.dart';
import '../model/caixa_auditoria_evento.dart';
import '../model/item_inventario.dart';
import '../model/item_lista_compra.dart';
import '../model/produto_sugestao_venda.dart';
import '../model/sugestao_venda_metrica_evento.dart';
import '../model/recado_loja.dart';
import '../model/conferencia_carga_romaneio.dart';
import '../model/sessao_inventario.dart';
import '../model/reajuste_preco.dart';
import '../model/reajuste_preco_item.dart';
import '../model/nfe_importada_registro.dart';
import '../model/obrigacao_mensal_fixa.dart';
import '../model/venda.dart';
import '../model/vendedor.dart';
import '../objectbox.g.dart';

class ObjectBox {
  ObjectBox._create(this.store) {
    _inicializarBoxes();
  }

  late Store store;
  late Box<Produto> produtoBox;
  late Box<Cliente> clienteBox;
  late Box<Venda> vendaBox;
  late Box<ItemVenda> itemVendaBox;
  late Box<RegistroDevolucao> registroDevolucaoBox;
  late Box<LinhaDevolucaoEntrada> linhaDevolucaoEntradaBox;
  late Box<LinhaTrocaSaida> linhaTrocaSaidaBox;
  late Box<ValeCredito> valeCreditoBox;
  late Box<UsoValeCredito> usoValeCreditoBox;
  late Box<HistoricoEntrega> historicoEntregaBox;
  late Box<Motorista> motoristaBox;
  late Box<Vendedor> vendedorBox;
  late Box<Funcionario> funcionarioBox;
  late Box<LancamentoFuncionario> lancamentoFuncionarioBox;
  late Box<FechamentoRhFuncionario> fechamentoRhFuncionarioBox;
  late Box<FornecedorNfe> fornecedorNfeBox;
  late Box<VinculoFornecedorProduto> vinculoFornecedorProdutoBox;
  late Box<HistoricoEntrada> historicoEntradaBox;
  late Box<MovimentoEstoque> movimentoEstoqueBox;
  late Box<LoteProduto> loteProdutoBox;
  late Box<NfeImportadaRegistro> nfeImportadaRegistroBox;
  late Box<KitOrcamento> kitOrcamentoBox;
  late Box<KitOrcamentoItem> kitOrcamentoItemBox;
  late Box<Promocao> promocaoBox;
  late Box<PromocaoItem> promocaoItemBox;
  late Box<PromocaoComboItem> promocaoComboItemBox;
  late Box<ContaPagar> contaPagarBox;
  late Box<TituloReceber> tituloReceberBox;
  late Box<RecebimentoFiado> recebimentoFiadoBox;
  late Box<ReajustePreco> reajustePrecoBox;
  late Box<ReajustePrecoItem> reajustePrecoItemBox;
  late Box<AuditoriaEvento> auditoriaEventoBox;
  late Box<CaixaAuditoriaEvento> caixaAuditoriaEventoBox;
  late Box<ItemListaCompra> itemListaCompraBox;
  late Box<ProdutoSugestaoVenda> produtoSugestaoVendaBox;
  late Box<SugestaoVendaMetricaEvento> sugestaoVendaMetricaEventoBox;
  late Box<RecadoLoja> recadoLojaBox;
  late Box<ConferenciaCargaRomaneio> conferenciaCargaRomaneioBox;
  late Box<ObrigacaoMensalFixa> obrigacaoMensalFixaBox;
  late Box<SessaoInventario> sessaoInventarioBox;
  late Box<ItemInventario> itemInventarioBox;
  late Directory productImagesDir;
  late Directory funcionarioImagesDir;
  late String storeDirectoryPath;

  void _inicializarBoxes() {
    produtoBox = Box<Produto>(store);
    clienteBox = Box<Cliente>(store);
    vendaBox = Box<Venda>(store);
    itemVendaBox = Box<ItemVenda>(store);
    registroDevolucaoBox = Box<RegistroDevolucao>(store);
    linhaDevolucaoEntradaBox = Box<LinhaDevolucaoEntrada>(store);
    linhaTrocaSaidaBox = Box<LinhaTrocaSaida>(store);
    valeCreditoBox = Box<ValeCredito>(store);
    usoValeCreditoBox = Box<UsoValeCredito>(store);
    historicoEntregaBox = Box<HistoricoEntrega>(store);
    motoristaBox = Box<Motorista>(store);
    vendedorBox = Box<Vendedor>(store);
    funcionarioBox = Box<Funcionario>(store);
    lancamentoFuncionarioBox = Box<LancamentoFuncionario>(store);
    fechamentoRhFuncionarioBox = Box<FechamentoRhFuncionario>(store);
    fornecedorNfeBox = Box<FornecedorNfe>(store);
    vinculoFornecedorProdutoBox = Box<VinculoFornecedorProduto>(store);
    historicoEntradaBox = Box<HistoricoEntrada>(store);
    movimentoEstoqueBox = Box<MovimentoEstoque>(store);
    loteProdutoBox = Box<LoteProduto>(store);
    nfeImportadaRegistroBox = Box<NfeImportadaRegistro>(store);
    kitOrcamentoBox = Box<KitOrcamento>(store);
    kitOrcamentoItemBox = Box<KitOrcamentoItem>(store);
    promocaoBox = Box<Promocao>(store);
    promocaoItemBox = Box<PromocaoItem>(store);
    promocaoComboItemBox = Box<PromocaoComboItem>(store);
    contaPagarBox = Box<ContaPagar>(store);
    tituloReceberBox = Box<TituloReceber>(store);
    recebimentoFiadoBox = Box<RecebimentoFiado>(store);
    reajustePrecoBox = Box<ReajustePreco>(store);
    reajustePrecoItemBox = Box<ReajustePrecoItem>(store);
    auditoriaEventoBox = Box<AuditoriaEvento>(store);
    caixaAuditoriaEventoBox = Box<CaixaAuditoriaEvento>(store);
    itemListaCompraBox = Box<ItemListaCompra>(store);
    produtoSugestaoVendaBox = Box<ProdutoSugestaoVenda>(store);
    sugestaoVendaMetricaEventoBox = Box<SugestaoVendaMetricaEvento>(store);
    recadoLojaBox = Box<RecadoLoja>(store);
    conferenciaCargaRomaneioBox = Box<ConferenciaCargaRomaneio>(store);
    obrigacaoMensalFixaBox = Box<ObrigacaoMensalFixa>(store);
    sessaoInventarioBox = Box<SessaoInventario>(store);
    itemInventarioBox = Box<ItemInventario>(store);
  }

  /// Grava filas assincronas e fecha o banco para copia consistente de `data.mdb`.
  Future<void> fecharParaCopiaDeArquivos() async {
    if (store.isClosed()) return;
    try {
      store.awaitQueueSubmitted();
      store.awaitQueueCompletion();
    } catch (_) {}
    try {
      store.runInTransaction(TxMode.write, () {});
    } catch (_) {}
    if (!store.isClosed()) {
      store.close();
    }
  }

  /// Reabre o banco apos backup manual sem reiniciar o app.
  Future<void> reabrirAposCopiaDeArquivos() async {
    if (!store.isClosed()) return;
    store = await openStore(directory: storeDirectoryPath);
    _inicializarBoxes();
  }

  static Future<ObjectBox> create() async {
    final baseDir = Platform.isWindows
        ? await getApplicationSupportDirectory()
        : await getApplicationDocumentsDirectory();
    final objectBoxDir = Directory(p.join(baseDir.path, 'objectbox'));
    final productImagesDir = Directory(p.join(baseDir.path, 'product_images'));
    final funcionarioImagesDir =
        Directory(p.join(baseDir.path, 'funcionario_images'));
    if (!objectBoxDir.existsSync()) {
      objectBoxDir.createSync(recursive: true);
    }
    if (!productImagesDir.existsSync()) {
      productImagesDir.createSync(recursive: true);
    }
    if (!funcionarioImagesDir.existsSync()) {
      funcionarioImagesDir.createSync(recursive: true);
    }

    final store = await openStore(directory: objectBoxDir.path);
    final instance = ObjectBox._create(store);
    instance.productImagesDir = productImagesDir;
    instance.funcionarioImagesDir = funcionarioImagesDir;
    instance.storeDirectoryPath = objectBoxDir.path;
    return instance;
  }

  /// Abre um ObjectBox temporario (testes de integracao).
  static ObjectBox createForTest(Directory directory) {
    if (!directory.existsSync()) {
      directory.createSync(recursive: true);
    }
    final store = Store(
      getObjectBoxModel(),
      directory: directory.path,
    );
    final instance = ObjectBox._create(store);
    instance.productImagesDir = directory;
    instance.funcionarioImagesDir = directory;
    instance.storeDirectoryPath = directory.path;
    return instance;
  }

  void close() {
    if (!store.isClosed()) {
      store.close();
    }
  }
}
