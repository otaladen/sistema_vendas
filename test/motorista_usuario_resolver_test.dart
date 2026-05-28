import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_vendas/domain/motorista_usuario_resolver.dart';
import 'package:sistema_vendas/model/motorista.dart';
import 'package:sistema_vendas/model/usuario_sistema.dart';

void main() {
  test('nomeMotoristaLogistica usa motoristaEntregaNome do usuario', () {
    const u = UsuarioSistema(
      id: '1',
      nome: 'Joao Silva',
      login: 'joao',
      senha: '',
      motoristaEntregaNome: 'Joao Caminhoneiro',
    );
    final nome = MotoristaUsuarioResolver.nomeMotoristaLogistica(u, const []);
    expect(nome, 'Joao Caminhoneiro');
  });

  test('nomeMotoristaLogistica casa com cadastro de motoristas', () {
    const u = UsuarioSistema(
      id: '1',
      nome: 'Carlos Expedicao',
      login: 'carlos',
      senha: '',
    );
    final nome = MotoristaUsuarioResolver.nomeMotoristaLogistica(
      u,
      [Motorista(nome: 'Carlos Expedicao')],
    );
    expect(nome, 'Carlos Expedicao');
  });
}
