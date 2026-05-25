import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/app_config_repository.dart';
import '../../data/sync/lan_sync_scheduler.dart';
import '../../data/sync/sync_api_client.dart';
import '../../data/sync/sync_log.dart';
import '../../domain/sync_token_util.dart';
import '../../services/lan_sync_server_manager.dart';

/// Assistente de rede local: servidor neste PC ou cliente apontando para outro.
class RedeSincronizacaoCard extends StatefulWidget {
  const RedeSincronizacaoCard({
    super.key,
    required this.configRepository,
    this.lanSyncScheduler,
  });

  final AppConfigRepository configRepository;
  final LanSyncScheduler? lanSyncScheduler;

  @override
  State<RedeSincronizacaoCard> createState() => _RedeSincronizacaoCardState();
}

class _RedeSincronizacaoCardState extends State<RedeSincronizacaoCard> {
  final _urlController = TextEditingController();
  final _portaController = TextEditingController();
  final _tokenController = TextEditingController();

  bool _modoServidor = false;
  bool _syncAtiva = false;
  String? _ipLocal;
  bool _servidorOnline = false;
  bool _carregando = true;
  bool _salvando = false;
  bool _testandoRede = false;
  bool _sincronizando = false;
  bool _iniciandoServidor = false;
  bool _parandoServidor = false;

  int? _estacoesAtivas;
  List<Map<String, dynamic>> _estacoesLista = [];
  String _presencaErro = '';
  bool _carregandoPresenca = false;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  @override
  void dispose() {
    _urlController.dispose();
    _portaController.dispose();
    _tokenController.dispose();
    super.dispose();
  }

  int get _porta {
    final p = int.tryParse(_portaController.text.trim());
    if (p == null || p < 1024 || p > 65535) {
      return LanSyncServerManager.portaPadrao;
    }
    return p;
  }

  Future<void> _carregar() async {
    setState(() => _carregando = true);
    final config = await widget.configRepository.carregarEmpresaConfig();
    final ip = await LanSyncServerManager.obterIpv4Local();
    final porta = config.redePortaServidor;
    var url = config.redeServidorUrl.trim();
    if (config.redeModoServidor && ip != null && url.isEmpty) {
      url = LanSyncServerManager.montarUrlServidor(ip, porta);
    }
    final online = url.isNotEmpty
        ? await LanSyncServerManager.servidorRespondendo(url)
        : await LanSyncServerManager.servidorRespondendoNaPorta(porta);

    if (!mounted) return;
    setState(() {
      _modoServidor = config.redeModoServidor;
      _syncAtiva = config.redeSincronizacaoAtiva;
      _ipLocal = ip;
      _portaController.text = '$porta';
      _urlController.text = url;
      _tokenController.text = config.redeSyncToken;
      _servidorOnline = online;
      _carregando = false;
    });
  }

  void _aoMudarModo(bool servidor) {
    setState(() {
      _modoServidor = servidor;
      if (servidor && _ipLocal != null) {
        _urlController.text =
            LanSyncServerManager.montarUrlServidor(_ipLocal!, _porta);
      }
    });
    _atualizarStatusServidor();
  }

  void _preencherUrlServidorLocal() {
    final ip = _ipLocal;
    if (ip == null || ip.isEmpty) return;
    _urlController.text = LanSyncServerManager.montarUrlServidor(ip, _porta);
  }

  Future<void> _atualizarStatusServidor() async {
    final url = _urlController.text.trim();
    final online = url.isNotEmpty
        ? await LanSyncServerManager.servidorRespondendo(url)
        : await LanSyncServerManager.servidorRespondendoNaPorta(_porta);
    if (mounted) setState(() => _servidorOnline = online);
  }

  Future<void> _salvar({bool iniciarServidorSeModoServidor = false}) async {
    setState(() => _salvando = true);
    try {
      if (_modoServidor) {
        _preencherUrlServidorLocal();
      }
      final atual = await widget.configRepository.carregarEmpresaConfig();
      var token = _tokenController.text.trim();
      if (_syncAtiva && token.isEmpty) {
        token = gerarTokenSyncLan();
        _tokenController.text = token;
      }
      final config = atual.copyWith(
        redeSincronizacaoAtiva: _syncAtiva,
        redeModoServidor: _modoServidor,
        redePortaServidor: _porta,
        redeServidorUrl: _urlController.text.trim(),
        redeSyncToken: token,
      );
      await widget.configRepository.salvarEmpresaConfig(config);

      if (_modoServidor && iniciarServidorSeModoServidor && Platform.isWindows) {
        final err = await LanSyncServerManager.iniciarServidor(
          porta: _porta,
          syncToken: token,
        );
        if (err != null && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(err)),
          );
        }
      }

      await widget.lanSyncScheduler?.iniciar();
      await _atualizarStatusServidor();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Configuracao de rede salva.')),
      );
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  Future<void> _configurarRedeCompleta() async {
    if (_modoServidor) {
      final ip = _ipLocal ?? await LanSyncServerManager.obterIpv4Local();
      if (ip == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Nao foi possivel detectar o IP deste PC na rede. '
              'Verifique Wi-Fi/cabo.',
            ),
          ),
        );
        return;
      }
      setState(() => _ipLocal = ip);
      _urlController.text = LanSyncServerManager.montarUrlServidor(ip, _porta);
    }

    setState(() => _syncAtiva = true);
    await _salvar(iniciarServidorSeModoServidor: _modoServidor);
    if (!mounted) return;

    await _testarConexao(silencioso: false);
    if (!mounted) return;

    if (_servidorOnline) {
      await _sincronizarAgora();
    }
  }

  Uri? _parseUri(String raw) {
    final s = raw.trim();
    if (s.isEmpty) return null;
    final comEsquema = s.contains('://') ? s : 'http://$s';
    return Uri.tryParse(comEsquema);
  }

  Future<void> _testarConexao({bool silencioso = false}) async {
    final uri = _parseUri(_urlController.text);
    if (uri == null || uri.host.isEmpty) {
      if (!silencioso && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Informe o endereco do servidor (ex.: 192.168.0.10:8787).'),
          ),
        );
      }
      return;
    }
    final porta = uri.hasPort ? uri.port : (uri.scheme == 'https' ? 443 : 80);
    setState(() => _testandoRede = true);
    try {
      final health = await SyncApiClient(
        baseUrl: _urlController.text,
        syncToken: _tokenController.text.trim(),
      ).health();
      if (!mounted) return;
      if (health) {
        setState(() => _servidorOnline = true);
        if (!silencioso) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Servidor OK em ${uri.host}:$porta.'),
            ),
          );
        }
      } else {
        await Socket.connect(uri.host, porta, timeout: const Duration(seconds: 6));
        if (!mounted) return;
        setState(() => _servidorOnline = false);
        if (!silencioso) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Porta ${uri.host}:$porta alcancavel, mas o servico de sync '
                'nao respondeu. Inicie o servidor neste PC.',
              ),
            ),
          );
        }
      }
    } on SocketException catch (e) {
      if (!mounted) return;
      setState(() => _servidorOnline = false);
      if (!silencioso) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Nao alcancou ${uri.host}:$porta. Verifique rede e firewall. (${e.message})',
            ),
          ),
        );
      }
    } catch (e) {
      if (!silencioso && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao testar: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _testandoRede = false);
    }
  }

  Future<void> _iniciarServidor() async {
    setState(() => _iniciandoServidor = true);
    try {
      final err = await LanSyncServerManager.iniciarServidor(
        porta: _porta,
        syncToken: _tokenController.text.trim(),
      );
      if (!mounted) return;
      if (err != null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
      } else {
        _preencherUrlServidorLocal();
        setState(() => _servidorOnline = true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Servidor de sincronizacao iniciado.')),
        );
      }
    } finally {
      if (mounted) setState(() => _iniciandoServidor = false);
    }
  }

  Future<void> _pararServidor() async {
    setState(() => _parandoServidor = true);
    try {
      await LanSyncServerManager.pararServidor();
      await _atualizarStatusServidor();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Comando de parada enviado ao servidor.')),
      );
    } finally {
      if (mounted) setState(() => _parandoServidor = false);
    }
  }

  Future<void> _liberarFirewall() async {
    final err = await LanSyncServerManager.tentarLiberarFirewall(_porta);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          err ?? 'Regra de firewall criada para a porta $_porta (se permitido pelo Windows).',
        ),
      ),
    );
  }

  Future<void> _sincronizarAgora() async {
    final agendador = widget.lanSyncScheduler;
    if (agendador == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Agendador de sync indisponivel.')),
      );
      return;
    }
    if (!_syncAtiva || _urlController.text.trim().isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Ative a sincronizacao, salve o endereco e tente de novo.'),
        ),
      );
      return;
    }
    setState(() => _sincronizando = true);
    try {
      final erro = await agendador.sincronizarAgora();
      if (!mounted) return;
      if (erro != null && erro.trim().isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Sync: $erro'), backgroundColor: Colors.red),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Sincronizacao concluida.')),
        );
      }
    } finally {
      if (mounted) setState(() => _sincronizando = false);
    }
  }

  Future<void> _atualizarPresenca() async {
    final uri = _urlController.text.trim();
    if (uri.isEmpty) {
      setState(() {
        _estacoesAtivas = null;
        _estacoesLista = [];
        _presencaErro = 'Salve o endereco do servidor antes.';
      });
      return;
    }
    setState(() {
      _carregandoPresenca = true;
      _presencaErro = '';
    });
    final client = SyncApiClient(
      baseUrl: uri,
      syncToken: _tokenController.text.trim(),
    );
    try {
      final map = await client.obterPresenca();
      if (!mounted) return;
      if (map == null) {
        setState(() {
          _carregandoPresenca = false;
          _presencaErro = 'Servidor nao respondeu. Inicie o servidor neste PC.';
        });
        return;
      }
      final n = (map['activeCount'] as num?)?.toInt();
      final raw = map['stations'];
      final lista = <Map<String, dynamic>>[];
      if (raw is List) {
        for (final e in raw) {
          if (e is Map<String, dynamic>) {
            lista.add(e);
          } else if (e is Map) {
            lista.add(Map<String, dynamic>.from(e));
          }
        }
      }
      setState(() {
        _carregandoPresenca = false;
        _estacoesAtivas = n;
        _estacoesLista = lista;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _carregandoPresenca = false;
        _presencaErro = 'Erro: $e';
      });
    }
  }

  String _formatarHora(DateTime dt) {
    final l = dt.toLocal();
    final h = l.hour.toString().padLeft(2, '0');
    final m = l.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  void _copiarEnderecoClientes() {
    final ip = _ipLocal;
    if (ip == null) return;
    final txt = '$ip:$_porta';
    Clipboard.setData(ClipboardData(text: txt));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Copiado para os outros PCs: $txt')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final onVar = tema.colorScheme.onSurfaceVariant;
    final erro = tema.colorScheme.error;

    if (_carregando) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Rede e sincronizacao (LAN)',
              style: tema.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Escolha o papel deste computador. O servidor concentra os dados; '
              'os outros PCs conectam ao IP dele na mesma rede Wi-Fi/cabo.',
              style: tema.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(
                  value: true,
                  label: Text('Servidor neste PC'),
                  icon: Icon(Icons.dns_outlined),
                ),
                ButtonSegment(
                  value: false,
                  label: Text('Outro PC e servidor'),
                  icon: Icon(Icons.lan_outlined),
                ),
              ],
              selected: {_modoServidor},
              onSelectionChanged: (s) => _aoMudarModo(s.first),
            ),
            const SizedBox(height: 12),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              value: _syncAtiva,
              onChanged: (v) => setState(() => _syncAtiva = v),
              title: const Text('Usar sincronizacao na rede local'),
              subtitle: const Text(
                'Sincroniza cadastros, estoque, vendas, NF-e, kits, usuarios e configuracoes.',
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _tokenController,
              decoration: InputDecoration(
                labelText: 'Token de sincronizacao (LAN)',
                hintText: 'Gerado ao salvar se vazio',
                border: const OutlineInputBorder(),
                isDense: true,
                suffixIcon: IconButton(
                  tooltip: 'Gerar novo token',
                  icon: const Icon(Icons.vpn_key_outlined),
                  onPressed: () {
                    setState(() {
                      _tokenController.text = gerarTokenSyncLan();
                    });
                  },
                ),
              ),
              obscureText: true,
              autocorrect: false,
            ),
            const SizedBox(height: 4),
            Text(
              'O mesmo token deve estar no servidor (variavel SYNC_TOKEN ao iniciar '
              'o .exe) e em todos os PCs clientes. Senhas de usuario nao sao replicadas.',
              style: tema.textTheme.bodySmall,
            ),
            ValueListenableBuilder<SyncLogEntry?>(
              valueListenable: SyncLog.ultimo,
              builder: (context, entry, _) {
                if (entry == null) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    entry.sucesso
                        ? 'Ultima sync: OK (${_formatarHora(entry.em)})'
                        : 'Ultima sync falhou (${_formatarHora(entry.em)}): '
                            '${entry.mensagem.split('\n').first}',
                    style: TextStyle(
                      fontSize: 12,
                      color: entry.sucesso ? Colors.green.shade800 : erro,
                    ),
                  ),
                );
              },
            ),
            if (_modoServidor) ...[
              const SizedBox(height: 8),
              _InfoLinha(
                rotulo: 'IP deste PC na rede',
                valor: _ipLocal ?? 'Nao detectado',
                trailing: IconButton(
                  tooltip: 'Atualizar IP',
                  onPressed: () async {
                    final ip = await LanSyncServerManager.obterIpv4Local();
                    setState(() => _ipLocal = ip);
                    if (ip != null) _preencherUrlServidorLocal();
                  },
                  icon: const Icon(Icons.refresh, size: 20),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _portaController,
                decoration: const InputDecoration(
                  labelText: 'Porta do servidor',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                onChanged: (_) => _preencherUrlServidorLocal(),
              ),
              const SizedBox(height: 8),
              _InfoLinha(
                rotulo: 'Endereco para este app',
                valor: _urlController.text.isEmpty ? '—' : _urlController.text,
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(
                    _servidorOnline ? Icons.check_circle : Icons.error_outline,
                    size: 18,
                    color: _servidorOnline ? Colors.green.shade700 : erro,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _servidorOnline
                          ? 'Servidor de sync respondendo'
                          : 'Servidor parado ou inacessivel',
                      style: tema.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    onPressed: (_iniciandoServidor || _servidorOnline)
                        ? null
                        : _iniciarServidor,
                    icon: _iniciandoServidor
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.play_arrow_outlined, size: 20),
                    label: const Text('Iniciar servidor'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _parandoServidor || !_servidorOnline
                        ? null
                        : _pararServidor,
                    icon: const Icon(Icons.stop_outlined, size: 20),
                    label: const Text('Parar'),
                  ),
                  if (Platform.isWindows)
                    OutlinedButton(
                      onPressed: _liberarFirewall,
                      child: const Text('Liberar porta no firewall'),
                    ),
                ],
              ),
              if (_ipLocal != null) ...[
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _copiarEnderecoClientes,
                  icon: const Icon(Icons.copy_outlined, size: 18),
                  label: Text(
                    'Copiar endereco para outros PCs (${_ipLocal!}:$_porta)',
                  ),
                ),
              ],
            ] else ...[
              const SizedBox(height: 8),
              TextField(
                controller: _urlController,
                decoration: const InputDecoration(
                  labelText: 'Endereco do servidor na rede',
                  hintText: 'Ex.: 192.168.0.15:8787',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.url,
                autocorrect: false,
              ),
            ],
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _salvando ? null : _configurarRedeCompleta,
                icon: const Icon(Icons.auto_fix_high_outlined),
                label: Text(
                  _salvando
                      ? 'Configurando...'
                      : 'Configurar rede (salvar + iniciar + sincronizar)',
                ),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: (_salvando || _testandoRede)
                        ? null
                        : () => _testarConexao(),
                    icon: _testandoRede
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.wifi_tethering_outlined),
                    label: Text(_testandoRede ? 'Testando...' : 'Testar'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _salvando ? null : () => _salvar(),
                    icon: const Icon(Icons.save_outlined),
                    label: Text(_salvando ? 'Salvando...' : 'Salvar'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: (_sincronizando || _salvando)
                    ? null
                    : _sincronizarAgora,
                icon: _sincronizando
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.cloud_sync_outlined),
                label: Text(
                  _sincronizando
                      ? 'Sincronizando...'
                      : 'Sincronizar dados agora',
                ),
              ),
            ),
            if (_modoServidor) ...[
              const Divider(height: 24),
              Text(
                'Estacoes conectadas',
                style: tema.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'PCs com o app aberto e sincronizacao ativa (atualiza a cada ~45 s).',
                style: tema.textTheme.bodySmall?.copyWith(color: onVar),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _carregandoPresenca ? null : _atualizarPresenca,
                icon: _carregandoPresenca
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.devices_outlined),
                label: Text(
                  _carregandoPresenca ? 'Consultando...' : 'Ver estacoes online',
                ),
              ),
              if (_presencaErro.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    _presencaErro,
                    style: TextStyle(color: erro, fontSize: 13),
                  ),
                ),
              if (_estacoesAtivas != null && _presencaErro.isEmpty) ...[
                const SizedBox(height: 8),
                Text('Total ativo: $_estacoesAtivas'),
                ..._estacoesLista.map((s) {
                  final lab = (s['label'] ?? '').toString();
                  return Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text('• ${lab.isEmpty ? "PC" : lab}'),
                  );
                }),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class _InfoLinha extends StatelessWidget {
  const _InfoLinha({
    required this.rotulo,
    required this.valor,
    this.trailing,
  });

  final String rotulo;
  final String valor;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(rotulo, style: Theme.of(context).textTheme.labelSmall),
              const SizedBox(height: 2),
              Text(
                valor,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ],
          ),
        ),
        ?trailing,
      ],
    );
  }
}
