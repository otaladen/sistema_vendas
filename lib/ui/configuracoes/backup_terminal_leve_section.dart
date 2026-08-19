import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;

import '../../data/api/lan_api_client.dart';
import '../../data/backup_terminal_copia_storage.dart';
import 'config_section_card.dart';

/// Backup a partir de terminal leve: cria no PC servidor e salva ZIP neste aparelho.
class BackupTerminalLeveSection extends StatefulWidget {
  const BackupTerminalLeveSection({super.key, required this.lanApiClient});

  final dynamic lanApiClient;

  @override
  State<BackupTerminalLeveSection> createState() =>
      _BackupTerminalLeveSectionState();
}

class _BackupTerminalLeveSectionState extends State<BackupTerminalLeveSection> {
  static final _fmt = DateFormat('dd/MM/yyyy HH:mm');

  bool _carregando = true;
  bool _ocupado = false;
  String _etapa = '';
  String? _erroStatus;
  Map<String, dynamic>? _status;
  String _copiaLocalPath = '';
  int _copiaLocalMs = 0;
  int _copiaLocalBytes = 0;

  LanApiClient? get _client {
    final c = widget.lanApiClient;
    return c is LanApiClient && c.configurado ? c : null;
  }

  @override
  void initState() {
    super.initState();
    _recarregar();
  }

  Future<void> _recarregar() async {
    setState(() {
      _carregando = true;
      _erroStatus = null;
    });
    final local = await BackupTerminalCopiaStorage.carregar();
    Map<String, dynamic>? status;
    String? erro;
    final client = _client;
    if (client == null) {
      erro = 'Este terminal nao esta conectado a API do PC servidor.';
    } else {
      try {
        status = await client.backupRemotoStatus();
      } catch (e) {
        erro = '$e';
      }
    }
    if (!mounted) return;
    setState(() {
      _copiaLocalPath = local.path;
      _copiaLocalMs = local.ms;
      _copiaLocalBytes = local.bytes;
      _status = status;
      _erroStatus = erro;
      _carregando = false;
    });
  }

  bool get _copiaLocalExiste =>
      _copiaLocalPath.isNotEmpty && File(_copiaLocalPath).existsSync();

  Future<String?> _escolherDestino(String nomeSugerido) async {
    final path = await FilePicker.platform.saveFile(
      dialogTitle: 'Salvar copia do backup neste PC',
      fileName: nomeSugerido,
      type: FileType.custom,
      allowedExtensions: const ['zip'],
    );
    if (path == null || path.trim().isEmpty) return null;
    return path.toLowerCase().endsWith('.zip') ? path : '$path.zip';
  }

  Future<void> _criarESalvar() async {
    final client = _client;
    if (client == null || _ocupado) return;
    final destino = await _escolherDestino(
      'backup_sistema_vendas_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.zip',
    );
    if (destino == null || !mounted) return;

    setState(() {
      _ocupado = true;
      _etapa = 'Criando backup no PC servidor…';
    });
    try {
      await client.criarBackupRemoto();
      if (!mounted) return;
      setState(() => _etapa = 'Salvando copia neste PC…');
      await client.baixarBackupZipParaArquivo(destino);
      await _registrarCopiaLocal(destino);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Backup salvo neste PC:\n$destino')),
      );
      await _recarregar();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$e'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _ocupado = false;
          _etapa = '';
        });
      }
    }
  }

  Future<void> _baixarUltimo() async {
    final client = _client;
    if (client == null || _ocupado) return;
    final zip = _status?['zip'];
    final nome = zip is Map && (zip['nome'] ?? '').toString().isNotEmpty
        ? zip['nome'].toString()
        : 'backup_sistema_vendas.zip';
    final destino = await _escolherDestino(nome);
    if (destino == null || !mounted) return;

    setState(() {
      _ocupado = true;
      _etapa = 'Baixando ultimo backup do servidor…';
    });
    try {
      await client.baixarBackupZipParaArquivo(destino);
      await _registrarCopiaLocal(destino);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Copia salva neste PC:\n$destino')),
      );
      await _recarregar();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$e'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _ocupado = false;
          _etapa = '';
        });
      }
    }
  }

  Future<void> _registrarCopiaLocal(String path) async {
    final file = File(path);
    final bytes = file.existsSync() ? file.lengthSync() : 0;
    final ms = DateTime.now().millisecondsSinceEpoch;
    await BackupTerminalCopiaStorage.salvar(path: path, ms: ms, bytes: bytes);
    if (!mounted) return;
    setState(() {
      _copiaLocalPath = path;
      _copiaLocalMs = ms;
      _copiaLocalBytes = bytes;
    });
  }

  String _fmtBytes(int bytes) {
    if (bytes <= 0) return '—';
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    if (bytes >= 1024) {
      return '${(bytes / 1024).toStringAsFixed(0)} KB';
    }
    return '$bytes B';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = _status;
    final pdvEmUso = status?['pdvEmUso'] == true;
    final temZip = status?['temZip'] == true;
    final ultimo = status?['ultimoBackup'];
    String? ultimoTexto;
    if (ultimo is Map) {
      final dt = DateTime.tryParse((ultimo['criadoEm'] ?? '').toString());
      if (dt != null) {
        ultimoTexto = _fmt.format(dt.toLocal());
      }
    }

    return ConfigSectionCard(
      icon: Icons.backup_outlined,
      title: 'Backup neste terminal',
      subtitle:
          'O banco oficial fica no PC servidor. Este terminal pede a copia la '
          'e grava um ZIP aqui — se o PC 1 falhar, voce ja tem o arquivo.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Se o PC servidor ja estiver desligado, nao da para criar backup '
            'novo. Use o ZIP ja salvo neste PC e restaure em outro computador '
            '(Configuracoes > Backup > restaurar ZIP), virando o novo servidor.',
            style: theme.textTheme.bodyMedium?.copyWith(height: 1.4),
          ),
          const SizedBox(height: 12),
          if (_carregando)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Center(child: CircularProgressIndicator()),
            )
          else ...[
            if (_erroStatus != null)
              Text(
                _erroStatus!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                  height: 1.35,
                ),
              )
            else ...[
              Text(
                ultimoTexto == null
                    ? 'Nenhum backup completo no servidor ainda.'
                    : 'Ultimo backup no servidor: $ultimoTexto',
                style: theme.textTheme.bodySmall,
              ),
              if (pdvEmUso) ...[
                const SizedBox(height: 6),
                Text(
                  'PDV aberto no servidor: da para baixar o ultimo ZIP, '
                  'mas nao criar um backup novo agora.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.tertiary,
                  ),
                ),
              ],
            ],
            const SizedBox(height: 8),
            Text(
              _copiaLocalExiste
                  ? 'Copia neste PC: ${_fmt.format(DateTime.fromMillisecondsSinceEpoch(_copiaLocalMs))} '
                      '(${_fmtBytes(_copiaLocalBytes)})\n${p.basename(_copiaLocalPath)}'
                  : 'Ainda nao ha copia salva neste terminal.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.35,
              ),
            ),
            if (_ocupado) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: Text(_etapa)),
                ],
              ),
            ],
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _ocupado || _client == null ? null : _criarESalvar,
              icon: const Icon(Icons.save_alt_outlined),
              label: const Text('Criar backup agora e salvar neste PC'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _ocupado || _client == null || (!temZip && ultimoTexto == null)
                  ? null
                  : _baixarUltimo,
              icon: const Icon(Icons.download_outlined),
              label: const Text('Salvar neste PC o ultimo backup do servidor'),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _ocupado ? null : _recarregar,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Atualizar status'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
