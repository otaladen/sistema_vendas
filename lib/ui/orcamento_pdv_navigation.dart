import 'package:flutter/material.dart';

import '../data/app_config_repository.dart';
import '../services/print_service.dart';
import '../model/usuario_sistema.dart';
import 'ponto_de_venda_page.dart';

/// Abre o PDV com um orcamento pendente carregado para edicao.
///
/// Repositorios sao [dynamic] para aceitar ObjectBox (servidor) ou API (terminal).
Future<void> abrirPdvComOrcamento(
  BuildContext context, {
  required int orcamentoId,
  required dynamic produtoRepository,
  required dynamic clienteRepository,
  required dynamic vendaRepository,
  required dynamic vendedorRepository,
  required AppConfigRepository appConfigRepository,
  required PrintService printService,
  required UsuarioSistema usuarioLogado,
}) {
  return Navigator.push<void>(
    context,
    MaterialPageRoute(
      builder: (_) => PontoDeVendaPage(
        produtoRepository: produtoRepository,
        clienteRepository: clienteRepository,
        vendaRepository: vendaRepository,
        vendedorRepository: vendedorRepository,
        appConfigRepository: appConfigRepository,
        printService: printService,
        usuarioLogado: usuarioLogado,
        orcamentoIdInicial: orcamentoId,
      ),
    ),
  );
}
