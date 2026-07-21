import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_vendas/data/app_config_repository.dart';
import 'package:sistema_vendas/data/sync/sync_entity_codec_extras.dart';

void main() {
  test('empresa_config nao envia pasta do segundo destino (S7)', () {
    const cfg = EmpresaConfig(
      nomeLoja: 'Loja Teste',
      backupSegundoDestinoAtivo: true,
      backupSegundoDestinoPasta: r'D:\BackupRede\PC-Caixa',
      redeServidorUrl: 'http://192.168.1.10:8787',
      redeSyncToken: 'token-secreto',
      impressoraPadrao: 'EPSON TM',
    );

    final map = SyncEntityCodecExtras.empresaConfigParaMap(cfg);

    expect(map.containsKey('backupSegundoDestinoPasta'), isFalse);
    expect(map.containsKey('redeServidorUrl'), isFalse);
    expect(map.containsKey('redeSyncToken'), isFalse);
    expect(map.containsKey('impressoraPadrao'), isFalse);
    expect(map['backupSegundoDestinoAtivo'], isTrue);
    expect(map['nomeLoja'], 'Loja Teste');
  });

  test('pull de empresa_config preserva pasta local do segundo destino', () {
    const local = EmpresaConfig(
      nomeLoja: 'Antiga',
      backupSegundoDestinoPasta: r'C:\BackupLocal',
      redeServidorUrl: 'http://192.168.1.10:8787',
    );
    final remoto = {
      'nomeLoja': 'Nova Loja',
      'backupSegundoDestinoAtivo': true,
      'backupSegundoDestinoPasta': r'\\servidor\outra_pasta',
      'redeServidorUrl': 'http://hacker:8787',
    };

    final merged = SyncEntityCodecExtras.empresaConfigDeMap(local, remoto);

    expect(merged.nomeLoja, 'Nova Loja');
    expect(merged.backupSegundoDestinoAtivo, isTrue);
    expect(merged.backupSegundoDestinoPasta, r'C:\BackupLocal');
    expect(merged.redeServidorUrl, 'http://192.168.1.10:8787');
  });
}
