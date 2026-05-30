import 'package:flutter/material.dart';

import '../../data/app_config_repository.dart';
import '../../data/cliente_repository.dart';
import '../../data/funcionario_repository.dart';
import '../../data/motorista_repository.dart';
import '../../data/objectbox.dart';
import '../../data/produto_repository.dart';
import '../../data/sync/lan_sync_scheduler.dart';
import '../../data/venda_repository.dart';
import '../../data/vendedor_repository.dart';
import '../../model/usuario_sistema.dart';
import '../../services/print_service.dart';

/// Dependencias compartilhadas do menu / shell.
class MainMenuDeps extends InheritedWidget {
  const MainMenuDeps({
    super.key,
    required this.objectBox,
    required this.produtoRepository,
    required this.clienteRepository,
    required this.vendaRepository,
    required this.vendedorRepository,
    required this.funcionarioRepository,
    required this.motoristaRepository,
    required this.usuarioLogado,
    required this.onLogout,
    required this.lanSyncScheduler,
    required this.appConfigRepository,
    required this.printService,
    required super.child,
  });

  final ObjectBox objectBox;
  final ProdutoRepository produtoRepository;
  final ClienteRepository clienteRepository;
  final VendaRepository vendaRepository;
  final VendedorRepository vendedorRepository;
  final FuncionarioRepository funcionarioRepository;
  final MotoristaRepository motoristaRepository;
  final UsuarioSistema usuarioLogado;
  final VoidCallback onLogout;
  final LanSyncScheduler lanSyncScheduler;
  final AppConfigRepository appConfigRepository;
  final PrintService printService;

  static MainMenuDeps? maybeOf(BuildContext context) {
    return context
        .getElementForInheritedWidgetOfExactType<MainMenuDeps>()
        ?.widget as MainMenuDeps?;
  }

  static MainMenuDeps of(BuildContext context) {
    final scope = maybeOf(context);
    assert(scope != null, 'MainMenuDeps nao encontrado na arvore');
    return scope!;
  }

  @override
  bool updateShouldNotify(MainMenuDeps oldWidget) => false;
}
