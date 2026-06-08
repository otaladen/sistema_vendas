import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../config/focus_nfe_runtime.dart';
import '../../data/app_config_repository.dart';
import '../../data/cliente_repository.dart';
import '../../data/venda_repository.dart';
import '../../model/usuario_sistema.dart';
import '../../model/venda.dart';
import '../../services/focus_nfe_service.dart';
import '../../services/nfce_reconciliacao_service.dart';
import 'nfe_gerenciamento_page.dart';

/// Central de pendencias NFC-e (reconsulta manual) e atalho para NF-e 55.
class PendenciasFiscaisPage extends StatefulWidget {
  const PendenciasFiscaisPage({
    super.key,
    required this.vendaRepository,
    required this.clienteRepository,
    required this.appConfigRepository,
    required this.usuarioLogado,
  });

  final VendaRepository vendaRepository;
  final ClienteRepository clienteRepository;
  final AppConfigRepository appConfigRepository;
  final UsuarioSistema usuarioLogado;

  @override
  State<PendenciasFiscaisPage> createState() => _PendenciasFiscaisPageState();
}

class _PendenciasFiscaisPageState extends State<PendenciasFiscaisPage> {
  late final FocusNfeService _focusNfe;
  late final NfceReconciliacaoService _reconciliacao;
  List<Venda> _pendentes = const [];
  bool _carregando = true;
  bool _reconsultando = false;

  static final _data = DateFormat('dd/MM/yyyy HH:mm');
  static final _moeda = NumberFormat('#,##0.00', 'pt_BR');

  @override
  void initState() {
    super.initState();
    _focusNfe = FocusNfeService(config: criarFocusNfeConfigPadrao());
    _reconciliacao = NfceReconciliacaoService(
      vendaRepository: widget.vendaRepository,
      focusNfe: _focusNfe,
    );
    _recarregar();
  }

  void _recarregar() {
    setState(() {
      _pendentes = _reconciliacao.listarPendentes();
      _carregando = false;
    });
  }

  Future<void> _reconsultarTodas() async {
    if (_reconsultando) return;
    setState(() => _reconsultando = true);
    try {
      _focusNfe.validarConfiguracao();
    } catch (e) {
      if (!mounted) return;
      setState(() => _reconsultando = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e')),
      );
      return;
    }

    try {
      final lote = await _reconciliacao.reconsultarTodasPendentes();
      if (!mounted) return;
      _recarregar();
      final msg = lote.total == 0
          ? 'Nenhuma NFC-e pendente.'
          : lote.autorizadas > 0
              ? '${lote.autorizadas} autorizada(s); '
                  '${lote.aindaProcessando} ainda aguardando.'
              : lote.aindaProcessando > 0
                  ? '${lote.aindaProcessando} ainda aguardando a SEFAZ.'
                  : 'Reconsulta concluida. Verifique a lista.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Falha na reconsulta: $e')),
      );
    } finally {
      if (mounted) setState(() => _reconsultando = false);
    }
  }

  Future<void> _reconsultarUma(Venda venda) async {
    if (_reconsultando) return;
    setState(() => _reconsultando = true);
    try {
      final r = await _reconciliacao.reconsultarVenda(venda);
      if (!mounted) return;
      _recarregar();
      final msg = switch (r.tipo) {
        NfceReconciliacaoTipo.autorizada => 'NFC-e autorizada na reconsulta.',
        NfceReconciliacaoTipo.processando => 'Ainda aguardando a SEFAZ.',
        NfceReconciliacaoTipo.erro =>
          r.mensagem.isEmpty ? 'NFC-e rejeitada ou erro.' : r.mensagem,
        NfceReconciliacaoTipo.semAlteracao => 'Sem alteracao de status.',
      };
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Falha: $e')),
      );
    } finally {
      if (mounted) setState(() => _reconsultando = false);
    }
  }

  void _abrirNfePendencias() {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => NfeGerenciamentoPage(
          vendaRepository: widget.vendaRepository,
          clienteRepository: widget.clienteRepository,
          appConfigRepository: widget.appConfigRepository,
          usuarioLogado: widget.usuarioLogado,
          abaInicial: 1,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pendencias fiscais'),
        actions: [
          IconButton(
            tooltip: 'Reconsultar todas NFC-e',
            onPressed: _reconsultando || _pendentes.isEmpty
                ? null
                : _reconsultarTodas,
            icon: _reconsultando
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'NFC-e aguardando SEFAZ',
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'O caixa reconsulta automaticamente a cada 45 s. '
                    'Use este painel para forcar a reconsulta ou conferir '
                    'antes do fechamento do mes.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (_carregando)
            const Center(child: CircularProgressIndicator())
          else if (_pendentes.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text('Nenhuma NFC-e pendente. Tudo certo por aqui.'),
              ),
            )
          else
            ..._pendentes.map((v) {
              final cupom = v.numeroOrcamento > 0 ? v.numeroOrcamento : v.id;
              return Card(
                child: ListTile(
                  leading: Icon(
                    Icons.hourglass_top_outlined,
                    color: theme.colorScheme.primary,
                  ),
                  title: Text('Venda $cupom'),
                  subtitle: Text(
                    '${_data.format(v.data.toLocal())} · '
                    'R\$ ${_moeda.format(v.total)}',
                  ),
                  trailing: OutlinedButton(
                    onPressed: _reconsultando ? null : () => _reconsultarUma(v),
                    child: const Text('Reconsultar'),
                  ),
                ),
              );
            }),
          const SizedBox(height: 16),
          Card(
            child: ListTile(
              leading: const Icon(Icons.receipt_long_outlined),
              title: const Text('NF-e modelo 55'),
              subtitle: const Text(
                'Processando, rejeitadas e vendas sem faturamento.',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: _abrirNfePendencias,
            ),
          ),
        ],
      ),
    );
  }
}
