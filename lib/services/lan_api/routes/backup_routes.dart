import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../../../data/backup_remoto_servidor_service.dart';
import '../lan_api_deps.dart';
import '../lan_api_json.dart';

void registerBackupRoutes(Router router, LanApiDeps d) {
  router.get('/api/backup/status', (_) async {
    try {
      return lanApiJson(await BackupRemotoServidorService.status());
    } catch (e) {
      return lanApiJson(
        {'ok': false, 'error': '$e'},
        status: 500,
      );
    }
  });

  router.post('/api/backup/criar', (_) async {
    try {
      final r = await BackupRemotoServidorService.criar(objectBox: d.objectBox);
      return lanApiJson(r);
    } on BackupRemotoPdvAbertoException catch (e) {
      return lanApiJson(
        {'ok': false, 'error': e.message, 'code': 'pdv_aberto'},
        status: 409,
      );
    } on BackupRemotoOcupadoException catch (e) {
      return lanApiJson(
        {'ok': false, 'error': e.message, 'code': 'backup_ocupado'},
        status: 409,
      );
    } catch (e) {
      return lanApiJson(
        {'ok': false, 'error': '$e'},
        status: 500,
      );
    }
  });

  router.get('/api/backup/zip', (_) async {
    try {
      final zip = await BackupRemotoServidorService.obterZipParaDownload();
      final nome = p.basename(zip.path);
      return Response.ok(
        zip.openRead(),
        headers: {
          'content-type': 'application/zip',
          'content-length': '${zip.lengthSync()}',
          'content-disposition': 'attachment; filename="$nome"',
        },
      );
    } on BackupRemotoSemArquivoException catch (e) {
      return lanApiJson(
        {'ok': false, 'error': e.message, 'code': 'sem_backup'},
        status: 404,
      );
    } catch (e) {
      return lanApiJson(
        {'ok': false, 'error': '$e'},
        status: 500,
      );
    }
  });
}
