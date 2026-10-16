import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:url_launcher/url_launcher.dart';

// PCNET-IT: painel unico das permissoes do macOS.
//
// Antes aparecia um cartao de cada vez na coluna da esquerda da pagina inicial
// (Gravacao de Ecra -> Acessibilidade -> Monitorizacao de Entrada -> Instalar),
// e cada um so aparecia depois de o anterior estar satisfeito: o tecnico nunca
// sabia quantas faltavam nem se ja tinha acabado. Aqui estao as tres ao mesmo
// tempo, cada uma com o seu estado (verde / vermelho) e o seu botao, e o painel
// le-as sozinho enquanto o tecnico anda nas Definicoes do macOS.
//
// O microfone fica de fora de proposito: nao e obrigatorio e a app pede-o
// quando precisa dele (osxCanRecordAudio / PermissionAuthorizeType).

/// As permissoes obrigatorias para a maquina poder ser controlada.
enum MacPermission {
  screenRecording,
  accessibility,
  inputMonitoring,
}

class _MacPermissionRow {
  const _MacPermissionRow(
      this.permission, this.titleKey, this.descKey, this.icon);

  final MacPermission permission;
  final String titleKey;
  final String descKey;
  final IconData icon;
}

const _macPermissionRows = <_MacPermissionRow>[
  _MacPermissionRow(MacPermission.screenRecording, 'Screen Recording',
      'mac-permissions-screen-desc', Icons.screen_share_outlined),
  _MacPermissionRow(MacPermission.accessibility, 'Accessibility',
      'mac-permissions-acc-desc', Icons.touch_app),
  _MacPermissionRow(MacPermission.inputMonitoring, 'Input Monitoring',
      'mac-permissions-input-desc', Icons.keyboard),
];

/// Em builds "outgoing only" (so controlam, nunca sao controladas) a Gravacao
/// de Ecra e a Acessibilidade nao fazem sentido -- e o que a cadeia de cartoes
/// ja fazia, so a Monitorizacao de Entrada era pedida sempre.
bool _isRequired(MacPermission p) =>
    p == MacPermission.inputMonitoring || !bind.isOutgoingOnly();

/// As permissoes que este build precisa, pela ordem em que aparecem.
List<MacPermission> macPermissionsRequired() => _macPermissionRows
    .map((r) => r.permission)
    .where(_isRequired)
    .toList();

/// Le o estado real da permissao. Com prompt: false nao abre nada.
bool macPermissionGranted(MacPermission p) {
  if (p == MacPermission.screenRecording) {
    return bind.mainIsCanScreenRecording(prompt: false);
  }
  if (p == MacPermission.accessibility) {
    return bind.mainIsProcessTrusted(prompt: false);
  }
  return bind.mainIsCanInputMonitoring(prompt: false);
}

/// Com prompt: true o macOS abre o painel certo das Definicoes. A chamada
/// devolve de imediato e o valor devolvido nao diz nada de util -- foi
/// exactamente esse o defeito do cartao "Instalar" (corrigido com
/// watchIsInstalledDaemon), por isso aqui e ignorado de proposito. Quem le o
/// estado e o temporizador do painel, de segundo a segundo.
void macPermissionRequest(MacPermission p) {
  if (p == MacPermission.screenRecording) {
    bind.mainIsCanScreenRecording(prompt: true);
  } else if (p == MacPermission.accessibility) {
    bind.mainIsProcessTrusted(prompt: true);
  } else {
    bind.mainIsCanInputMonitoring(prompt: true);
  }
}

/// A Gravacao de Ecra e a Monitorizacao de Entrada so ficam mesmo activas
/// depois de a app sair e reabrir: o TCC do macOS guarda a resposta por
/// processo (CGPreflightScreenCaptureAccess / IOHIDCheckAccess), e e por isso
/// que o proprio macOS pede "Quit & Reopen" quando se marca a opcao. A
/// Acessibilidade (AXIsProcessTrusted) e lida ao vivo. Daqui sai o aviso do
/// painel, para o tecnico nao ficar a olhar para uma linha vermelha sem saber
/// porque.
bool macPermissionNeedsRestart(MacPermission p) =>
    p == MacPermission.screenRecording || p == MacPermission.inputMonitoring;

bool macPermissionsAllGranted() {
  if (!isMacOS) {
    return true;
  }
  for (final p in macPermissionsRequired()) {
    if (!macPermissionGranted(p)) {
      return false;
    }
  }
  return true;
}

const String kMacPermissionsDialogTag = 'pcnet-mac-permissions';

bool _isOpen = false;

bool isMacPermissionsDialogOpen() => _isOpen;

/// Fecha o painel a pedido de quem o abriu (o dispose da pagina inicial). O
/// futuro de [showMacPermissionsDialog] completa com null, que nao conta como
/// fecho a mao.
void dismissMacPermissionsDialog() {
  if (_isOpen) {
    gFFI.dialogManager.dismissByTag(kMacPermissionsDialogTag);
  }
}

/// PCNET-IT: builds personalizados podem esconder os cartoes de ajuda. Nesse
/// caso o painel nao abre -- e quem o tenta abrir tem de saber disso ANTES,
/// senao fica a pedir a abertura a cada segundo e a reconstruir a pagina.
bool macPermissionsPanelSuppressed() =>
    bind.mainGetBuildinOption(key: kOptionHideHelpCards) == 'Y';

/// Abre o painel (uma instancia, no maximo) e diz como foi fechado:
///   true  -> ficaram todas concedidas e o painel saiu sozinho;
///   false -> foi o tecnico a fecha-lo com alguma a faltar;
///   null  -> nao abriu, ou foi fechado por fora (um msgBox faz dismissAll).
/// Nunca lanca: quem chama trata so do resultado.
Future<bool?> showMacPermissionsDialog() async {
  if (!isMacOS || _isOpen) {
    return null;
  }
  // Nas instalacoes que escondem os cartoes de ajuda tambem nao se abre o
  // painel, pelo mesmo motivo (e o mesmo que buildInstallCard respeita).
  if (bind.mainGetBuildinOption(key: kOptionHideHelpCards) == 'Y') {
    return null;
  }
  _isOpen = true;
  try {
    return await gFFI.dialogManager.show<bool>(
      (setState, close, context) {
        return CustomAlertDialog(
          title: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.shield_outlined, color: MyTheme.accent),
              Padding(
                padding: const EdgeInsets.only(left: 10),
                child: Text(translate('mac-permissions-title')),
              ),
            ],
          ),
          contentBoxConstraints: const BoxConstraints(maxWidth: 560),
          content: _MacPermissionsPanel(onCompleted: () => close(true)),
          actions: [
            TextButton(
              onPressed: () async {
                await launchUrl(Uri.parse(translate('doc_mac_permission')));
              },
              child: Text(translate('Help')),
            ),
            dialogButton('Close',
                onPressed: () => close(false), isOutline: true),
          ],
          // Esc fecha, como em qualquer dialogo desta app: nunca encurralar o
          // tecnico neste painel.
          onCancel: () => close(false),
        );
      },
      tag: kMacPermissionsDialogTag,
      clickMaskDismiss: false,
      backDismiss: false,
    );
  } catch (e) {
    debugPrint('showMacPermissionsDialog falhou: $e');
    return null;
  } finally {
    _isOpen = false;
  }
}

class _MacPermissionsPanel extends StatefulWidget {
  const _MacPermissionsPanel({Key? key, required this.onCompleted})
      : super(key: key);

  final VoidCallback onCompleted;

  @override
  State<_MacPermissionsPanel> createState() => _MacPermissionsPanelState();
}

class _MacPermissionsPanelState extends State<_MacPermissionsPanel> {
  Timer? _timer;
  final Map<MacPermission, bool> _granted = {};
  // permissoes em que o tecnico ja clicou em Configurar e que ainda podem
  // precisar de um reinicio da app para fazerem efeito
  final Set<MacPermission> _requestedNeedRestart = {};
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    for (final p in macPermissionsRequired()) {
      _granted[p] = macPermissionGranted(p);
    }
    // Temporizador proprio, com o mesmo periodo de 1 s do da pagina inicial.
    // Nao se reaproveita o de la porque o painel vive no Overlay, numa arvore
    // separada da pagina: o setState da pagina nao reconstroi este widget. E
    // morre no dispose, com o painel -- o da pagina continua a servir o aviso
    // da coluna da esquerda.
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _refresh());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _refresh() {
    if (!mounted) {
      return;
    }
    var changed = false;
    for (final p in macPermissionsRequired()) {
      final granted = macPermissionGranted(p);
      if (_granted[p] != granted) {
        _granted[p] = granted;
        changed = true;
      }
      // O aviso de "tem de sair e reabrir" deixa de fazer sentido assim que a
      // linha fica verde -- deixa-lo la era a confusao que este painel existe
      // para eliminar.
      if (granted && _requestedNeedRestart.remove(p)) {
        changed = true;
      }
    }
    if (!_closing && _allGranted) {
      _closing = true;
      changed = true;
      // Deixa o tecnico ver as tres a verde antes de o painel sair do ecra.
      Future.delayed(const Duration(milliseconds: 1500), () {
        if (mounted) {
          widget.onCompleted();
        }
      });
    }
    if (changed) {
      setState(() {});
    }
  }

  bool get _allGranted =>
      macPermissionsRequired().every((p) => _granted[p] == true);

  int get _grantedCount =>
      macPermissionsRequired().where((p) => _granted[p] == true).length;

  @override
  Widget build(BuildContext context) {
    final requiredPerms = macPermissionsRequired();
    // Em janelas estreitas (build "incoming only") o botao passa para baixo do
    // texto, em vez de espremer a coluna do meio.
    final narrow = MediaQuery.of(context).size.width < 460;
    final children = <Widget>[
      Text(
        translate('mac-permissions-tip'),
        style: const TextStyle(fontSize: 13, height: 1.5),
      ),
      const SizedBox(height: 14),
      Text(
        '${translate('mac-permissions-progress')}: $_grantedCount/${requiredPerms.length}',
        style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.4,
            color: MyTheme.textSecondary),
      ),
      const SizedBox(height: 10),
    ];
    for (final row in _macPermissionRows) {
      if (!requiredPerms.contains(row.permission)) {
        continue;
      }
      children.add(_buildPermissionRow(row, narrow));
    }
    children.add(const SizedBox(height: 4));
    // O aviso do reinicio aparece so depois de o tecnico ter clicado em
    // Configurar numa das permissoes que o macOS so passa a respeitar depois
    // de a app reabrir.
    if (_requestedNeedRestart.isNotEmpty) {
      children.add(_buildRestartNote());
      children.add(const SizedBox(height: 10));
    }
    children.add(_buildFooter());
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: children,
    );
  }

  Widget _buildPermissionRow(_MacPermissionRow row, bool narrow) {
    final granted = _granted[row.permission] == true;
    final statusText = translate(granted ? 'Granted' : 'Not granted');
    final statusColor = granted ? MyTheme.green : MyTheme.danger;
    final button = dialogButton('Configure',
        onPressed: granted ? null : () => _request(row));
    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Icon(row.icon, size: 16, color: MyTheme.textSecondary),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                translate(row.titleKey),
                style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: MyTheme.textPrimary),
              ),
            ),
            const SizedBox(width: 8),
            // O estado tambem vai escrito, e nao so na cor e na forma do
            // sinal: isto abre em Macs de clientes, por vezes com o ecra
            // partilhado e com quem nao distingue bem as cores.
            Text(
              statusText,
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: statusColor),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          translate(row.descKey),
          style: const TextStyle(
              fontSize: 12, height: 1.4, color: MyTheme.textSecondary),
        ),
      ],
    );
    return Semantics(
      label: '${translate(row.titleKey)}: $statusText',
      container: true,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: MyTheme.surface2,
          borderRadius: BorderRadius.circular(MyTheme.radiusMd),
          border: Border.all(
              color: granted ? MyTheme.green : MyTheme.hairline, width: 1),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 24,
              height: 24,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: statusColor.withOpacity(0.18),
                shape: BoxShape.circle,
                border: Border.all(color: statusColor, width: 1),
              ),
              child: Icon(
                granted ? Icons.done_rounded : Icons.close_rounded,
                size: 15,
                color: statusColor,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: narrow
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        text,
                        Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: button,
                        ),
                      ],
                    )
                  : text,
            ),
            if (!narrow) const SizedBox(width: 12),
            if (!narrow) button,
          ],
        ),
      ),
    );
  }

  Widget _buildRestartNote() {
    const amber = Color(0xFFE2B33C);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: amber.withOpacity(0.10),
        borderRadius: BorderRadius.circular(MyTheme.radiusMd),
        border: Border.all(color: amber.withOpacity(0.5), width: 1),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.restart_alt_rounded, size: 16, color: amber),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              translate('mac-permissions-restart-tip'),
              style: const TextStyle(fontSize: 12, height: 1.4, color: amber),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFooter() {
    final allGranted = _allGranted;
    final color = allGranted ? MyTheme.green : MyTheme.textSecondary;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: allGranted
            ? MyTheme.green.withOpacity(0.12)
            : Colors.black.withOpacity(0.18),
        borderRadius: BorderRadius.circular(MyTheme.radiusMd),
        border: Border.all(
            color: allGranted ? MyTheme.green : MyTheme.hairline, width: 1),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            allGranted ? Icons.check_circle : Icons.info_outline,
            size: 16,
            color: color,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              translate(allGranted
                  ? 'mac-permissions-all-granted-tip'
                  : 'mac-permissions-steps-tip'),
              style: TextStyle(fontSize: 12, height: 1.4, color: color),
            ),
          ),
        ],
      ),
    );
  }

  void _request(_MacPermissionRow row) {
    // Abre o painel certo das Definicoes. Nada de ler o estado agora: a
    // chamada devolve antes de o tecnico ter feito o que quer que seja la.
    // Quem le o estado e o _refresh(), de segundo a segundo.
    macPermissionRequest(row.permission);
    if (macPermissionNeedsRestart(row.permission)) {
      setState(() {
        _requestedNeedRestart.add(row.permission);
      });
    }
  }
}
