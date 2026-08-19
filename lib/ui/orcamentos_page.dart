import 'package:flutter/material.dart';

import '../data/app_config_repository.dart';
import '../domain/permissao_usuario.dart';
import '../domain/usuario_permissao_helper.dart';
import '../model/usuario_sistema.dart';
import '../model/venda.dart';
import '../services/print_service.dart';
import 'orcamento_pdv_navigation.dart';
import 'relatorios/relatorio_orcamentos_abertos_page.dart';

/// Orcamentos salvos no PDV que ainda nao foram pagos no caixa.
class OrcamentosPage extends StatelessWidget {
  const OrcamentosPage({
    super.key,
    required this.vendaRepository,
    required this.clienteRepository,
    required this.produtoRepository,
    required this.vendedorRepository,
    required this.appConfigRepository,
    required this.printService,
    required this.usuarioLogado,
  });

  final dynamic vendaRepository;
  final dynamic clienteRepository;
  final dynamic produtoRepository;
  final dynamic vendedorRepository;
  final AppConfigRepository appConfigRepository;
  final PrintService printService;
  final UsuarioSistema usuarioLogado;

  bool get _podeEditarNoPdv =>
      UsuarioPermissaoHelper.tem(usuarioLogado, PermissaoUsuario.acessarPdv);

  /// Mesma permissao de cancelar venda: apaga orcamento pendente.
  bool get _podeApagar =>
      UsuarioPermissaoHelper.podeCancelarVendas(usuarioLogado);

  Future<void> _editarNoPdv(BuildContext context, Venda venda) {
    return abrirPdvComOrcamento(
      context,
      orcamentoId: venda.id,
      produtoRepository: produtoRepository,
      clienteRepository: clienteRepository,
      vendaRepository: vendaRepository,
      vendedorRepository: vendedorRepository,
      appConfigRepository: appConfigRepository,
      printService: printService,
      usuarioLogado: usuarioLogado,
    );
  }

  @override
  Widget build(BuildContext context) {
    return RelatorioOrcamentosAbertosPage(
      vendaRepository: vendaRepository,
      clienteRepository: clienteRepository,
      tituloAppBar: 'Orcamentos',
      textoResumo:
          'Salvos no PDV e aguardando pagamento no caixa — ainda nao viraram venda.',
      exibirExportacoesRelatorio: false,
      podeEditarNoPdv: _podeEditarNoPdv,
      onEditarNoPdv: _podeEditarNoPdv ? _editarNoPdv : null,
      podeApagarOrcamentos: _podeApagar,
      usuarioExecutor: _podeApagar ? usuarioLogado : null,
    );
  }
}
