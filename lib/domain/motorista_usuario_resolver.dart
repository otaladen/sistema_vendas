import '../model/motorista.dart';
import '../model/usuario_sistema.dart';

/// Vincula [UsuarioSistema] ao nome em [Venda.motoristaEntrega].
abstract final class MotoristaUsuarioResolver {
  MotoristaUsuarioResolver._();

  static String nomeMotoristaLogistica(
    UsuarioSistema usuario,
    List<Motorista> motoristasCadastro,
  ) {
    final vinculo = usuario.motoristaEntregaNome.trim();
    if (vinculo.isNotEmpty) return vinculo;

    final nomeUsuario = usuario.nome.trim();
    if (nomeUsuario.isNotEmpty) {
      for (final m in motoristasCadastro) {
        if (m.nome.trim().toLowerCase() == nomeUsuario.toLowerCase()) {
          return m.nome.trim();
        }
      }
      return nomeUsuario;
    }
    return usuario.login.trim();
  }

  static bool entregaEhDoMotorista(
    String motoristaEntregaVenda,
    String nomeMotoristaUsuario,
  ) {
    final a = motoristaEntregaVenda.trim().toLowerCase();
    final b = nomeMotoristaUsuario.trim().toLowerCase();
    if (a.isEmpty || b.isEmpty) return false;
    return a == b;
  }
}
