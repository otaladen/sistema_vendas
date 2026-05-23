import '../../domain/perfil_usuario_preset.dart';
import '../../domain/permissao_usuario.dart';
import '../../domain/usuario_permissao_helper.dart';
import '../../model/usuario_sistema.dart';

/// Estado editavel do formulario de usuario (dados + permissoes).
class UsuarioFormState {
  UsuarioFormState.novo()
      : editandoId = null,
        _usuario = UsuarioSistema(
          id: '',
          nome: '',
          login: '',
          senha: '',
        );

  UsuarioFormState.de(UsuarioSistema u) : editandoId = u.id, _usuario = u;

  String? editandoId;
  UsuarioSistema _usuario;
  PerfilUsuarioPreset _perfilSelecionado = PerfilUsuarioPreset.customizado;

  String get nome => _usuario.nome;
  String get login => _usuario.login;
  String get senha => _usuario.senha;
  bool get ativo => _usuario.ativo;
  bool get admin => _usuario.admin;
  UsuarioSistema get usuario => _usuario;
  PerfilUsuarioPreset get perfilSelecionado => _perfilSelecionado;

  bool get permissoesTravadas => _usuario.admin;

  void definirNome(String v) => _usuario = _usuario.copyWith(nome: v);
  void definirLogin(String v) => _usuario = _usuario.copyWith(login: v);
  void definirSenha(String v) => _usuario = _usuario.copyWith(senha: v);
  void definirAtivo(bool v) => _usuario = _usuario.copyWith(ativo: v);

  /// Texto do teto de desconto; vazio = usar configuracao da empresa.
  String get descontoMaximoTexto {
    final v = _usuario.descontoMaximoPercentualPdv;
    if (v == null) return '';
    return v == v.roundToDouble() ? v.toInt().toString() : v.toString();
  }

  void definirDescontoMaximoTexto(String texto) {
    _perfilSelecionado = PerfilUsuarioPreset.customizado;
    final t = texto.trim().replaceAll(',', '.');
    if (t.isEmpty) {
      _usuario = _usuario.copyWith(limparDescontoMaximoPdv: true);
      return;
    }
    final v = double.tryParse(t);
    if (v == null || v < 0) return;
    _usuario = _usuario.copyWith(descontoMaximoPercentualPdv: v);
  }

  void definirAdmin(bool v) {
    _usuario = UsuarioPermissaoHelper.aplicarAdmin(_usuario, v);
    if (v) {
      _perfilSelecionado = PerfilUsuarioPreset.dono;
    }
  }

  void aplicarPerfil(PerfilUsuarioPreset perfil) {
    _perfilSelecionado = perfil;
    if (perfil == PerfilUsuarioPreset.customizado) return;
    _usuario = PerfilUsuarioPresetAplicador.aplicar(_usuario, perfil);
    if (perfil == PerfilUsuarioPreset.dono) {
      _usuario = _usuario.copyWith(admin: true);
    } else {
      _usuario = _usuario.copyWith(admin: false);
    }
  }

  void definirPermissao(PermissaoUsuario p, bool valor) {
    _perfilSelecionado = PerfilUsuarioPreset.customizado;
    _usuario = UsuarioPermissaoHelper.comPermissao(_usuario, p, valor);
    if (p == PermissaoUsuario.acessarPdv && valor) {
      _usuario = _usuario.copyWith(podeVendas: true);
    }
    if (p == PermissaoUsuario.acessarCaixa && valor) {
      _usuario = _usuario.copyWith(podeVendas: true);
    }
    if (p == PermissaoUsuario.acessarListagemVendas && valor) {
      _usuario = _usuario.copyWith(podeVendas: true);
    }
    if ((p == PermissaoUsuario.leituraParcialCaixa ||
            p == PermissaoUsuario.visualizarAuditoriaCaixa ||
            p == PermissaoUsuario.manutencaoAuditoriaCaixa) &&
        valor) {
      _usuario = _usuario.copyWith(
        podeVendas: true,
        podeAcessarCaixa: true,
        podeCaixa: true,
      );
    }
    if (p == PermissaoUsuario.gerenciarEntregas && valor) {
      _usuario = _usuario.copyWith(podeVisualizarEntregas: true);
    }
  }

  bool lerPermissao(PermissaoUsuario p) =>
      UsuarioPermissaoHelper.lerFlag(_usuario, p);

  UsuarioSistema montarParaSalvar(String id) {
    return _usuario.copyWith(
      id: id,
      nome: _usuario.nome.trim(),
      login: _usuario.login.trim(),
      senha: _usuario.senha,
      perfil: _perfilSelecionado.id,
    );
  }

  void carregar(UsuarioSistema u) {
    editandoId = u.id;
    _usuario = u;
    _perfilSelecionado = perfilUsuarioFromId(u.perfil);
    if (u.admin && _perfilSelecionado == PerfilUsuarioPreset.customizado) {
      _perfilSelecionado = PerfilUsuarioPreset.dono;
    }
  }

  void limpar() {
    editandoId = null;
    _usuario = UsuarioSistema(
      id: '',
      nome: '',
      login: '',
      senha: '',
    );
    _perfilSelecionado = PerfilUsuarioPreset.customizado;
  }
}
