import '../model/usuario_sistema.dart';
import 'perfil_usuario_preset.dart';
import 'permissao_usuario.dart';
import 'usuario_permissao_helper.dart';

/// Textos legiveis do que o usuario pode ou nao fazer no ERP.
class UsuarioResumoPermissoes {
  UsuarioResumoPermissoes._();

  static ({List<String> pode, List<String> naoPode}) gerar(UsuarioSistema u) {
    if (u.admin) {
      return (
        pode: const ['Acesso total a todos os modulos e funcoes do sistema'],
        naoPode: const [],
      );
    }

    final pode = <String>[];
    final naoPode = <String>[];

    void add(bool cond, String rotulo) {
      (cond ? pode : naoPode).add(rotulo);
    }

    final perfil = perfilUsuarioFromId(u.perfil);
    if (perfil != PerfilUsuarioPreset.customizado) {
      pode.add('Perfil: ${perfil.rotulo}');
    }

    add(UsuarioPermissaoHelper.tem(u, PermissaoUsuario.acessarPdv), 'Ponto de venda (PDV)');
    add(UsuarioPermissaoHelper.tem(u, PermissaoUsuario.acessarCaixa), 'Caixa');
    add(
      UsuarioPermissaoHelper.podeVisualizarEntregas(u),
      'Ver entregas / romaneio',
    );
    add(
      UsuarioPermissaoHelper.podeGerenciarEntregas(u),
      'Alterar status e montagem de entregas',
    );
    add(UsuarioPermissaoHelper.tem(u, PermissaoUsuario.cadastros), 'Cadastros gerais');
    add(UsuarioPermissaoHelper.tem(u, PermissaoUsuario.estoque), 'Estoque e NF');
    add(UsuarioPermissaoHelper.tem(u, PermissaoUsuario.financeiro), 'Financeiro');
    add(UsuarioPermissaoHelper.tem(u, PermissaoUsuario.acessarRelatorios), 'Relatorios');
    add(UsuarioPermissaoHelper.podeCancelarVendas(u), 'Cancelar vendas e devolucoes');
    add(UsuarioPermissaoHelper.podeReajustePrecoLote(u), 'Reajuste de precos em lote');
    add(UsuarioPermissaoHelper.tem(u, PermissaoUsuario.venderFiado), 'Vender a prazo (fiado)');
    add(
      UsuarioPermissaoHelper.tem(u, PermissaoUsuario.alterarPrecoPdv),
      'Desconto manual no PDV (sem limite de teto)',
    );
    if (UsuarioPermissaoHelper.tem(u, PermissaoUsuario.acessarPdv)) {
      if (u.descontoMaximoPercentualPdv != null) {
        pode.add(
          'Teto de desconto no PDV: ${u.descontoMaximoPercentualPdv!.toStringAsFixed(1)}%',
        );
      } else if (!UsuarioPermissaoHelper.tem(u, PermissaoUsuario.alterarPrecoPdv)) {
        pode.add('Teto de desconto no PDV: padrao da empresa');
      }
    }

    if (pode.isEmpty) {
      pode.add('Acesso minimo — revise as permissoes');
    }

    return (pode: pode, naoPode: naoPode);
  }
}
