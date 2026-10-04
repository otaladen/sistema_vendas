import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:image/image.dart' as img;
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';

import 'package:sistema_vendas/data/api/lan_api_client.dart';
import 'package:sistema_vendas/data/app_config_repository.dart';
import 'package:sistema_vendas/services/configuracoes_service.dart';
import 'package:sistema_vendas/services/empresa_logo_service.dart';
import 'package:sistema_vendas/services/empresa_logo_sync_service.dart';
import 'package:sistema_vendas/services/esc_pos_image.dart';
import 'package:sistema_vendas/services/lan_api/routes/empresa_logo_routes.dart';

/// Permite HTTP real nos testes de integracao (shelf local).
class _HttpRealOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..badCertificateCallback = (_, __, ___) => true;
  }
}

void main() {
  late Directory pastaLogoTeste;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    HttpOverrides.global = _HttpRealOverrides();
    pastaLogoTeste = await Directory.systemTemp.createTemp('logo_empresa_test_');
    EmpresaLogoService.pastaEmpresaOverrideForTest = pastaLogoTeste;
  });

  tearDownAll(() {
    HttpOverrides.global = null;
    EmpresaLogoService.pastaEmpresaOverrideForTest = null;
    if (pastaLogoTeste.existsSync()) {
      pastaLogoTeste.deleteSync(recursive: true);
    }
  });

  test('ESC/POS raster: imagem 8px gera GS v 0 com largura 1 byte', () {
    final im = img.Image(width: 8, height: 2);
    for (var x = 0; x < 8; x++) {
      im.setPixelRgb(x, 0, 0, 0, 0);
      im.setPixelRgb(x, 1, 255, 255, 255);
    }
    final png = Uint8List.fromList(img.encodePng(im));
    final cmd = EscPosImageRaster.comandosBitonal(
      png,
      maxWidthPx: 384,
    );
    expect(cmd, isNotNull);
    expect(cmd!.length, greaterThan(8));
    expect(cmd[0], EscPosImageRaster.headerGsV0);
    expect(cmd[1], EscPosImageRaster.cmdGsV0);
    expect(cmd[2], 0x30);
    expect(cmd[4], 1);
    expect(cmd[8], 0xFF);
    expect(cmd[9], 0x00);
  });

  test('API /api/empresa/logo POST e GET roundtrip', () async {
    HttpServer? server;
    final repo = AppConfigRepository();
    ConfiguracoesService.registrar(repo);
    try {
      final router = Router();
      registerEmpresaLogoRoutes(router, notificar: (_) {});
      server = await shelf_io.serve(
        router.call,
        InternetAddress.loopbackIPv4,
        0,
      );
      final port = server.port;
      final client = LanApiClient(
        baseUrl: 'http://127.0.0.1:$port',
        syncToken: '',
      );

      final im = img.Image(width: 16, height: 16);
      img.fill(im, color: img.ColorRgb8(200, 40, 40));
      final bytes = img.encodePng(im);

      final post = await client.uploadEmpresaLogo(bytes);
      expect(post['ok'], isTrue);
      final hash = (post['logoHash'] ?? '').toString();
      expect(hash, isNotEmpty);

      final baixado = await client.downloadEmpresaLogo();
      expect(baixado, isNotNull);
      expect(EmpresaLogoService.hashBytes(Uint8List.fromList(baixado!)), hash);

      await client.removerEmpresaLogo();
      final vazio = await client.downloadEmpresaLogo();
      expect(vazio, isNull);
    } finally {
      await server?.close(force: true);
    }
  });

  test('sincronizacao grava arquivo local quando hash remoto difere', () async {
    HttpServer? server;
    final repo = AppConfigRepository();
    ConfiguracoesService.registrar(repo);
    try {
      final router = Router();
      registerEmpresaLogoRoutes(router, notificar: (_) {});
      server = await shelf_io.serve(
        router.call,
        InternetAddress.loopbackIPv4,
        0,
      );
      final port = server.port;
      final client = LanApiClient(
        baseUrl: 'http://127.0.0.1:$port',
        syncToken: '',
      );
      ConfiguracoesService.global.vincularLanApiClient(client);

      final im = img.Image(width: 12, height: 12);
      img.fill(im, color: img.ColorRgb8(10, 120, 200));
      final png = Uint8List.fromList(img.encodePng(im));
      final post = await client.uploadEmpresaLogo(png);
      final hash = (post['logoHash'] ?? '').toString();

      await repo.salvarEmpresaConfig(
        EmpresaConfig(
          redeServidorUrl: 'http://127.0.0.1:$port',
          logoHash: hash,
          logoPath: '',
        ),
        propagarRede: false,
      );

      await EmpresaLogoSyncService(configRepository: repo)
          .sincronizarArquivoSeNecessario();

      final depois = await repo.carregarEmpresaConfig();
      expect(depois.logoPath.trim(), isNotEmpty);
      expect(File(depois.logoPath).existsSync(), isTrue);
      expect(
        await EmpresaLogoService.hashArquivo(depois.logoPath),
        hash,
      );
    } finally {
      await server?.close(force: true);
    }
  });
}
