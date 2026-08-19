import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_vendas/data/sync/sync_entity_codec_extras.dart';
import 'package:sistema_vendas/model/usuario_sistema.dart';

void main() {
  test('fromMap aceita numeros como string', () {
    final u = UsuarioSistema.fromMap({
      'id': 'u1',
      'nome': 'Admin',
      'login': 'admin',
      'senha': 'x',
      'vendedorId': '12',
      'descontoMaximoPercentualPdv': '10,5',
      'admin': true,
    });
    expect(u.vendedorId, 12);
    expect(u.descontoMaximoPercentualPdv, 10.5);
    expect(u.podeGerenciarUsuarios, isTrue);
  });

  test('usuariosDeMap nao quebra com item invalido', () {
    final lista = SyncEntityCodecExtras.usuariosDeMap({
      'usuarios': [
        {
          'id': 'ok',
          'nome': 'Ok',
          'login': 'ok',
          'senha': '',
        },
        'lixo',
        {
          'id': 'ok2',
          'nome': 'Ok2',
          'login': 'ok2',
          'senha': '',
          'vendedorId': '3',
        },
      ],
    });
    expect(lista.map((u) => u.id), ['ok', 'ok2']);
  });
}
