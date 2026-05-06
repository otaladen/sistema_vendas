import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

class SyncCursorStorage {
  static const _kRevision = 'sync_lan_last_revision';
  static const _kDevice = 'sync_lan_device_id';

  Future<int> carregarUltimaRevision() async {
    final p = await SharedPreferences.getInstance();
    return p.getInt(_kRevision) ?? 0;
  }

  Future<void> salvarUltimaRevision(int revision) async {
    final p = await SharedPreferences.getInstance();
    await p.setInt(_kRevision, revision);
  }

  Future<String> obterOuCriarDeviceId() async {
    final p = await SharedPreferences.getInstance();
    var id = p.getString(_kDevice);
    if (id != null && id.trim().isNotEmpty) {
      return id.trim();
    }
    final rnd = Random.secure();
    id = List.generate(16, (_) => rnd.nextInt(256))
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
    await p.setString(_kDevice, id);
    return id;
  }
}
