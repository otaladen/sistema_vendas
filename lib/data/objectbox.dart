import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../data/models/conta_pagar.dart';
import '../model/item_venda.dart';
import '../model/linha_devolucao_entrada.dart';
import '../model/linha_troca_saida.dart';
import '../model/registro_devolucao.dart';
import '../model/cliente.dart';
import '../model/fornecedor_nfe.dart';
import '../model/historico_entrada.dart';
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
import '../model/reajuste_preco.dart';
import '../model/reajuste_preco_item.dart';
import '../model/nfe_importada_registro.dart';
import '../model/venda.dart';
import '../model/vendedor.dart';
import '../objectbox.g.dart';

class ObjectBox {
  ObjectBox._create(this.store) {
    produtoBox = Box<Produto>(store);
    clienteBox = Box<Cliente>(store);
    vendaBox = Box<Venda>(store);
    itemVendaBox = Box<ItemVenda>(store);
    registroDevolucaoBox = Box<RegistroDevolucao>(store);
    linhaDevolucaoEntradaBox = Box<LinhaDevolucaoEntrada>(store);
    linhaTrocaSaidaBox = Box<LinhaTrocaSaida>(store);
    historicoEntregaBox = Box<HistoricoEntrega>(store);
    motoristaBox = Box<Motorista>(store);
    vendedorBox = Box<Vendedor>(store);
    funcionarioBox = Box<Funcionario>(store);
    lancamentoFuncionarioBox = Box<LancamentoFuncionario>(store);
    fornecedorNfeBox = Box<FornecedorNfe>(store);
    vinculoFornecedorProdutoBox = Box<VinculoFornecedorProduto>(store);
    historicoEntradaBox = Box<HistoricoEntrada>(store);
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
  }

  late final Store store;
  late final Box<Produto> produtoBox;
  late final Box<Cliente> clienteBox;
  late final Box<Venda> vendaBox;
  late final Box<ItemVenda> itemVendaBox;
  late final Box<RegistroDevolucao> registroDevolucaoBox;
  late final Box<LinhaDevolucaoEntrada> linhaDevolucaoEntradaBox;
  late final Box<LinhaTrocaSaida> linhaTrocaSaidaBox;
  late final Box<HistoricoEntrega> historicoEntregaBox;
  late final Box<Motorista> motoristaBox;
  late final Box<Vendedor> vendedorBox;
  late final Box<Funcionario> funcionarioBox;
  late final Box<LancamentoFuncionario> lancamentoFuncionarioBox;
  late final Box<FornecedorNfe> fornecedorNfeBox;
  late final Box<VinculoFornecedorProduto> vinculoFornecedorProdutoBox;
  late final Box<HistoricoEntrada> historicoEntradaBox;
  late final Box<NfeImportadaRegistro> nfeImportadaRegistroBox;
  late final Box<KitOrcamento> kitOrcamentoBox;
  late final Box<KitOrcamentoItem> kitOrcamentoItemBox;
  late final Box<Promocao> promocaoBox;
  late final Box<PromocaoItem> promocaoItemBox;
  late final Box<PromocaoComboItem> promocaoComboItemBox;
  late final Box<ContaPagar> contaPagarBox;
  late final Box<TituloReceber> tituloReceberBox;
  late final Box<RecebimentoFiado> recebimentoFiadoBox;
  late final Box<ReajustePreco> reajustePrecoBox;
  late final Box<ReajustePrecoItem> reajustePrecoItemBox;
  late final Box<AuditoriaEvento> auditoriaEventoBox;
  late final Directory productImagesDir;
  late final String storeDirectoryPath;

  static Future<ObjectBox> create() async {
    final baseDir = Platform.isWindows
        ? await getApplicationSupportDirectory()
        : await getApplicationDocumentsDirectory();
    final objectBoxDir = Directory(p.join(baseDir.path, 'objectbox'));
    final productImagesDir = Directory(p.join(baseDir.path, 'product_images'));
    if (!objectBoxDir.existsSync()) {
      objectBoxDir.createSync(recursive: true);
    }
    if (!productImagesDir.existsSync()) {
      productImagesDir.createSync(recursive: true);
    }

    final store = await openStore(directory: objectBoxDir.path);
    final instance = ObjectBox._create(store);
    instance.productImagesDir = productImagesDir;
    instance.storeDirectoryPath = objectBoxDir.path;
    return instance;
  }
}
