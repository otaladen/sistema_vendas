import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../model/cliente.dart';
import '../../layout/app_layout.dart';
import '../../widgets/mascaras_cadastro_input.dart';

/// Valores especiais retornados por [mostrarSelecionarClientePdvDialog].
const int kSelecionarClienteSemCliente = -1;
const int kSelecionarClienteNovoCadastro = -2;
const int kSelecionarClienteSomenteCotacao = -3;

typedef FiltrarClientesPdv = List<Cliente> Function(String termo);

typedef AgendarPesquisaClienteRemotaPdv = void Function({
  required String termo,
  required VoidCallback aoConcluir,
  required void Function(Timer timer) registrarDebounce,
});

Future<int?> mostrarSelecionarClientePdvDialog(
  BuildContext context, {
  required String titulo,
  required bool permitirSemCliente,
  required bool mostrarOpcaoSomenteCotacao,
  required bool somenteCotacaoInicial,
  required FiltrarClientesPdv filtrarClientes,
  AgendarPesquisaClienteRemotaPdv? agendarPesquisaRemota,
}) {
  return showDialog<int>(
    context: context,
    builder: (dialogContext) => _SelecionarClienteDialog(
      titulo: titulo,
      permitirSemCliente: permitirSemCliente,
      mostrarOpcaoSomenteCotacao: mostrarOpcaoSomenteCotacao,
      somenteCotacaoInicial: somenteCotacaoInicial,
      filtrarClientes: filtrarClientes,
      agendarPesquisaRemota: agendarPesquisaRemota,
    ),
  );
}

bool nomeClientePareceInvalidoParaExibicao(String texto) {
  final t = texto.trim();
  if (t.isEmpty) return true;
  final apenasDigitos = somenteDigitos(t);
  if (apenasDigitos.isEmpty) return false;
  final compacto = t.replaceAll(RegExp(r'\s'), '');
  if (RegExp(r'^[\d.\-/]+$').hasMatch(compacto)) return true;
  return false;
}

String nomeExibicaoClienteListaPdv(Cliente cliente) {
  final razao = cliente.nomeRazao.trim();
  final fantasia = cliente.nomeFantasia.trim();

  if (!nomeClientePareceInvalidoParaExibicao(razao)) {
    return razao;
  }
  if (!nomeClientePareceInvalidoParaExibicao(fantasia)) {
    return fantasia;
  }
  return 'Nome não informado';
}

String formatarDocumentoClienteExibicao(Cliente cliente) {
  final bruto = cliente.documento.trim();
  if (bruto.isEmpty) return '';
  final digitos = somenteDigitos(bruto);
  if (digitos.isEmpty) return bruto;

  if (digitos.length == 11) {
    return CpfInputFormatter().formatEditUpdate(
      TextEditingValue.empty,
      TextEditingValue(text: digitos),
    ).text;
  }
  if (digitos.length == 14) {
    return CnpjInputFormatter().formatEditUpdate(
      TextEditingValue.empty,
      TextEditingValue(text: digitos),
    ).text;
  }
  return bruto;
}

String formatarTelefoneClienteExibicao(String telefone) {
  final bruto = telefone.trim();
  if (bruto.isEmpty) return '';
  final digitos = somenteDigitos(bruto);
  if (digitos.isEmpty) return bruto;
  return TelefoneInputFormatter().formatEditUpdate(
    TextEditingValue.empty,
    TextEditingValue(text: digitos),
  ).text;
}

String? subtituloClienteListaPdv(Cliente cliente) {
  final partes = <String>[];
  final doc = formatarDocumentoClienteExibicao(cliente);
  if (doc.isNotEmpty) partes.add(doc);
  final tel = formatarTelefoneClienteExibicao(cliente.telefone);
  if (tel.isNotEmpty) partes.add(tel);
  if (partes.isEmpty) return null;
  return partes.join(' · ');
}

bool clienteEhPessoaJuridica(Cliente cliente) {
  final digitos = somenteDigitos(cliente.documento);
  if (digitos.length == 14) return true;
  return cliente.tipoPessoa.trim().toLowerCase() == 'juridica';
}

String iniciaisAvatarClientePdv(Cliente cliente) {
  final nome = nomeExibicaoClienteListaPdv(cliente);
  if (nome == 'Nome não informado') return '';
  final partes =
      nome.split(RegExp(r'\s+')).where((p) => p.trim().isNotEmpty).toList();
  if (partes.isEmpty) return '';
  if (partes.length == 1) {
    final p = partes.first;
    return p.substring(0, math.min(2, p.length)).toUpperCase();
  }
  return '${partes.first[0]}${partes.last[0]}'.toUpperCase();
}

class _SelecionarClienteDialog extends StatefulWidget {
  const _SelecionarClienteDialog({
    required this.titulo,
    required this.permitirSemCliente,
    required this.mostrarOpcaoSomenteCotacao,
    required this.somenteCotacaoInicial,
    required this.filtrarClientes,
    this.agendarPesquisaRemota,
  });

  final String titulo;
  final bool permitirSemCliente;
  final bool mostrarOpcaoSomenteCotacao;
  final bool somenteCotacaoInicial;
  final FiltrarClientesPdv filtrarClientes;
  final AgendarPesquisaClienteRemotaPdv? agendarPesquisaRemota;

  @override
  State<_SelecionarClienteDialog> createState() =>
      _SelecionarClienteDialogState();
}

class _SelecionarClienteDialogState extends State<_SelecionarClienteDialog> {
  late final TextEditingController _pesquisaController;
  late final FocusNode _pesquisaFocusNode;
  late final ScrollController _listaScrollController;
  late List<Cliente> _filtrados;
  late bool _somenteCotacao;
  final ValueNotifier<int> _indiceSelecionado = ValueNotifier(-1);
  Timer? _debounceApi;
  bool _fechando = false;

  @override
  void initState() {
    super.initState();
    _pesquisaController = TextEditingController();
    _pesquisaFocusNode = FocusNode();
    _listaScrollController = ScrollController();
    _filtrados = widget.filtrarClientes('');
    _somenteCotacao = widget.somenteCotacaoInicial;
    _indiceSelecionado.value = _filtrados.isEmpty ? -1 : 0;
  }

  @override
  void dispose() {
    _debounceApi?.cancel();
    _indiceSelecionado.dispose();
    _pesquisaController.dispose();
    _pesquisaFocusNode.dispose();
    _listaScrollController.dispose();
    super.dispose();
  }

  void _fechar(int? valor) {
    if (_fechando) return;
    _fechando = true;
    Navigator.of(context).pop(valor);
  }

  void _confirmarCliente(int id) => _fechar(id);

  void _rolarParaIndiceSelecionado() {
    final indice = _indiceSelecionado.value;
    if (!_listaScrollController.hasClients || indice < 0) return;
    const alturaLinha = 72.0;
    final posicao = (indice * alturaLinha).clamp(
      0.0,
      _listaScrollController.position.maxScrollExtent,
    );
    _listaScrollController.animateTo(
      posicao,
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeOut,
    );
  }

  void _definirIndiceSelecionado(int indice) {
    if (_indiceSelecionado.value == indice) return;
    _indiceSelecionado.value = indice;
  }

  void _atualizarBusca(String value) {
    final termo = value;
    setState(() {
      _filtrados = widget.filtrarClientes(termo);
      _indiceSelecionado.value = _filtrados.isEmpty ? -1 : 0;
    });

    final agendar = widget.agendarPesquisaRemota;
    if (agendar == null || termo.trim().isEmpty) return;

    agendar(
      termo: termo.trim(),
      aoConcluir: () {
        if (!mounted) return;
        setState(() {
          _filtrados = widget.filtrarClientes(_pesquisaController.text);
          _indiceSelecionado.value = _filtrados.isEmpty ? -1 : 0;
        });
      },
      registrarDebounce: (timer) {
        _debounceApi?.cancel();
        _debounceApi = timer;
      },
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_listaScrollController.hasClients) {
        _listaScrollController.jumpTo(0);
      }
    });
  }

  KeyEventResult _tratarTeclasLista(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    if (event.logicalKey == LogicalKeyboardKey.escape) {
      _fechar(null);
      return KeyEventResult.handled;
    }

    if (_filtrados.isEmpty) return KeyEventResult.ignored;

    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      _moverIndiceLista(1);
      return KeyEventResult.handled;
    }

    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      _moverIndiceLista(-1);
      return KeyEventResult.handled;
    }

    if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter) {
      final indice =
          _indiceSelecionado.value >= 0 ? _indiceSelecionado.value : 0;
      _confirmarCliente(_filtrados[indice].id);
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  void _moverIndiceLista(int delta) {
    if (_filtrados.isEmpty) return;
    final atual = _indiceSelecionado.value;
    final max = _filtrados.length - 1;
    final novo = delta > 0
        ? (atual < 0 ? 0 : math.min(atual + 1, max))
        : (atual < 0 ? 0 : math.max(atual - 1, 0));
    _definirIndiceSelecionado(novo);
    _rolarParaIndiceSelecionado();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final corDestaque = scheme.primaryContainer.withValues(alpha: 0.45);
    final corBordaFoco = scheme.primary.withValues(alpha: 0.65);

    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.arrowDown): () {
          if (_filtrados.isNotEmpty) _moverIndiceLista(1);
        },
        const SingleActivator(LogicalKeyboardKey.arrowUp): () {
          if (_filtrados.isNotEmpty) _moverIndiceLista(-1);
        },
        const SingleActivator(LogicalKeyboardKey.escape): () => _fechar(null),
      },
      child: Focus(
        onKeyEvent: _tratarTeclasLista,
        child: AlertDialog(
        title: Text(widget.titulo),
        content: AdaptiveDialogPane(
          desktopWidth: 680,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (widget.mostrarOpcaoSomenteCotacao) ...[
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _somenteCotacao,
                  onChanged: (v) => setState(() => _somenteCotacao = v),
                  title: const Text('Só cotação (sem cadastro de cliente)'),
                  subtitle: const Text(
                    'Cliente apenas cotando preços. '
                    'Endereço e dados ficam para depois.',
                  ),
                ),
                const SizedBox(height: 8),
              ],
              Focus(
                onKeyEvent: _tratarTeclasLista,
                child: TextField(
                  controller: _pesquisaController,
                  focusNode: _pesquisaFocusNode,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'Buscar por nome, documento, telefone...',
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Setas para navegar · Enter para confirmar',
                  ),
                  onChanged: _atualizarBusca,
                  onSubmitted: (_) {
                    if (_filtrados.isEmpty) return;
                    final indice = _indiceSelecionado.value >= 0
                        ? _indiceSelecionado.value
                        : 0;
                    _confirmarCliente(_filtrados[indice].id);
                  },
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (widget.permitirSemCliente)
                    ActionChip(
                      avatar: Icon(
                        Icons.person_off_outlined,
                        size: 18,
                        color: scheme.onSecondaryContainer,
                      ),
                      label: const Text('Consumidor final'),
                      tooltip: 'Venda sem cliente cadastrado',
                      visualDensity: VisualDensity.compact,
                      onPressed: () =>
                          _fechar(kSelecionarClienteSemCliente),
                    ),
                  ActionChip(
                    avatar: Icon(
                      Icons.person_add_alt_1_outlined,
                      size: 18,
                      color: scheme.onPrimaryContainer,
                    ),
                    label: const Text('Novo cadastro'),
                    visualDensity: VisualDensity.compact,
                    onPressed: () => _fechar(kSelecionarClienteNovoCadastro),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Divider(height: 1),
              const SizedBox(height: 8),
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: adaptiveDialogListMaxHeight(
                    context,
                    desktopFactor: 0.45,
                    mobileFactor: 0.38,
                  ),
                ),
                child: _filtrados.isEmpty
                    ? const Center(
                        child: Padding(
                          padding: EdgeInsets.all(16),
                          child: Text('Nenhum cliente encontrado.'),
                        ),
                      )
                    : ListView.builder(
                        controller: _listaScrollController,
                        shrinkWrap: true,
                        itemCount: _filtrados.length,
                        itemExtent: 72,
                        cacheExtent: 280,
                        itemBuilder: (context, index) {
                          final cliente = _filtrados[index];
                          return _ClienteListaLinha(
                            cliente: cliente,
                            indice: index,
                            indiceSelecionado: _indiceSelecionado,
                            corDestaque: corDestaque,
                            corBordaFoco: corBordaFoco,
                            onHover: () => _definirIndiceSelecionado(index),
                            onTap: () => _confirmarCliente(cliente.id),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => _fechar(null),
            child: const Text('Cancelar'),
          ),
          if (widget.mostrarOpcaoSomenteCotacao)
            FilledButton(
              onPressed: _somenteCotacao
                  ? () => _fechar(kSelecionarClienteSomenteCotacao)
                  : null,
              child: const Text('Avançar'),
            ),
        ],
      ),
      ),
    );
  }
}

class _ClienteListaLinha extends StatefulWidget {
  const _ClienteListaLinha({
    required this.cliente,
    required this.indice,
    required this.indiceSelecionado,
    required this.corDestaque,
    required this.corBordaFoco,
    required this.onHover,
    required this.onTap,
  });

  final Cliente cliente;
  final int indice;
  final ValueNotifier<int> indiceSelecionado;
  final Color corDestaque;
  final Color corBordaFoco;
  final VoidCallback onHover;
  final VoidCallback onTap;

  @override
  State<_ClienteListaLinha> createState() => _ClienteListaLinhaState();
}

class _ClienteListaLinhaState extends State<_ClienteListaLinha> {
  late bool _selecionado;

  @override
  void initState() {
    super.initState();
    _selecionado = widget.indiceSelecionado.value == widget.indice;
    widget.indiceSelecionado.addListener(_aoMudarSelecao);
  }

  @override
  void didUpdateWidget(covariant _ClienteListaLinha oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.indiceSelecionado != widget.indiceSelecionado) {
      oldWidget.indiceSelecionado.removeListener(_aoMudarSelecao);
      widget.indiceSelecionado.addListener(_aoMudarSelecao);
    }
    final agora = widget.indiceSelecionado.value == widget.indice;
    if (agora != _selecionado) _selecionado = agora;
  }

  @override
  void dispose() {
    widget.indiceSelecionado.removeListener(_aoMudarSelecao);
    super.dispose();
  }

  void _aoMudarSelecao() {
    final agora = widget.indiceSelecionado.value == widget.indice;
    if (agora == _selecionado) return;
    setState(() => _selecionado = agora);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final juridica = clienteEhPessoaJuridica(widget.cliente);
    final iniciais = iniciaisAvatarClientePdv(widget.cliente);
    final titulo = nomeExibicaoClienteListaPdv(widget.cliente);
    final subtitulo = subtituloClienteListaPdv(widget.cliente);

    return MouseRegion(
      onEnter: (_) => widget.onHover(),
      child: Material(
        color: _selecionado ? widget.corDestaque : Colors.transparent,
        child: InkWell(
          onTap: widget.onTap,
          child: Container(
            height: 72,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(
                  color: _selecionado ? widget.corBordaFoco : Colors.transparent,
                  width: 3,
                ),
              ),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: _selecionado
                      ? scheme.primary
                      : scheme.secondaryContainer,
                  foregroundColor: _selecionado
                      ? scheme.onPrimary
                      : scheme.onSecondaryContainer,
                  child: iniciais.isNotEmpty
                      ? Text(
                          iniciais,
                          style: theme.textTheme.labelLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        )
                      : Icon(
                          juridica
                              ? Icons.business_rounded
                              : Icons.person_outline_rounded,
                          size: 22,
                        ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        titulo,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight:
                              _selecionado ? FontWeight.w600 : FontWeight.w500,
                        ),
                      ),
                      if (subtitulo != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitulo,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
