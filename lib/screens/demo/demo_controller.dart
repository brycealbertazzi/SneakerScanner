import 'dart:async';

import 'package:flutter/material.dart';

import '../../services/mixpanel_service.dart';
import 'coach_mark_overlay.dart';

/// Widgets the guided demo can spotlight. Each one attaches
/// `key: DemoKeys.key(DemoTarget.x)` at its build site.
enum DemoTarget {
  cameraPreview,
  scanLabelButton,
  enterSkuButton,
  skuField,
  skuFormatsIcon,
  skuFormatsSheet,
  lookUpButton,
  scanBarcodeButton,
  searchByTitleButton,
  cancelButton,
  historyTab,
  historyEmptyState,
}

/// Registry of the [GlobalKey]s the demo measures its spotlight from.
///
/// Keys are created lazily and reused, which is safe because no two of these
/// widgets are ever mounted at the same time.
class DemoKeys {
  DemoKeys._();

  static final Map<DemoTarget, GlobalKey> _keys = {};

  static GlobalKey key(DemoTarget target) => _keys.putIfAbsent(
    target,
    () => GlobalKey(debugLabel: 'demo:${target.name}'),
  );

  /// Global-coordinate rect of [target], or null if it isn't laid out yet.
  static Rect? rectOf(DemoTarget target) {
    final context = _keys[target]?.currentContext;
    if (context == null) return null;
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }
}

/// Signals the app sends back to the demo so "tap it yourself" steps can
/// advance on the real thing happening rather than on a timer.
enum DemoEvent {
  manualDialogOpened,
  formatsSheetOpened,
  formatsSheetClosed,
  manualDialogClosed,
  historyTabOpened,
}

class DemoStep {
  /// Widget to spotlight. Null renders a centered card with a plain scrim.
  final DemoTarget? target;
  final String title;
  final String body;

  /// When set the step has no Next button: the spotlight becomes tappable and
  /// the demo waits for the app to report this event.
  final DemoEvent? awaitEvent;

  /// Instruction shown in place of the Next button on action steps.
  final String? actionHint;

  final EdgeInsets holePadding;
  final double holeRadius;

  /// Where the card sits when there is no [target] to anchor it to.
  final Alignment cardAlignment;

  /// Runs as the step becomes current — used to drive the app between steps.
  final void Function(DemoController controller)? onEnter;

  const DemoStep({
    required this.title,
    required this.body,
    this.target,
    this.awaitEvent,
    this.actionHint,
    this.holePadding = const EdgeInsets.all(8),
    this.holeRadius = 12,
    this.cardAlignment = Alignment.center,
    this.onEnter,
  }) : assert(
         awaitEvent == null || actionHint != null,
         'action steps need an actionHint',
       );

  bool get isAction => awaitEvent != null;
}

/// Drives the one-time guided demo. Non-skippable by design: the overlay has no
/// dismiss affordance and swallows every tap outside the current spotlight.
class DemoController extends ChangeNotifier {
  DemoController._();

  static final DemoController instance = DemoController._();

  List<DemoStep> _steps = const [];
  int _index = 0;
  bool _active = false;
  OverlayEntry? _entry;
  Completer<void>? _finished;
  void Function(int tabIndex)? _switchTab;
  NavigatorState? _navigator;
  bool _formatsSheetOpen = false;

  bool get isActive => _active;
  int get index => _index;
  int get stepCount => _steps.length;
  DemoStep get step => _steps[_index];
  bool get isLastStep => _index == _steps.length - 1;

  /// Inserts the coach-mark overlay into the root overlay so it stays above any
  /// route pushed while the demo runs (dialogs, bottom sheets).
  Future<void> start(
    BuildContext context, {
    List<DemoStep> steps = kDemoSteps,
    required void Function(int tabIndex) switchTab,
  }) {
    if (_active || steps.isEmpty) return Future<void>.value();

    // Never let a missing overlay take the app down — just skip the demo.
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return Future<void>.value();

    _steps = steps;
    _index = 0;
    _active = true;
    _switchTab = switchTab;
    _navigator = Navigator.maybeOf(context);
    _formatsSheetOpen = false;
    _finished = Completer<void>();

    // Assigned only once it's actually in the tree, so finish() can never try
    // to remove an entry that was never inserted.
    final entry = OverlayEntry(builder: (_) => const CoachMarkOverlay());
    overlay.insert(entry);
    _entry = entry;

    MixpanelService.instance.track(
      'Demo Started',
      properties: {'total_steps': steps.length},
    );
    _trackStep();
    _steps[0].onEnter?.call(this);
    return _finished!.future;
  }

  void next() {
    if (!_active) return;
    if (isLastStep) {
      finish(completed: true);
      return;
    }
    _index++;
    notifyListeners();
    _trackStep();
    step.onEnter?.call(this);
  }

  /// Called by the app when something the demo is waiting on happens.
  void handleEvent(DemoEvent event) {
    if (!_active) return;
    if (event == DemoEvent.formatsSheetOpened) _formatsSheetOpen = true;
    if (event == DemoEvent.formatsSheetClosed) _formatsSheetOpen = false;
    if (!step.isAction || step.awaitEvent != event) return;
    next();
  }

  void switchTab(int tabIndex) => _switchTab?.call(tabIndex);

  /// The scrim swallows the sheet's own dismiss gestures, so the demo has to
  /// close it on the user's behalf when the step is done with it.
  void closeFormatsSheet() {
    if (!_formatsSheetOpen) return;
    _formatsSheetOpen = false;
    final navigator = _navigator;
    if (navigator != null && navigator.canPop()) navigator.pop();
  }

  void finish({bool completed = false}) {
    if (!_active) return;
    _active = false;
    _entry?.remove();
    _entry = null;
    _switchTab = null;
    _navigator = null;
    _formatsSheetOpen = false;
    MixpanelService.instance.track(
      completed ? 'Demo Completed' : 'Demo Ended Early',
      properties: {'last_step': _index + 1, 'total_steps': _steps.length},
    );
    notifyListeners();
    if (_finished?.isCompleted == false) _finished!.complete();
  }

  void _trackStep() {
    MixpanelService.instance.track(
      'Demo Step Viewed',
      properties: {
        'step': _index + 1,
        'total_steps': _steps.length,
        'title': step.title,
      },
    );
  }
}

// ── The script ────────────────────────────────────────────────────────────────

const kDemoSteps = <DemoStep>[
  // Scan tab
  DemoStep(
    target: DemoTarget.cameraPreview,
    title: 'This is your viewfinder',
    body:
        'Point it at the label on the shoe box. Lay the box flat, fill the '
        'frame, and keep the whole label in view.',
    holePadding: EdgeInsets.all(4),
  ),
  DemoStep(
    target: DemoTarget.scanLabelButton,
    title: 'Scan the label',
    body:
        'Tap here to photograph it. SneakScan reads the style code, brand and '
        'size straight off the label — no typing needed.',
  ),
  DemoStep(
    target: DemoTarget.enterSkuButton,
    title: 'Or type the code yourself',
    body:
        'Labels get worn, torn, or lost to glare. When the camera can\'t read '
        'one, you can always enter the code by hand.',
    awaitEvent: DemoEvent.manualDialogOpened,
    actionHint: 'Tap "Enter SKU Manually" to keep going',
  ),

  // Manual SKU dialog
  DemoStep(
    target: DemoTarget.skuField,
    title: 'The style code goes here',
    body:
        'Type it exactly as printed on the label — letters, numbers and all. '
        'A style code is the most accurate way to identify a shoe.',
  ),
  DemoStep(
    target: DemoTarget.skuFormatsIcon,
    title: 'Not sure what to look for?',
    body:
        'Every brand prints its style code a little differently. This button '
        'shows you exactly what each one looks like.',
    awaitEvent: DemoEvent.formatsSheetOpened,
    // No padding: the spotlight is the button's own tap target, so a stray
    // press can't land on the text field and pop the keyboard up.
    holePadding: EdgeInsets.zero,
    actionHint: 'Tap the ⓘ button to open the guide',
    holeRadius: 24,
  ),
  DemoStep(
    target: DemoTarget.skuFormatsSheet,
    title: 'Ten brands, ten formats',
    body:
        'Nike, Adidas, Asics, New Balance, Vans, Puma and the rest — each with '
        'a real example of what its code looks like.',
    // Overshoot the bottom so the cutout's lower corners fall off-screen.
    holePadding: EdgeInsets.only(bottom: 28),
    holeRadius: 20,
  ),
  DemoStep(
    target: DemoTarget.lookUpButton,
    title: 'One tap, three markets',
    body:
        'Look Up pulls live StockX, GOAT and eBay prices for that code, broken '
        'down by size. Save this one for a real box.',
    onEnter: _closeFormatsSheet,
  ),
  DemoStep(
    target: DemoTarget.scanBarcodeButton,
    title: 'No style code? Use the barcode',
    body:
        'Scan the barcode on the box label instead and SneakScan will match '
        'the shoe from that.',
  ),
  DemoStep(
    target: DemoTarget.searchByTitleButton,
    title: 'Or just search the name',
    body:
        'Type something like "Nike Air Max 90 White" and pick the right shoe '
        'from the matches.',
  ),
  DemoStep(
    target: DemoTarget.cancelButton,
    title: 'Back out any time',
    body: 'Nothing is looked up until you say so.',
    awaitEvent: DemoEvent.manualDialogClosed,
    actionHint: 'Tap Cancel to close this',
  ),

  // History
  DemoStep(
    target: DemoTarget.historyTab,
    title: 'Everything you scan is saved',
    body: 'Your whole scan history lives one tap away.',
    awaitEvent: DemoEvent.historyTabOpened,
    actionHint: 'Tap History',
    // Kept inside the nav item so the press can't miss it and hit the page.
    holePadding: EdgeInsets.symmetric(horizontal: 22, vertical: 4),
  ),
  DemoStep(
    target: DemoTarget.historyEmptyState,
    title: 'Your scan history',
    body:
        'Every lookup lands here with its prices and photo. Tap a past scan to '
        'reopen it — you never have to scan the same box twice.',
    holePadding: EdgeInsets.all(16),
    holeRadius: 20,
  ),

  // Wrap
  DemoStep(
    title: 'You\'re all set',
    body: 'Grab a box, point the camera at the label, and run your first scan.',
    onEnter: _returnToScanTab,
  ),
];

void _returnToScanTab(DemoController controller) => controller.switchTab(0);

void _closeFormatsSheet(DemoController controller) =>
    controller.closeFormatsSheet();
