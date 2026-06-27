import '../model/usuario_sistema.dart';
import 'permissao_usuario.dart';
import 'usuario_permissao_helper.dart';

/// Lancada quando uma operacao sensivel e chamada sem permissao.
class OperacaoNaoAutorizadaException implements Exception {
  OperacaoNaoAutorizadaException(this.mensagem);

  final String mensagem;

  @override
  String toString() => mensagem;
}

/// Validacao de permissoes na camada de dominio (alem da UI).
abstract final class OperacaoPermissaoGuard {
  static void exigir(UsuarioSistema usuario, PermissaoUsuario permissao) {
    if (!UsuarioPermissaoHelper.tem(usuario, permissao)) {
      throw OperacaoNaoAutorizadaException(
        'Usuario "${usuario.login}" sem permissao para esta operacao.',
      );
    }
  }

  static void exigirCancelarVendas(UsuarioSistema usuario) {
    exigir(usuario, PermissaoUsuario.cancelarVendas);
  }

  static bool podeCancelarVendas(UsuarioSistema usuario) {
    return UsuarioPermissaoHelper.tem(usuario, PermissaoUsuario.cancelarVendas);
  }
}
