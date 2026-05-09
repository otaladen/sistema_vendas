import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../model/item_venda.dart';
import '../model/linha_devolucao_entrada.dart';
import '../model/linha_troca_saida.dart';
import '../model/registro_devolucao.dart';
import '../model/cliente.dart';
import '../model/funcionario.dart';
import '../model/historico_entrega.dart';
import '../model/motorista.dart';
import '../model/produto.dart';
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
  late final Directory productImagesDir;

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
    return instance;
  }
}
