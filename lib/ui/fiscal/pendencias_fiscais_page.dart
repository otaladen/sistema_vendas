import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../config/focus_nfe_runtime.dart';
import '../../domain/fiscal/venda_nfce_obrigatoria_helper.dart';
import '../../domain/venda_documento_rotulo_helper.dart';
import '../../domain/venda_finalizacao_caixa_helper.dart';
import '../../data/app_config_repository.dart';
import '../../data/cliente_repository.dart';
import '../../data/venda_repository.dart';
import '../../model/usuario_sistema.dart';
import '../../model/venda.dart';
import '../../services/focus_nfe_service.dart';
import '../../services/nfce_reconciliacao_service.dart';
import 'nfce_emissao_pendente_flow.dart';
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
  List<Venda> _pendentesSefaz = const [];
  List<Venda> _pendentesEmissao = const [];
  bool _carregando = true;
  bool _reconsultando = false;
  bool _emitindo = false;
  bool _permitirVendaSemEstoque = true;

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
    _carregarConfig();
    _recarregar();
  }

  Future<void> _carregarConfig() async {
    final config = await widget.appConfigRepository.carregarEmpresaConfig();
    if (!mounted) return;
    setState(() => _permitirVendaSemEstoque = config.permitirVendaSemEstoque);
  }

  void _recarregar() {
    setState(() {
      _pendentesSefaz = _reconciliacao.listarPendentes();
      _pendentesEmissao = widget.vendaRepository.listarComNfcePendenteEmissao();
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
          ? 'Nenhuma NFC-e pendente na SEFAZ.'
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
        NfceReconciliacaoTipo.autorizada =>
          r.cupomInternoRegistrado
              ? 'NFC-e autorizada e estoque atualizado.'
              : (r.mensagem.isEmpty
                  ? 'NFC-e autorizada, mas falhou ao salvar venda/estoque.'
                  : r.mensagem),
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

  Future<void> _emitirNfce(Venda venda) async {
    if (_emitindo) return;
    setState(() => _emitindo = true);
    try {
      final ok = await NfceEmissaoPendenteFlow.emitir(
        context,
        venda: venda,
        vendaRepository: widget.vendaRepository,
        clienteRepository: widget.clienteRepository,
        appConfigRepository: widget.appConfigRepository,
        permitirVendaSemEstoque: _permitirVendaSemEstoque,
      );
      if (ok && mounted) _recarregar();
    } finally {
      if (mounted) setState(() => _emitindo = false);
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

  String _dataExibicao(Venda v) {
    final ref = VendaFinalizacaoCaixaHelper.momentoFinalizacao(v);
    return _data.format(ref.toLocal());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final totalEmissao = VendaNfceObrigatoriaHelper.somaTotal(_pendentesEmissao);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Pendencias fiscais'),
        actions: [
          IconButton(
            tooltip: 'Reconsultar NFC-e na SEFAZ',
            onPressed: _reconsultando || _pendentesSefaz.isEmpty
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
            color: _pendentesEmissao.isNotEmpty
                ? scheme.errorContainer.withValues(alpha: 0.35)
                : null,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.warning_amber_rounded,
                        color: _pendentesEmissao.isNotEmpty
                            ? scheme.error
                            : scheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'NFC-e a emitir (PIX / cartao)',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      if (_pendentesEmissao.isNotEmpty)
                        Chip(
                          label: Text('${_pendentesEmissao.length}'),
                          visualDensity: VisualDensity.compact,
                          backgroundColor: scheme.errorContainer,
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _pendentesEmissao.isEmpty
                        ? 'Nenhuma venda paga no cartao ou PIX sem NFC-e autorizada.'
                        : '${_pendentesEmissao.length} venda(s) · '
                            'R\$ ${_moeda.format(totalEmissao)} sem documento fiscal.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
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
          else if (_pendentesEmissao.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text('Nenhuma NFC-e pendente de emissao.'),
              ),
            )
          else
            ..._pendentesEmissao.map((v) {
              final motivo = VendaNfceObrigatoriaHelper.motivoPendenciaEmissao(v);
              return Card(
                child: ListTile(
                  leading: Icon(Icons.receipt_long_outlined, color: scheme.error),
                  title: Text(
                    VendaDocumentoRotuloHelper.rotuloControleInterno(v),
                  ),
                  subtitle: Text(
                    '${_dataExibicao(v)} · '
                    'R\$ ${_moeda.format(v.total)} · '
                    '${VendaNfceObrigatoriaHelper.rotuloFormaPagamento(v)}\n'
                    '$motivo',
                  ),
                  isThreeLine: true,
                  trailing: FilledButton(
                    onPressed: _emitindo ? null : () => _emitirNfce(v),
                    child: const Text('Emitir'),
                  ),
                ),
              );
            }),
          const SizedBox(height: 20),
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
                    'Notas ja enviadas que aguardam retorno. O caixa reconsulta '
                    'automaticamente a cada 45 s.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (!_carregando && _pendentesSefaz.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text('Nenhuma NFC-e aguardando a SEFAZ.'),
              ),
            )
          else if (!_carregando)
            ..._pendentesSefaz.map((v) {
              return Card(
                child: ListTile(
                  leading: Icon(
                    Icons.hourglass_top_outlined,
                    color: scheme.primary,
                  ),
                  title: Text(
                    VendaDocumentoRotuloHelper.rotuloControleInterno(v),
                  ),
                  subtitle: Text(
                    '${_dataExibicao(v)} · R\$ ${_moeda.format(v.total)}',
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
