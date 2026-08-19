import 'package:flutter/material.dart';

import '../../data/app_config_repository.dart';
import '../../data/api/lan_api_client.dart';
import '../../data/api/venda_api_repository.dart';
import '../../data/objectbox.dart';
import '../../data/sync/lan_sync_scheduler.dart';
import '../../data/usuario_repository.dart';
import '../../model/usuario_sistema.dart';
import '../../services/print_service.dart';

/// Dependencias compartilhadas do menu / shell.
class MainMenuDeps extends InheritedWidget {
  const MainMenuDeps({
    super.key,
    required this.objectBox,
    this.terminalLeve = false,
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
    this.usuarioRepository,
    this.vendaApiRepository,
    this.lanApiClient,
    this.contaPagarRepository,
    this.kitOrcamentoRepository,
    this.promocaoRepository,
    this.listaCompraRepository,
    this.nfeImportadaRepository,
    this.recadoLojaRepository,
    this.fornecedorRepository,
    required super.child,
  });

  final ObjectBox? objectBox;
  final bool terminalLeve;
  final dynamic produtoRepository;
  final dynamic clienteRepository;
  final dynamic vendaRepository;
  final dynamic vendedorRepository;
  final dynamic funcionarioRepository;
  final dynamic motoristaRepository;
  final UsuarioSistema usuarioLogado;
  final VoidCallback onLogout;
  final LanSyncScheduler? lanSyncScheduler;
  final AppConfigRepository appConfigRepository;
  final PrintService printService;
  /// [UsuarioRepository] (PC1) ou [UsuarioApiRepository] (terminal).
  final dynamic usuarioRepository;
  final VendaApiRepository? vendaApiRepository;
  final LanApiClient? lanApiClient;
  final dynamic contaPagarRepository;
  final dynamic kitOrcamentoRepository;
  final dynamic promocaoRepository;
  final dynamic listaCompraRepository;
  /// [NfeImportadaApiRepository] no Terminal Leve; null no PC1 (usa ObjectBox).
  final dynamic nfeImportadaRepository;
  /// [RecadoLojaApiRepository] no Terminal Leve; null no PC1 (usa ObjectBox).
  final dynamic recadoLojaRepository;
  /// [FornecedorRepository] (PC1) ou [FornecedorApiRepository] (terminal).
  final dynamic fornecedorRepository;

  static MainMenuDeps? maybeOf(BuildContext context) {
    return context
            .getElementForInheritedWidgetOfExactType<MainMenuDeps>()
            ?.widget
        as MainMenuDeps?;
  }

  static MainMenuDeps of(BuildContext context) {
    final scope = maybeOf(context);
    assert(scope != null, 'MainMenuDeps nao encontrado na arvore');
    return scope!;
  }

  /// Usuarios: no terminal leve so via API (sem SharedPreferences local).
  static dynamic resolverUsuarioRepository(BuildContext context) {
    final deps = maybeOf(context);
    if (deps?.usuarioRepository != null) return deps!.usuarioRepository;
    if (deps?.terminalLeve == true) {
      throw StateError(
        'Usuarios so via API no terminal leve. Reconecte ao PC servidor.',
      );
    }
    return UsuarioRepository();
  }

  /// Mesmo criterio para uso fora de BuildContext (ex.: sub-router).
  dynamic usuarioRepositoryEfetivo() {
    if (usuarioRepository != null) return usuarioRepository!;
    if (terminalLeve) {
      throw StateError(
        'Usuarios so via API no terminal leve. Reconecte ao PC servidor.',
      );
    }
    return UsuarioRepository();
  }

  /// Reconstroi o InheritedWidget com outro [child] (push mobile).
  MainMenuDeps wrap(Widget child) => MainMenuDeps(
    objectBox: objectBox,
    terminalLeve: terminalLeve,
    produtoRepository: produtoRepository,
    clienteRepository: clienteRepository,
    vendaRepository: vendaRepository,
    vendedorRepository: vendedorRepository,
    funcionarioRepository: funcionarioRepository,
    motoristaRepository: motoristaRepository,
    usuarioLogado: usuarioLogado,
    onLogout: onLogout,
    lanSyncScheduler: lanSyncScheduler,
    appConfigRepository: appConfigRepository,
    printService: printService,
    usuarioRepository: usuarioRepository,
    vendaApiRepository: vendaApiRepository,
    lanApiClient: lanApiClient,
    contaPagarRepository: contaPagarRepository,
    kitOrcamentoRepository: kitOrcamentoRepository,
    promocaoRepository: promocaoRepository,
    listaCompraRepository: listaCompraRepository,
    nfeImportadaRepository: nfeImportadaRepository,
    recadoLojaRepository: recadoLojaRepository,
    fornecedorRepository: fornecedorRepository,
    child: child,
  );

  @override
  bool updateShouldNotify(MainMenuDeps oldWidget) =>
      oldWidget.terminalLeve != terminalLeve;
}
