import 'package:flutter/material.dart';

import '../domain/troca_com_nota_pdv_intent.dart';
import '../model/usuario_sistema.dart';
import '../services/configuracoes_service.dart';
import '../data/cliente_repository.dart';
import '../data/produto_repository.dart';
import '../data/venda_repository.dart';
import '../data/vendedor_repository.dart';
import '../services/print_service.dart';
import 'ponto_de_venda_page.dart';

/// Abre o PDV com cliente e credito de devolucao sugeridos (troca com nota).
Future<void> abrirPdvTrocaComNota(
  BuildContext context, {
  required TrocaComNotaPdvIntent intent,
  required ProdutoRepository produtoRepository,
  required ClienteRepository clienteRepository,
  required VendaRepository vendaRepository,
  required VendedorRepository vendedorRepository,
  required ConfiguracoesService configuracoesService,
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
        configuracoesService: configuracoesService,
        printService: printService,
        usuarioLogado: usuarioLogado,
        intentTrocaComNota: intent,
      ),
    ),
  );
}
