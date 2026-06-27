import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../data/objectbox.dart';
import '../data/recado_loja_repository.dart';
import '../data/sync/safe_sync_refresh_mixin.dart';
import '../domain/perfil_usuario_preset.dart';
import '../domain/recado_loja_constantes.dart';
import '../domain/recado_loja_helper.dart';
import '../model/recado_loja.dart';
import '../model/usuario_sistema.dart';

/// Recados internos para a equipe da loja (Fase 1).
class RecadosLojaPage extends StatefulWidget {
  const RecadosLojaPage({
    super.key,
    required this.objectBox,
    required this.usuarioLogado,
  });

  final ObjectBox objectBox;
  final UsuarioSistema usuarioLogado;

  @override
  State<RecadosLojaPage> createState() => _RecadosLojaPageState();
}

class _RecadosLojaPageState extends State<RecadosLojaPage>
    with SafeSyncRefreshMixin {
  late final RecadoLojaRepository _repo;
  List<RecadoLoja> _recados = [];
  String _filtro = 'ativos';
  static final _dataFmt = DateFormat('dd/MM/yyyy HH:mm', 'pt_BR');

  @override
  void initState() {
    super.initState();
    _repo = RecadoLojaRepository(widget.objectBox);
    initSafeSyncRefresh(onReload: _recarregar);
    _recarregar();
  }

  void _recarregar() {
    if (!mounted) return;
    setState(() => _recados = _repo.listarTodos());
  }

  List<RecadoLoja> get _visiveis {
    final u = widget.usuarioLogado;
    final login = u.login;
    switch (_filtro) {
      case 'nao_lidos':
        return _recados
            .where(
              (r) =>
                  r.ativo &&
                  RecadoLojaHelper.aplicaParaUsuario(r, u) &&
                  !RecadoLojaHelper.foiLido(r, login),
            )
            .toList();
      case 'arquivados':
        return _recados.where((r) => !r.ativo).toList();
      case 'todos':
        return _recados
            .where((r) => r.ativo && RecadoLojaHelper.aplicaParaUsuario(r, u))
            .toList();
      case 'ativos':
      default:
        return _repo.listarAtivosParaUsuario(u);
    }
  }

  Future<void> _novoRecado() async {
    final textoController = TextEditingController();
    var prioridade = RecadoLojaPrioridade.normal;
    var destinoTipo = RecadoLojaDestino.todos;
    var destinoPerfil = PerfilUsuarioPreset.caixa.id;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setLocal) {
            return AlertDialog(
              title: const Text('Novo recado'),
              content: SizedBox(
                width: 480,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextField(
                        controller: textoController,
                        maxLines: 4,
                        decoration: const InputDecoration(
                          labelText: 'Mensagem',
                          hintText: 'Ex.: Cliente retira pedido apos as 14h',
                          border: OutlineInputBorder(),
                        ),
                        autofocus: true,
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        value: prioridade,
                        decoration: const InputDecoration(
                          labelText: 'Prioridade',
                          border: OutlineInputBorder(),
                        ),
                        items: RecadoLojaPrioridade.todos
                            .map(
                              (p) => DropdownMenuItem(
                                value: p,
                                child: Text(RecadoLojaPrioridade.rotulo(p)),
                              ),
                            )
                            .toList(),
                        onChanged: (v) {
                          if (v == null) return;
                          setLocal(() => prioridade = v);
                        },
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        value: destinoTipo,
                        decoration: const InputDecoration(
                          labelText: 'Destino',
                          border: OutlineInputBorder(),
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: RecadoLojaDestino.todos,
                            child: Text('Toda a loja'),
                          ),
                          DropdownMenuItem(
                            value: RecadoLojaDestino.perfil,
                            child: Text('Um perfil'),
                          ),
                        ],
                        onChanged: (v) {
                          if (v == null) return;
                          setLocal(() => destinoTipo = v);
                        },
                      ),
                      if (destinoTipo == RecadoLojaDestino.perfil) ...[
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          value: destinoPerfil,
                          decoration: const InputDecoration(
                            labelText: 'Perfil',
                            border: OutlineInputBorder(),
                          ),
                          items: RecadoLojaDestino.perfisDisponiveis
                              .map(
                                (p) => DropdownMenuItem(
                                  value: p.id,
                                  child: Text(p.rotulo),
                                ),
                              )
                              .toList(),
                          onChanged: (v) {
                            if (v == null) return;
                            setLocal(() => destinoPerfil = v);
                          },
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancelar'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Publicar'),
                ),
              ],
            );
          },
        );
      },
    );

    if (ok != true) {
      textoController.dispose();
      return;
    }

    try {
      _repo.criar(
        texto: textoController.text,
        prioridade: prioridade,
        destinoTipo: destinoTipo,
        destinoPerfil: destinoPerfil,
        criadoPorLogin: widget.usuarioLogado.login,
        criadoPorNome: widget.usuarioLogado.nome,
      );
      _recarregar();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Recado publicado.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    } finally {
      textoController.dispose();
    }
  }

  void _marcarLido(RecadoLoja recado) {
    _repo.marcarLido(recado.id, widget.usuarioLogado.login);
    _recarregar();
  }

  Future<void> _arquivar(RecadoLoja recado) async {
    if (!RecadoLojaHelper.podeArquivar(recado, widget.usuarioLogado)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Somente quem criou ou gerente/dono pode arquivar.'),
        ),
      );
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Arquivar recado'),
        content: const Text('O recado deixara de aparecer para a equipe.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Arquivar'),
          ),
        ],
      ),
    );
    if (ok == true) {
      _repo.arquivar(recado.id);
      _recarregar();
    }
  }

  Future<void> _abrirManutencaoArquivados() async {
    if (!RecadoLojaHelper.podeManutencao(widget.usuarioLogado)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Manutencao disponivel para gerente ou dono.'),
        ),
      );
      return;
    }

    final qtd = _repo.contarArquivados();
    final acao = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Manutencao — arquivados'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Recados arquivados: $qtd\n\n'
                'A exclusao e permanente e replica na rede da loja.',
                style: Theme.of(ctx).textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: qtd <= 0 ? null : () => Navigator.pop(ctx, 'todos'),
                icon: const Icon(Icons.delete_sweep_outlined),
                label: Text('Apagar todos arquivados ($qtd)'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Fechar'),
          ),
        ],
      ),
    );
    if (acao != 'todos' || !mounted) return;

    final confirma = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Apagar arquivados'),
        content: Text(
          'Excluir permanentemente $qtd recado(s) arquivado(s)?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Voltar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Apagar tudo'),
          ),
        ],
      ),
    );
    if (confirma != true || !mounted) return;

    final n = _repo.apagarTodosArquivados();
    _recarregar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          n > 0 ? '$n recado(s) apagado(s).' : 'Nenhum recado arquivado.',
        ),
      ),
    );
  }

  Color _corPrioridade(BuildContext context, String prioridade) {
    switch (prioridade) {
      case RecadoLojaPrioridade.urgente:
        return Colors.red.shade700;
      case RecadoLojaPrioridade.importante:
        return Colors.orange.shade800;
      default:
        return Theme.of(context).colorScheme.primary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final u = widget.usuarioLogado;
    final lista = _visiveis;
    final naoLidos = _repo.contarNaoLidos(u);
    final arquivados = _repo.contarArquivados();
    final podeManutencao = RecadoLojaHelper.podeManutencao(u);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Recados da loja'),
        actions: [
          if (_filtro == 'arquivados' && podeManutencao)
            IconButton(
              tooltip: 'Manutencao — apagar arquivados',
              onPressed: _abrirManutencaoArquivados,
              icon: const Icon(Icons.build_outlined),
            ),
          if (naoLidos > 0)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Chip(
                label: Text('$naoLidos nao lido(s)'),
                visualDensity: VisualDensity.compact,
              ),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _novoRecado,
        icon: const Icon(Icons.add_comment_outlined),
        label: const Text('Novo recado'),
      ),
      body: Column(
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: Row(
              children: [
                _chipFiltro('Nao lidos', 'nao_lidos'),
                _chipFiltro('Ativos', 'ativos'),
                _chipFiltro('Todos', 'todos'),
                _chipFiltro('Arquivados', 'arquivados'),
              ],
            ),
          ),
          if (_filtro == 'arquivados' && podeManutencao) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: OutlinedButton.icon(
                onPressed: _abrirManutencaoArquivados,
                icon: const Icon(Icons.delete_sweep_outlined),
                label: Text(
                  arquivados > 0
                      ? 'Manutencao — apagar todos ($arquivados)'
                      : 'Manutencao — apagar arquivados',
                ),
              ),
            ),
          ],
          Expanded(
            child: lista.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        _filtro == 'nao_lidos'
                            ? 'Nenhum recado pendente de leitura.'
                            : _filtro == 'arquivados'
                                ? 'Nenhum recado arquivado.'
                                : 'Nenhum recado neste filtro.',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: lista.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final recado = lista[index];
                      final lido = RecadoLojaHelper.foiLido(recado, u.login);
                      final cor = _corPrioridade(context, recado.prioridade);
                      final autor = recado.criadoPorNome.trim().isNotEmpty
                          ? recado.criadoPorNome.trim()
                          : recado.criadoPorLogin;
                      return Card(
                        child: ListTile(
                          isThreeLine: true,
                          leading: CircleAvatar(
                            backgroundColor: cor.withValues(alpha: 0.15),
                            child: Icon(
                              lido
                                  ? Icons.mark_email_read_outlined
                                  : Icons.mark_email_unread_outlined,
                              color: cor,
                            ),
                          ),
                          title: Text(
                            recado.texto,
                            style: TextStyle(
                              fontWeight:
                                  lido ? FontWeight.w500 : FontWeight.w700,
                            ),
                          ),
                          subtitle: Text(
                            '${RecadoLojaPrioridade.rotulo(recado.prioridade)} · '
                            '${RecadoLojaDestino.rotuloTipo(recado.destinoTipo, recado.destinoPerfil)}\n'
                            '$autor · ${_dataFmt.format(recado.criadoEm.toLocal())}',
                          ),
                          trailing: PopupMenuButton<String>(
                            onSelected: (v) {
                              switch (v) {
                                case 'lido':
                                  _marcarLido(recado);
                                  break;
                                case 'arquivar':
                                  _arquivar(recado);
                                  break;
                              }
                            },
                            itemBuilder: (context) => [
                              if (!lido && recado.ativo)
                                const PopupMenuItem(
                                  value: 'lido',
                                  child: Text('Marcar como lido'),
                                ),
                              if (recado.ativo)
                                const PopupMenuItem(
                                  value: 'arquivar',
                                  child: Text('Arquivar'),
                                ),
                            ],
                          ),
                          onTap: () {
                            if (!lido && recado.ativo) _marcarLido(recado);
                          },
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _chipFiltro(String rotulo, String valor) {
    final sel = _filtro == valor;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Text(rotulo),
        selected: sel,
        onSelected: (_) => setState(() => _filtro = valor),
      ),
    );
  }
}
