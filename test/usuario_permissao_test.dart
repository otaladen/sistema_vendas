import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_vendas/domain/perfil_usuario_preset.dart';
import 'package:sistema_vendas/domain/permissao_usuario.dart';
import 'package:sistema_vendas/domain/usuario_permissao_helper.dart';
import 'package:sistema_vendas/domain/usuario_senha_codec.dart';
import 'package:sistema_vendas/model/usuario_sistema.dart';

void main() {
  test('vendedor: PDV sem cancelar, fiado nem reajuste', () {
    final u = PerfilUsuarioPresetAplicador.aplicar(
      UsuarioSistema(id: '1', nome: 'V', login: 'v', senha: 'x'),
      PerfilUsuarioPreset.vendedor,
    );
    expect(UsuarioPermissaoHelper.tem(u, PermissaoUsuario.acessarPdv), isTrue);
    expect(UsuarioPermissaoHelper.podeCancelarVendas(u), isFalse);
    expect(UsuarioPermissaoHelper.tem(u, PermissaoUsuario.venderFiado), isFalse);
    expect(UsuarioPermissaoHelper.podeReajustePrecoLote(u), isFalse);
    expect(u.descontoMaximoPercentualPdv, 8);
  });

  test('motorista: so visualiza entregas', () {
    final u = PerfilUsuarioPresetAplicador.aplicar(
      UsuarioSistema(id: '2', nome: 'M', login: 'm', senha: 'x'),
      PerfilUsuarioPreset.motorista,
    );
    expect(UsuarioPermissaoHelper.podeVisualizarEntregas(u), isTrue);
    expect(UsuarioPermissaoHelper.podeGerenciarEntregas(u), isFalse);
    expect(UsuarioPermissaoHelper.tem(u, PermissaoUsuario.acessarPdv), isFalse);
  });

  test('gerente: reajuste e cancelar', () {
    final u = PerfilUsuarioPresetAplicador.aplicar(
      UsuarioSistema(id: '3', nome: 'G', login: 'g', senha: 'x'),
      PerfilUsuarioPreset.gerente,
    );
    expect(UsuarioPermissaoHelper.podeReajustePrecoLote(u), isTrue);
    expect(UsuarioPermissaoHelper.podeCancelarVendas(u), isTrue);
    expect(UsuarioPermissaoHelper.tem(u, PermissaoUsuario.venderFiado), isTrue);
  });

  test('senha hash verifica e rejeita errada', () {
    final hash = UsuarioSenhaCodec.gerarHash('1234');
    expect(UsuarioSenhaCodec.verificar('1234', hash), isTrue);
    expect(UsuarioSenhaCodec.verificar('0000', hash), isFalse);
    expect(UsuarioSenhaCodec.isHashArmazenado(hash), isTrue);
  });
}
