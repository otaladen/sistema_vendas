import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../model/item_venda.dart';
import '../model/cliente.dart';
import '../model/produto.dart';
import '../model/venda.dart';
import '../objectbox.g.dart';

class ObjectBox {
  ObjectBox._create(this.store) {
    produtoBox = Box<Produto>(store);
    clienteBox = Box<Cliente>(store);
    vendaBox = Box<Venda>(store);
    itemVendaBox = Box<ItemVenda>(store);
  }

  late final Store store;
  late final Box<Produto> produtoBox;
  late final Box<Cliente> clienteBox;
  late final Box<Venda> vendaBox;
  late final Box<ItemVenda> itemVendaBox;
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

    final store = await openStore(
      directory: objectBoxDir.path,
    );
    final instance = ObjectBox._create(store);
    instance.productImagesDir = productImagesDir;
    return instance;
  }
}
