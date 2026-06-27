import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_vendas/domain/perfil_usuario_preset.dart';
import 'package:sistema_vendas/domain/recado_loja_constantes.dart';
import 'package:sistema_vendas/domain/recado_loja_helper.dart';
import 'package:sistema_vendas/model/recado_loja.dart';
import 'package:sistema_vendas/model/usuario_sistema.dart';

void main() {
  final caixa = UsuarioSistema(
    id: '1',
    login: 'caixa1',
    nome: 'Caixa Um',
    senha: 'x',
    perfil: PerfilUsuarioPreset.caixa.id,
  );

  final vendedor = UsuarioSistema(
    id: '2',
    login: 'vend1',
    nome: 'Vendedor',
    senha: 'x',
    perfil: PerfilUsuarioPreset.vendedor.id,
  );

  RecadoLoja recadoPerfilCaixa() => RecadoLoja(
        texto: 'Teste',
        destinoTipo: RecadoLojaDestino.perfil,
        destinoPerfil: PerfilUsuarioPreset.caixa.id,
      );

  test('aplica para todos', () {
    final r = RecadoLoja(
      texto: 'Geral',
      destinoTipo: RecadoLojaDestino.todos,
    );
    expect(RecadoLojaHelper.aplicaParaUsuario(r, vendedor), isTrue);
    expect(RecadoLojaHelper.aplicaParaUsuario(r, caixa), isTrue);
  });

  test('aplica somente ao perfil destino', () {
    final r = recadoPerfilCaixa();
    expect(RecadoLojaHelper.aplicaParaUsuario(r, caixa), isTrue);
    expect(RecadoLojaHelper.aplicaParaUsuario(r, vendedor), isFalse);
  });

  test('gerente ve recados de qualquer perfil', () {
    final gerente = caixa.copyWith(
      login: 'ger',
      perfil: PerfilUsuarioPreset.gerente.id,
    );
    final r = recadoPerfilCaixa();
    expect(RecadoLojaHelper.aplicaParaUsuario(r, gerente), isTrue);
  });

  test('marcar lido e mesclar leituras', () {
    final r = RecadoLoja(texto: 'A');
    expect(RecadoLojaHelper.foiLido(r, 'caixa1'), isFalse);

    final json = RecadoLojaHelper.serializarLeituras(['caixa1']);
    r.leiturasJson = json;
    expect(RecadoLojaHelper.foiLido(r, 'caixa1'), isTrue);

    final merged = RecadoLojaHelper.mesclarLeiturasJson(
      '["a"]',
      '["b","a"]',
    );
    expect(RecadoLojaHelper.parseLeituras(merged), ['a', 'b']);
  });

  test('manutencao apenas gerente dono ou admin', () {
    final admin = caixa.copyWith(admin: true);
    final gerente = caixa.copyWith(
      login: 'ger',
      perfil: PerfilUsuarioPreset.gerente.id,
    );
    expect(RecadoLojaHelper.podeManutencao(caixa), isFalse);
    expect(RecadoLojaHelper.podeManutencao(vendedor), isFalse);
    expect(RecadoLojaHelper.podeManutencao(gerente), isTrue);
    expect(RecadoLojaHelper.podeManutencao(admin), isTrue);
  });
}
