import 'package:flutter/material.dart';

import '../data/app_config_repository.dart';
import '../data/cliente_repository.dart';
import '../data/produto_repository.dart';
import '../data/venda_repository.dart';
import '../data/vendedor_repository.dart';
import '../model/usuario_sistema.dart';
import '../services/print_service.dart';
import 'ponto_de_venda_page.dart';

/// Abre o PDV com um orcamento pendente carregado para edicao.
Future<void> abrirPdvComOrcamento(
  BuildContext context, {
  required int orcamentoId,
  required ProdutoRepository produtoRepository,
  required ClienteRepository clienteRepository,
  required VendaRepository vendaRepository,
  required VendedorRepository vendedorRepository,
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
