import '../model/usuario_sistema.dart';
import 'perfil_usuario_preset.dart';
import 'usuario_senha_codec.dart';

/// Normaliza usuarios antigos (perfil + hash de senha).
class UsuarioMigracaoService {
  UsuarioMigracaoService._();

  /// Infere perfil e aplica hash se a senha ainda estiver em texto puro.
  static UsuarioSistema normalizarLegado(UsuarioSistema u) {
    var r = u;
    if (!UsuarioSenhaCodec.isHashArmazenado(u.senha) && u.senha.isNotEmpty) {
      r = r.copyWith(senha: UsuarioSenhaCodec.gerarHash(u.senha));
    }
    if (r.perfil == 'customizado' || r.perfil.isEmpty) {
      final sugerido = _inferirPerfil(r);
      if (sugerido != PerfilUsuarioPreset.customizado) {
        r = PerfilUsuarioPresetAplicador.aplicar(r, sugerido).copyWith(
          id: r.id,
          nome: r.nome,
          login: r.login,
          senha: r.senha,
          ativo: r.ativo,
          perfil: sugerido.id,
        );
      }
    }
    return r;
  }

  static PerfilUsuarioPreset _inferirPerfil(UsuarioSistema u) {
    if (u.admin) return PerfilUsuarioPreset.dono;
    if (u.podeReajustePrecoLote && u.podeCancelarVendas) {
      return PerfilUsuarioPreset.gerente;
    }
    if (u.podeGerenciarEntregas && !u.podeAcessarPdv) {
      return PerfilUsuarioPreset.separador;
    }
    if (u.podeVisualizarEntregas &&
        !u.podeGerenciarEntregas &&
        !u.podeAcessarPdv) {
      return PerfilUsuarioPreset.motorista;
    }
    if (u.podeAcessarCaixa && !u.podeAcessarPdv) {
      return PerfilUsuarioPreset.caixa;
    }
    if (u.podeEstoque && !u.podeVendas) {
      return PerfilUsuarioPreset.comprador;
    }
    if (u.podeAcessarPdv) return PerfilUsuarioPreset.vendedor;
    return PerfilUsuarioPreset.customizado;
  }
}
