import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../data/api/lan_api_event_hub.dart';
import '../../data/api/obrigacao_mensal_api_repository.dart';
import '../../data/obrigacao_mensal_fixa_repository.dart';
import '../../data/objectbox.dart';
import '../../model/obrigacao_mensal_fixa.dart';
import '../widgets/lan_api_feedback.dart';

final NumberFormat _moeda = NumberFormat.currency(locale: 'pt_BR', symbol: r'R$');

/// Cadastro de despesas fixas (semanal / mensal / anual).
///
/// Ao salvar ou ao abrir Contas a pagar, gera automaticamente a
/// [ContaPagar] do periodo corrente (sem duplicar).
class ObrigacoesMensaisPage extends StatefulWidget {
  const ObrigacoesMensaisPage({
    super.key,
    this.objectBox,
    this.obrigacaoRepository,
  }) : assert(
          objectBox != null || obrigacaoRepository != null,
          'Informe objectBox ou obrigacaoRepository',
        );

  final ObjectBox? objectBox;
  final dynamic obrigacaoRepository;

  @override
  State<ObrigacoesMensaisPage> createState() => _ObrigacoesMensaisPageState();
}

class _ObrigacoesMensaisPageState extends State<ObrigacoesMensaisPage> {
  late dynamic _repo;
  List<ObrigacaoMensalFixa> _itens = [];
  bool _carregando = true;

  @override
  void initState() {
    super.initState();
    _repo = widget.obrigacaoRepository ??
        (widget.objectBox != null
            ? ObrigacaoMensalFixaRepository(widget.objectBox!)
            : null);
    if (_repo == null) {
      throw StateError(
        'Obrigacoes fixas: informe obrigacaoRepository ou objectBox.',
      );
    }
    _recarregar();
  }

  Future<void> _recarregar() async {
    setState(() => _carregando = true);
    try {
      if (_repo is ObrigacaoMensalApiRepository) {
        if (!LanApiEventHub.instance.garantirOnlineOuAvisar(context)) {
          if (mounted) setState(() => _carregando = false);
          return;
        }
        await (_repo as ObrigacaoMensalApiRepository).hidratar();
      }
      final lista = (_repo.listar() as List).cast<ObrigacaoMensalFixa>();
      if (!mounted) return;
      setState(() {
        _itens = lista;
        _carregando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _carregando = false);
      LanApiFeedback.snackErro(
        context,
        e,
        prefixo: 'Falha ao carregar obrigacoes',
      );
    }
  }

  Future<void> _gerarAgora() async {
    try {
      final criadas = await _repo.gerarPendenciasRecentes() as int;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            criadas > 0
                ? '$criadas conta(s) gerada(s).'
                : 'Nenhuma conta nova — ja estavam geradas.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      LanApiFeedback.snackErro(context, e, prefixo: 'Falha ao gerar contas');
    }
  }

  Future<void> _abrirForm({ObrigacaoMensalFixa? existente}) async {
    final descCtrl = TextEditingController(text: existente?.descricao ?? '');
    final valorCtrl = TextEditingController(
      text: existente == null
          ? ''
          : existente.valor.toStringAsFixed(2).replaceAll('.', ','),
    );
    final diaCtrl = TextEditingController(
      text: '${existente?.diaVencimento ?? 10}',
    );
    final cnpjCtrl = TextEditingController(text: existente?.cnpj ?? '');
    var ativo = existente?.ativo ?? true;
    var periodicidade = ObrigacaoPeriodicidade.normalizar(
      existente?.periodicidade,
    );
    var diaSemana = (existente != null &&
            periodicidade == ObrigacaoPeriodicidade.semanal)
        ? existente.diaVencimento.clamp(1, 7)
        : DateTime.now().weekday;
    var mesAnual = existente?.mesVencimento.clamp(1, 12) ?? 1;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setLocal) {
            return AlertDialog(
              title: Text(
                existente == null ? 'Nova obrigacao fixa' : 'Editar obrigacao',
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: descCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Descricao / favorecido',
                        hintText: 'Ex.: Aluguel da loja',
                      ),
                      textCapitalization: TextCapitalization.sentences,
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      // ignore: deprecated_member_use
                      value: periodicidade,
                      decoration: const InputDecoration(
                        labelText: 'Periodicidade',
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: ObrigacaoPeriodicidade.semanal,
                          child: Text('Semanal'),
                        ),
                        DropdownMenuItem(
                          value: ObrigacaoPeriodicidade.mensal,
                          child: Text('Mensal'),
                        ),
                        DropdownMenuItem(
                          value: ObrigacaoPeriodicidade.anual,
                          child: Text('Anual'),
                        ),
                      ],
                      onChanged: (v) {
                        if (v == null) return;
                        setLocal(() {
                          periodicidade = v;
                          if (v == ObrigacaoPeriodicidade.semanal &&
                              (int.tryParse(diaCtrl.text) ?? 0) > 7) {
                            diaCtrl.text = '$diaSemana';
                          }
                          if (v != ObrigacaoPeriodicidade.semanal &&
                              (int.tryParse(diaCtrl.text) ?? 0) < 1) {
                            diaCtrl.text = '10';
                          }
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: valorCtrl,
                      decoration: InputDecoration(
                        labelText: periodicidade ==
                                ObrigacaoPeriodicidade.semanal
                            ? 'Valor semanal'
                            : periodicidade == ObrigacaoPeriodicidade.anual
                                ? 'Valor anual'
                                : 'Valor mensal',
                        prefixText: r'R$ ',
                      ),
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                          RegExp(r'[\d.,]'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (periodicidade == ObrigacaoPeriodicidade.semanal)
                      DropdownButtonFormField<int>(
                        // ignore: deprecated_member_use
                        value: diaSemana,
                        decoration: const InputDecoration(
                          labelText: 'Dia da semana',
                        ),
                        items: [
                          for (var d = 1; d <= 7; d++)
                            DropdownMenuItem(
                              value: d,
                              child: Text(
                                ObrigacaoMensalFixaRepository.nomeDiaSemana(d),
                              ),
                            ),
                        ],
                        onChanged: (v) {
                          if (v == null) return;
                          setLocal(() {
                            diaSemana = v;
                            diaCtrl.text = '$v';
                          });
                        },
                      )
                    else ...[
                      if (periodicidade == ObrigacaoPeriodicidade.anual) ...[
                        DropdownButtonFormField<int>(
                          // ignore: deprecated_member_use
                          value: mesAnual,
                          decoration: const InputDecoration(
                            labelText: 'Mes do vencimento',
                          ),
                          items: [
                            for (var m = 1; m <= 12; m++)
                              DropdownMenuItem(
                                value: m,
                                child: Text(
                                  ObrigacaoMensalFixaRepository.nomeMes(m),
                                ),
                              ),
                          ],
                          onChanged: (v) {
                            if (v == null) return;
                            setLocal(() => mesAnual = v);
                          },
                        ),
                        const SizedBox(height: 12),
                      ],
                      TextField(
                        controller: diaCtrl,
                        decoration: InputDecoration(
                          labelText: periodicidade ==
                                  ObrigacaoPeriodicidade.anual
                              ? 'Dia do mes (1–28)'
                              : 'Dia do vencimento (1–28)',
                          helperText:
                              'Se o mes tiver menos dias, usa o ultimo dia.',
                        ),
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                      ),
                    ],
                    const SizedBox(height: 12),
                    TextField(
                      controller: cnpjCtrl,
                      decoration: const InputDecoration(
                        labelText: 'CNPJ (opcional)',
                      ),
                      keyboardType: TextInputType.number,
                    ),
                    const SizedBox(height: 8),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        switch (periodicidade) {
                          ObrigacaoPeriodicidade.semanal =>
                            'Ativa (gera toda semana)',
                          ObrigacaoPeriodicidade.anual =>
                            'Ativa (gera todo ano)',
                          _ => 'Ativa (gera todo mes)',
                        },
                      ),
                      value: ativo,
                      onChanged: (v) => setLocal(() => ativo = v),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancelar'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Salvar'),
                ),
              ],
            );
          },
        );
      },
    );

    if (ok != true || !mounted) return;

    final valorTxt =
        valorCtrl.text.trim().replaceAll('.', '').replaceAll(',', '.');
    final valor = double.tryParse(valorTxt) ?? 0;
    final dia = periodicidade == ObrigacaoPeriodicidade.semanal
        ? diaSemana
        : (int.tryParse(diaCtrl.text.trim()) ?? 0);

    try {
      await _repo.salvar(
        id: existente?.id ?? 0,
        descricao: descCtrl.text,
        valor: valor,
        periodicidade: periodicidade,
        diaVencimento: dia,
        mesVencimento: mesAnual,
        cnpj: cnpjCtrl.text,
        ativo: ativo,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Salvo. Conta do periodo gerada automaticamente se estiver ativa.',
          ),
        ),
      );
      await _recarregar();
    } catch (e) {
      if (!mounted) return;
      LanApiFeedback.snackErro(context, e, prefixo: 'Nao foi possivel salvar');
    }
  }

  Future<void> _confirmarRemover(ObrigacaoMensalFixa o) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remover obrigacao?'),
        content: Text(
          'Remove o cadastro "${o.descricao}". '
          'Contas ja geradas em Contas a pagar nao sao excluidas.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remover'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await _repo.remover(o.id);
      await _recarregar();
    } catch (e) {
      if (!mounted) return;
      LanApiFeedback.snackErro(context, e, prefixo: 'Falha ao remover');
    }
  }

  String _avatarLabel(ObrigacaoMensalFixa o) {
    final p = ObrigacaoPeriodicidade.normalizar(o.periodicidade);
    switch (p) {
      case ObrigacaoPeriodicidade.semanal:
        return ObrigacaoMensalFixaRepository.nomeDiaSemana(o.diaVencimento)
            .substring(0, 3);
      case ObrigacaoPeriodicidade.anual:
        return o.mesVencimento.toString().padLeft(2, '0');
      default:
        return '${o.diaVencimento}';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Obrigacoes fixas'),
        actions: [
          IconButton(
            tooltip: 'Gerar contas do periodo agora',
            onPressed: _gerarAgora,
            icon: const Icon(Icons.playlist_add_check_outlined),
          ),
          IconButton(
            tooltip: 'Atualizar',
            onPressed: _recarregar,
            icon: const Icon(Icons.refresh_outlined),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _abrirForm(),
        icon: const Icon(Icons.add),
        label: const Text('Nova obrigacao'),
      ),
      body: _carregando
          ? const Center(child: CircularProgressIndicator())
          : _itens.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'Nenhuma obrigacao cadastrada.\n'
                      'Cadastre aluguel (mensal), taxa semanal, licenca anual, etc. '
                      'A conta aparece em Contas a pagar no periodo correspondente.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyLarge,
                    ),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
                  itemCount: _itens.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, i) {
                    final o = _itens[i];
                    return Card(
                      child: ListTile(
                        leading: CircleAvatar(
                          child: Text(
                            _avatarLabel(o),
                            style: const TextStyle(fontSize: 11),
                          ),
                        ),
                        title: Text(o.descricao),
                        subtitle: Text(
                          '${ObrigacaoPeriodicidade.rotulo(o.periodicidade)} · '
                          '${ObrigacaoMensalFixaRepository.resumoVencimento(o)} · '
                          '${o.ativo ? 'Ativa' : 'Inativa'}'
                          '${o.cnpj.isNotEmpty ? ' · CNPJ ${o.cnpj}' : ''}',
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _moeda.format(o.valor),
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            IconButton(
                              tooltip: 'Editar',
                              onPressed: () => _abrirForm(existente: o),
                              icon: const Icon(Icons.edit_outlined),
                            ),
                            IconButton(
                              tooltip: 'Remover',
                              onPressed: () => _confirmarRemover(o),
                              icon: const Icon(Icons.delete_outline),
                            ),
                          ],
                        ),
                        onTap: () => _abrirForm(existente: o),
                      ),
                    );
                  },
                ),
    );
  }
}
