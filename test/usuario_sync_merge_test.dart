import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_vendas/data/sync/sync_entity_codec_extras.dart';
import 'package:sistema_vendas/model/usuario_sistema.dart';

void main() {
  test('mesclar usuarios preserva hash local e nao envia senha no sync', () {
    final local = UsuarioSistema(
      id: '1',
      nome: 'Admin',
      login: 'admin',
      senha: 'hash_local_secreto',
      admin: true,
    );
    final remoto = UsuarioSistema(
      id: '1',
      nome: 'Admin atualizado',
      login: 'admin',
      senha: '',
      admin: true,
    );

    final mesclados = SyncEntityCodecExtras.mesclarUsuariosAposSync(
      locais: [local],
      remotos: [remoto],
    );

    expect(mesclados, hasLength(1));
    expect(mesclados.first.nome, 'Admin atualizado');
    expect(mesclados.first.senha, 'hash_local_secreto');

    final payload = SyncEntityCodecExtras.usuariosParaMap([local]);
    final users = payload['usuarios'] as List;
    expect(users.first['senha'], isNull);
    expect(users.first['senhaConfigurada'], isTrue);
  });
}
