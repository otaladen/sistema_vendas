import 'package:flutter/material.dart';

import '../../data/cliente_repository.dart';
import '../../data/objectbox.dart';
import '../../data/venda_repository.dart';
import '../../domain/filtro_contas_receber.dart';
import '../../domain/permissao_usuario.dart';
import '../../domain/usuario_permissao_helper.dart';
import '../../model/usuario_sistema.dart';
import '../layout/app_layout.dart';
import '../widgets/hub_nav_button.dart';
import 'contas_pagar_page.dart';
import 'contas_receber_page.dart';

const Color _corReceber = Color(0xFF1565C0);
const Color _corPagar = Color(0xFF455A64);

/// Hub do modulo Financeiro.
class FinanceiroHubPage extends StatelessWidget {
  const FinanceiroHubPage({
    super.key,
    required this.objectBox,
    required this.vendaRepository,
    required this.clienteRepository,
    required this.usuarioLogado,
    this.filtroContasReceberInicial,
  });

  final ObjectBox objectBox;
  final VendaRepository vendaRepository;
  final ClienteRepository clienteRepository;
  final UsuarioSistema usuarioLogado;
  final FiltroContasReceber? filtroContasReceberInicial;

  @override
  Widget build(BuildContext context) {
    final podeFinanceiro =
        UsuarioPermissaoHelper.tem(usuarioLogado, PermissaoUsuario.financeiro);
    final podeCaixa =
        UsuarioPermissaoHelper.tem(usuarioLogado, PermissaoUsuario.acessarCaixa);

    if (filtroContasReceberInicial != null && podeFinanceiro) {
      return ContasReceberPage(
        vendaRepository: vendaRepository,
        clienteRepository: clienteRepository,
        usuarioLogado: usuarioLogado,
        podeRegistrarRecebimento: podeCaixa,
        filtroInicial: filtroContasReceberInicial!,
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Financeiro')),
      body: AdaptiveHubBody(
        children: [
          HubNavButton(
            icon: Icons.call_received_outlined,
            corDestaque: _corReceber,
            titulo: 'Contas a receber',
            subtitulo: 'Fiado, vencidos e recebimentos',
            habilitado: podeFinanceiro,
            onTap: () {
              if (!podeFinanceiro) return;
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ContasReceberPage(
                    vendaRepository: vendaRepository,
                    clienteRepository: clienteRepository,
                    usuarioLogado: usuarioLogado,
                    podeRegistrarRecebimento: podeCaixa,
                  ),
                ),
              );
            },
          ),
          HubNavButton(
            icon: Icons.call_made_outlined,
            corDestaque: _corPagar,
            titulo: 'Contas a pagar',
            subtitulo: 'Fornecedores e vencimentos',
            habilitado: podeFinanceiro,
            onTap: () {
              if (!podeFinanceiro) return;
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ContasPagarPage(objectBox: objectBox),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
