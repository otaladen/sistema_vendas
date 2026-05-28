import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/app_config_repository.dart';
import '../../data/motorista_repository.dart';
import '../../data/venda_repository.dart';
import '../../services/entrega_pod_finalizacao.dart';
import '../../domain/entrega_filtro_util.dart';
import '../../domain/motorista_usuario_resolver.dart';
import '../../domain/usuario_permissao_helper.dart';
import '../../model/usuario_sistema.dart';
import '../../model/venda.dart';
import '../entregas/pod_entrega_dialog.dart';
import '../../model/historico_entrega.dart';

/// Painel do motorista: entregas do dia atribuidas ao usuario logado.
class MotoristaEntregasPage extends StatefulWidget {
  const MotoristaEntregasPage({
    super.key,
    required this.vendaRepository,
    required this.motoristaRepository,
    required this.usuarioLogado,
    this.appConfigRepository,
  });

  final VendaRepository vendaRepository;
  final MotoristaRepository motoristaRepository;
  final UsuarioSistema usuarioLogado;
  final AppConfigRepository? appConfigRepository;

  @override
  State<MotoristaEntregasPage> createState() => _MotoristaEntregasPageState();
}

class _MotoristaEntregasPageState extends State<MotoristaEntregasPage> {
  List<Venda> _entregas = [];
  late String _nomeMotorista;
  bool _carregando = true;

  @override
  void initState() {
    super.initState();
    _nomeMotorista = MotoristaUsuarioResolver.nomeMotoristaLogistica(
      widget.usuarioLogado,
      widget.motoristaRepository.listarAtivos(),
    );
    _carregar();
  }

  void _carregar() {
    setState(() {
      _carregando = true;
      _entregas = widget.vendaRepository.listarEntregasModoMotorista(
        _nomeMotorista,
      );
      _carregando = false;
    });
  }

  int _progressoCarga(Venda v) {
    var n = 0;
    if (v.cargaSeparada) n++;
    if (v.cargaCarregada) n++;
    if (v.cargaSaiu) n++;
    return n;
  }

  Future<void> _navegar(Venda v) async {
    final endereco = v.enderecoEntrega.trim();
    if (endereco.isEmpty) return;
    final uri = Uri.parse(
      'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(endereco)}',
    );
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _marcarEntregue(Venda venda) async {
    if (!UsuarioPermissaoHelper.podeRegistrarPodEntrega(widget.usuarioLogado)) {
      return;
    }
    if (_progressoCarga(venda) < 3) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Aguarde a expedicao marcar Separado, Carregado e Saiu antes de entregar.',
          ),
        ),
      );
      return;
    }
    if (venda.statusEntrega != 'saiu_entrega' &&
        venda.statusEntrega != 'roteirizada') {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Esta entrega nao esta pronta para baixa no modo motorista.'),
        ),
      );
      return;
    }

    final pod = await showPodEntregaDialog(
      context: context,
      vendaId: venda.id,
    );
    if (pod == null || !mounted) return;

    try {
      final podFinal = EntregaPodFinalizacao(
        configRepository: widget.appConfigRepository,
      );
      await podFinal.registrarPod(
        vendaRepository: widget.vendaRepository,
        vendaId: venda.id,
        recebidoPor: pod.recebidoPor,
        usuarioLogin: widget.usuarioLogado.login,
        fotoPathLocal: pod.fotoPathLocal ?? '',
        fotoPathServidor: pod.fotoPathServidor ?? '',
      );
      final statusAnterior = venda.statusEntrega;
      widget.vendaRepository.atualizarStatusEntrega(venda.id, 'entregue');
      widget.vendaRepository.registrarHistoricoStatusEntrega(
        vendaId: venda.id,
        statusAnterior: statusAnterior,
        statusNovo: 'entregue',
        usuario: widget.usuarioLogado.login,
      );
      widget.vendaRepository.registrarOcorrenciaEntrega(
        vendaId: venda.id,
        status: HistoricoEntregaEventos.podEntrega,
        motivo:
            'Recebido por: ${pod.recebidoPor}${pod.fotoPathLocal != null ? ' (com foto no servidor)' : ''}',
        usuario: widget.usuarioLogado.login,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Entrega ${venda.numeroOrcamento} concluida.')),
      );
      _carregar();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro: $e'), backgroundColor: Colors.red),
      );
    }
  }

  String _rotuloStatus(String s) {
    switch (s) {
      case 'roteirizada':
        return 'Roteirizada';
      case 'saiu_entrega':
        return 'Saiu para entrega';
      case 'entregue_complemento_pendente':
        return 'Complemento pendente';
      default:
        return s;
    }
  }

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('dd/MM/yyyy HH:mm');
    return Scaffold(
      appBar: AppBar(
        title: const Text('Modo motorista'),
        actions: [
          IconButton(
            tooltip: 'Atualizar',
            onPressed: _carregar,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _carregando
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () async => _carregar(),
              child: ListView(
                padding: const EdgeInsets.all(12),
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.usuarioLogado.nome,
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          Text('Motorista: $_nomeMotorista'),
                          Text(
                            '${_entregas.length} entrega(s) em rota',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (_entregas.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(32),
                      child: Center(
                        child: Text(
                          'Nenhuma entrega ativa para voce no momento.',
                        ),
                      ),
                    ),
                  ..._entregas.map((v) {
                    final prog = _progressoCarga(v);
                    final atrasada = EntregaFiltroUtil.ehAtrasada(v);
                    return Card(
                      margin: const EdgeInsets.only(bottom: 10),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              'Pedido ${v.numeroOrcamento}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 16,
                              ),
                            ),
                            Text(v.cliente.target?.nomeRazao ?? 'Cliente'),
                            const SizedBox(height: 4),
                            Text(v.enderecoEntrega),
                            Wrap(
                              spacing: 8,
                              runSpacing: 4,
                              children: [
                                Chip(
                                  label: Text(_rotuloStatus(v.statusEntrega)),
                                  visualDensity: VisualDensity.compact,
                                ),
                                Chip(
                                  label: Text('Carga $prog/3'),
                                  visualDensity: VisualDensity.compact,
                                ),
                                if (atrasada)
                                  Chip(
                                    label: const Text('Atrasada'),
                                    backgroundColor: Colors.red.shade50,
                                    visualDensity: VisualDensity.compact,
                                  ),
                              ],
                            ),
                            if (v.dataEntregaMarcada != null)
                              Text(
                                'Data marcada: ${fmt.format(v.dataEntregaMarcada!.toLocal())}',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: () => _navegar(v),
                                    icon: const Icon(Icons.directions_outlined),
                                    label: const Text('Navegar'),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: FilledButton.icon(
                                    onPressed: prog >= 3 &&
                                            (v.statusEntrega == 'saiu_entrega' ||
                                                v.statusEntrega == 'roteirizada')
                                        ? () => _marcarEntregue(v)
                                        : null,
                                    icon: const Icon(Icons.check_circle_outline),
                                    label: const Text('Entregue'),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
                ],
              ),
            ),
    );
  }
}
