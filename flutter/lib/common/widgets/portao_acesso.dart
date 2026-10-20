import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/common/widgets/login.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:get/get.dart';

// PCNET-IT: portao de acesso do tecnico.
//
// POR QUE EXISTE
// Um tecnico que saia da empresa leva consigo uma copia do programa. O console
// ja sabe desativar a conta (`is_active = false` em console_users) e ja responde
// a isso em POST /api/currentUser com 401. O que faltava era o programa EXIGIR
// essa resposta antes de deixar usar.
//
// SAO DOIS PORTOES, E A DIFERENCA IMPORTA
//
//   1. PORTAO DA LIGACAO (kExigirLoginParaLigar, LIGADO por omissao)
//      Guarda a ACCAO de ligar a outra maquina, dentro de connect() em
//      common.dart -- o unico sitio por onde passam os 7 pontos de entrada da
//      interface (caixa de ID, cartao de par, barra da sessao, movel).
//      E' seguro ter isto ligado em TODAS as builds: uma maquina de cliente
//      nunca liga para fora, logo nunca encontra este portao. As 23 maquinas
//      ja' instaladas continuam a abrir e a mostrar ID e senha como sempre.
//
//   2. PORTAO DA JANELA (kPortaoJanela, DESLIGADO por omissao)
//      Nao deixa a janela principal abrir sem sessao. E' o que o dono pediu
//      para a app do tecnico: ve-se a tela de entrada mal se abre o programa.
//      Fica DESLIGADO por omissao de proposito -- hoje existe uma build so,
//      e ela corre nas maquinas dos CLIENTES. Liga-la por omissao trancaria
//      as 23 maquinas em producao a mostrar um login que o cliente nao tem
//      como passar. Liga-se com --dart-define=PCNET_PORTAO_JANELA=true na
//      build do tecnico, quando ela existir.
//
// O QUE ISTO E, E O QUE NAO E
// Isto e' a PORTA: o tecnico ve "conta desativada" e percebe o que aconteceu.
// NAO e' a fechadura. Quem remendar o binario, editar a configuracao a mao ou
// usar `--connect <id>` pela linha de comandos passa a` volta, porque este `if`
// corre na maquina dele. A fechadura e' o servidor de ID recusar o token que ja
// viaja em PunchHoleRequest.token (campo 5) e RequestRelay.token (campo 8).
//
// QUEDA DE REDE NAO TRANCA NINGUEM, DE PROPOSITO
// `refreshCurrentUser()` so chama `reset()` quando o console responde 401 ou
// 400; se a ligacao falhar, escreve em `networkError` e deixa a sessao como
// esta' (user_model.dart:76-94). Um console em baixo nao pode parar a equipa
// toda. O custo honesto e' que um tecnico ja' autenticado, se ficar sem rede,
// continua a trabalhar ate' voltar a ligar-se.

/// Guarda a accao de ligar a outra maquina. Ligado por omissao: uma maquina de
/// cliente nunca liga para fora, por isso nao e' afectada.
const bool kExigirLoginParaLigar =
    bool.fromEnvironment('PCNET_EXIGIR_LOGIN', defaultValue: true);

/// Nao deixa a janela principal abrir sem sessao. DESLIGADO por omissao: ver a
/// nota acima sobre as 23 maquinas em producao.
const bool kPortaoJanela =
    bool.fromEnvironment('PCNET_PORTAO_JANELA', defaultValue: false);

/// De quanto em quanto tempo se pergunta ao console se a conta ainda vale.
///
/// O token do console dura 12 h, por isso esperar por ele seria tarde demais.
/// Cinco minutos sao ~288 pedidos por dia e por tecnico -- barato -- e e' o
/// atraso maximo entre desativar a conta no console e a app trancar sozinha.
const Duration _intervaloRevalidacao = Duration(minutes: 5);

/// `isIncomingOnly()` e' cinto e suspensorios: uma build marcada como "so
/// recebe ligacoes" nao tem caixa de ligar, logo nao ha nada que proteger.
bool get _portaoAplicavel => !bind.isIncomingOnly();

/// Ha sessao valida neste momento?
bool get temSessao => gFFI.userModel.userName.value.isNotEmpty;

/// Chamado no topo de `connect()`. Devolve `true` se a ligacao pode seguir.
///
/// Se nao houver sessao, abre o ecra de entrada e espera; o tecnico entra e a
/// ligacao continua sem ele ter de repetir o ID.
Future<bool> podeLigar() async {
  if (!kExigirLoginParaLigar || !_portaoAplicavel) return true;
  if (temSessao) return true;
  await loginDialog();
  return temSessao;
}

/// Envolve a janela principal. So faz alguma coisa quando kPortaoJanela esta
/// ligado (build do tecnico).
class PortaoAcesso extends StatefulWidget {
  const PortaoAcesso({Key? key, required this.filho}) : super(key: key);

  final Widget filho;

  @override
  State<PortaoAcesso> createState() => _PortaoAcessoState();
}

class _PortaoAcessoState extends State<PortaoAcesso> {
  Timer? _relogio;

  bool get _activo => kPortaoJanela && _portaoAplicavel;

  @override
  void initState() {
    super.initState();
    if (!kExigirLoginParaLigar || !_portaoAplicavel) return;
    // O relogio corre mesmo com o portao da janela desligado: e' ele que faz a
    // sessao de um tecnico despedido cair dentro de 5 minutos, e e' a mesma
    // queda que fecha o portao da ligacao.
    //
    // O arranque ja' chama refreshCurrentUser() uma vez (main.dart, runMainApp).
    _relogio = Timer.periodic(
        _intervaloRevalidacao, (_) => gFFI.userModel.refreshCurrentUser());
  }

  @override
  void dispose() {
    _relogio?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_activo) return widget.filho;
    return Obx(() =>
        temSessao ? widget.filho : const EcraDeEntrada());
  }
}

/// A tela que o tecnico ve quando nao ha sessao.
class EcraDeEntrada extends StatefulWidget {
  const EcraDeEntrada({Key? key}) : super(key: key);

  @override
  State<EcraDeEntrada> createState() => _EcraDeEntradaState();
}

class _EcraDeEntradaState extends State<EcraDeEntrada> {
  bool _aAbrir = false;

  Future<void> _entrar() async {
    if (_aAbrir) return;
    setState(() => _aAbrir = true);
    try {
      await loginDialog();
    } finally {
      if (mounted) setState(() => _aAbrir = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(Icons.lock_outline,
                    size: 48, color: tema.colorScheme.primary),
                const SizedBox(height: 20),
                Text(
                  bind.mainGetAppNameSync(),
                  textAlign: TextAlign.center,
                  style: tema.textTheme.titleLarge,
                ),
                const SizedBox(height: 10),
                Text(
                  translate('pcnet_login_required_tip'),
                  textAlign: TextAlign.center,
                  style: tema.textTheme.bodyMedium
                      ?.copyWith(color: tema.hintColor),
                ),
                const SizedBox(height: 24),
                // Distinguir "console inacessivel" de "conta recusada" e' o que
                // evita o tecnico ligar a dizer "nao entra" quando o problema e'
                // a internet dele.
                Obx(() {
                  if (gFFI.userModel.networkError.value.isEmpty) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Text(
                      translate('pcnet_login_offline_tip'),
                      textAlign: TextAlign.center,
                      style: tema.textTheme.bodySmall
                          ?.copyWith(color: tema.colorScheme.error),
                    ),
                  );
                }),
                ElevatedButton(
                  onPressed: _aAbrir ? null : _entrar,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(translate('Login')),
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
