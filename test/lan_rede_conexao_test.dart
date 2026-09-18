import 'package:flutter_test/flutter_test.dart';

import 'package:sistema_vendas/data/api/lan_api_url.dart';
import 'package:sistema_vendas/data/api/lan_conexao_qr.dart';
import 'package:sistema_vendas/services/lan_rede_helper.dart';

void main() {
  test('URL da API sempre usa dois pontos entre IP e porta', () {
    expect(
      LanApiUrl.fromSyncUrl('192.168.1.69'),
      'http://192.168.1.69:8788',
    );
    expect(
      LanApiUrl.fromSyncUrl('http://192.168.1.69'),
      'http://192.168.1.69:8788',
    );
    expect(
      LanRedeHelper.montarUrlServidor('192.168.1.69'),
      'http://192.168.1.69:8788',
    );
    expect(
      LanRedeHelper.montarUrlServidor('192.168.1.69:8788'),
      'http://192.168.1.69:8788',
    );
    expect(LanApiUrl.fromSyncUrl('192.168.1.69').contains('698788'), isFalse);
    expect(LanApiUrl.fromSyncUrl('192.168.1.69').contains(':8788'), isTrue);
  });

  test('classifica Ethernet, Wi-Fi e Tailscale pelo nome/IP', () {
    expect(
      LanRedeHelper.classificarInterface(
        nomeInterface: 'Ethernet',
        ip: '192.168.1.69',
      ),
      LanInterfaceTipo.ethernet,
    );
    expect(
      LanRedeHelper.classificarInterface(
        nomeInterface: 'Wi-Fi',
        ip: '192.168.1.80',
      ),
      LanInterfaceTipo.wifi,
    );
    expect(
      LanRedeHelper.classificarInterface(
        nomeInterface: 'Tailscale',
        ip: '100.64.1.2',
      ),
      LanInterfaceTipo.tailscale,
    );
    expect(LanRedeHelper.deveIgnorarInterface('vEthernet (Default Switch)'), isTrue);
    expect(LanRedeHelper.deveIgnorarInterface('Ethernet'), isFalse);
  });

  test('recomendado para PCs e QR do celular respeitam o tipo', () {
    const ethernet = LanEnderecoLocal(
      nomeInterface: 'Ethernet',
      ip: '192.168.1.69',
      tipo: LanInterfaceTipo.ethernet,
      url: 'http://192.168.1.69:8788',
      recomendadoPcs: true,
    );
    const wifi = LanEnderecoLocal(
      nomeInterface: 'Wi-Fi',
      ip: '192.168.1.80',
      tipo: LanInterfaceTipo.wifi,
      url: 'http://192.168.1.80:8788',
    );
    const tail = LanEnderecoLocal(
      nomeInterface: 'Tailscale',
      ip: '100.64.1.2',
      tipo: LanInterfaceTipo.tailscale,
      url: 'http://100.64.1.2:8788',
    );
    expect(
      LanRedeHelper.enderecoRecomendadoPcs([wifi, ethernet, tail])?.ip,
      '192.168.1.69',
    );
    expect(
      LanRedeHelper.enderecosParaCelular([ethernet, wifi, tail]).map((e) => e.tipo),
      [LanInterfaceTipo.wifi, LanInterfaceTipo.tailscale],
    );
  });

  test('QR de conexao inclui URL com porta e token', () {
    final payload = LanConexaoQr.montar(
      url: '192.168.1.80',
      token: 'abcToken',
    );
    final dados = LanConexaoQr.parse(payload);
    expect(dados, isNotNull);
    expect(dados!.url, 'http://192.168.1.80:8788');
    expect(dados.token, 'abcToken');
    expect(
      LanConexaoQr.parse('http://100.64.1.2:8788')?.url,
      'http://100.64.1.2:8788',
    );
  });
}
