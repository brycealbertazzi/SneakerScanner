import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/subscription_service.dart';
import 'login_screen.dart';
import 'main_screen.dart';
import 'paywall_page.dart';

// ── Entry point ───────────────────────────────────────────────────────────────

class OnboardingFlow extends StatefulWidget {
  const OnboardingFlow({super.key});

  @override
  State<OnboardingFlow> createState() => _OnboardingFlowState();
}

class _OnboardingFlowState extends State<OnboardingFlow> {
  // ── Intro phase ──
  bool _inIntro = true;

  // ── Question phase ──
  bool _inQuestions = true;
  int _currentQuestion = 0;
  PageController _questionPageCtrl = PageController();

  // ── Pages phase ──
  final _pageController = PageController();
  int _currentPage = 0;
  bool _showAnalysis = false;

  // Starts at 1 so the bar opens at one step in; incremented on each action
  int _stepsCompleted = 1;

  // Stored question answers (question index → answer index)
  final Map<int, int> _questionAnswers = {};

  // Currently highlighted answer on the active question screen
  int? _currentSelectedAnswer;

  // Multi-select state for Q2 ("Where do you primarily sell?")
  Set<int> _currentMultiAnswers = {};
  final Map<int, Set<int>> _multiQuestionAnswers = {};

  @override
  void initState() {
    super.initState();
    // Start the subscription check as early as possible — well before the
    // analysis screen opens — so the status (freeTrial vs cancelled) is
    // resolved by the time we route to the paywall. Without this, if product
    // loading takes longer than the analysis animation (~3 s), awaitLaunchCheck
    // could return prematurely with status = loading, causing a lapsed
    // subscriber to incorrectly see "Start Free Trial".
    SubscriptionService.instance.initialize();
  }

  static const _multiSelectQuestion = 2; // Q3: "Where do you primarily sell?"

  // Called by single-select _QuestionScreen on tap
  void _onAnswerSelected(int questionIndex, int answerIndex) {
    _questionAnswers[questionIndex] = answerIndex;
    setState(() => _currentSelectedAnswer = answerIndex);
  }

  // Called by multi-select _QuestionScreen on each tap
  void _onMultiAnswerSelected(Set<int> selected) {
    _multiQuestionAnswers[_multiSelectQuestion] = Set.from(selected);
    setState(() => _currentMultiAnswers = Set.from(selected));
  }

  void _restoreSelectionForQuestion(int questionIndex) {
    if (questionIndex == _multiSelectQuestion) {
      _currentMultiAnswers = Set.from(
        _multiQuestionAnswers[questionIndex] ?? {},
      );
      _currentSelectedAnswer = null;
    } else {
      _currentSelectedAnswer = _questionAnswers[questionIndex];
      _currentMultiAnswers = {};
    }
  }

  void _startOnboarding() {
    setState(() {
      _inIntro = false;
      _restoreSelectionForQuestion(0);
    });
  }

  bool get _canContinue {
    if (!_inQuestions) return true;
    if (_currentQuestion == _multiSelectQuestion) {
      return _currentMultiAnswers.isNotEmpty;
    }
    return _currentSelectedAnswer != null;
  }

  void _onContinue() {
    if (!_canContinue) return;
    if (_inQuestions) {
      setState(() => _stepsCompleted++);
      if (_currentQuestion < _kQuestions.length - 1) {
        final nextQ = _currentQuestion + 1;
        setState(() {
          _currentQuestion = nextQ;
          _restoreSelectionForQuestion(nextQ);
        });
        _questionPageCtrl.nextPage(
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeInOut,
        );
      } else {
        setState(() {
          _inQuestions = false;
          _currentSelectedAnswer = null;
        });
      }
    } else {
      // Pages phase
      setState(() => _stepsCompleted++);
      if (_currentPage < 3) {
        _pageController.nextPage(
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeInOut,
        );
      } else {
        Future.delayed(const Duration(milliseconds: 500), () {
          if (mounted) setState(() => _showAnalysis = true);
        });
      }
    }
  }

  // Back is available on all question/page screens (Q1 back → intro)
  bool get _canGoBack => !_inIntro;

  void _goBack() {
    if (!_canGoBack) return;
    setState(() {
      if (_stepsCompleted > 1) _stepsCompleted--;
    });
    if (!_inQuestions) {
      if (_currentPage > 0) {
        _pageController.previousPage(
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeInOut,
        );
      } else {
        // Back from Page1 → Q5: recreate controller at the last question
        _questionPageCtrl.dispose();
        final lastQ = _kQuestions.length - 1;
        _questionPageCtrl = PageController(initialPage: lastQ);
        setState(() {
          _inQuestions = true;
          _currentQuestion = lastQ;
          _restoreSelectionForQuestion(lastQ);
        });
      }
    } else {
      if (_currentQuestion > 0) {
        final prevQ = _currentQuestion - 1;
        _questionPageCtrl.previousPage(
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeInOut,
        );
        setState(() {
          _currentQuestion = prevQ;
          _restoreSelectionForQuestion(prevQ);
        });
      } else {
        // Q1 back → intro screen
        setState(() => _inIntro = true);
      }
    }
  }

  Future<void> _completeOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('has_seen_onboarding', true);
    if (!mounted) return;
    final user = FirebaseAuth.instance.currentUser;
    final Widget destination;
    if (SubscriptionService.instance.canScan) {
      // Already subscribed — skip paywall, ensure signed in before app.
      destination = user != null ? const MainScreen() : const LoginScreen();
    } else {
      // Not subscribed — paywall first, then sign in if needed.
      destination = PaywallPage(isCloseable: false, isPreLogin: user == null);
    }
    Navigator.of(
      context,
    ).pushReplacement(MaterialPageRoute(builder: (_) => destination));
  }

  @override
  void dispose() {
    _questionPageCtrl.dispose();
    _pageController.dispose();
    super.dispose();
  }

  // 8 questions + 4 animation pages = 12 total steps, each ~8.3%
  static const _totalSteps = 12;

  double get _progressValue => _stepsCompleted / _totalSteps;

  Widget _buildFooter() {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 14, 24, 24),
      decoration: BoxDecoration(
        color: const Color(0xFF0D0D1A),
        border: Border(
          top: BorderSide(color: Colors.white.withValues(alpha: 0.08), width: 0.5),
        ),
      ),
      child: _PressableButton(
        label: 'Continue',
        enabled: _canContinue,
        onPressed: _onContinue,
      ),
    );
  }

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.only(left: 12, right: 24),
      child: Row(
        children: [
          // Back button — always takes up space to keep bar width consistent
          SizedBox(
            width: 40,
            height: 40,
            child: _canGoBack
                ? GestureDetector(
                    onTap: () {
                      HapticFeedback.heavyImpact();
                      _goBack();
                    },
                    child: Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withValues(alpha: 0.10),
                      ),
                      child: Icon(
                        Icons.arrow_back_rounded,
                        color: Colors.white.withValues(alpha: 0.75),
                        size: 20,
                      ),
                    ),
                  )
                : null,
          ),
          const SizedBox(width: 12),
          // Progress bar
          Expanded(
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.0, end: _progressValue),
              duration: const Duration(milliseconds: 450),
              curve: Curves.easeInOut,
              builder: (context, value, _) => ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                  value: value,
                  minHeight: 3,
                  backgroundColor: Colors.white.withValues(alpha: 0.08),
                  valueColor: const AlwaysStoppedAnimation(Color(0xFF646CFF)),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Analysis screen stands alone — no progress bar
    if (_showAnalysis) {
      return _AnalysisScreen(onComplete: _completeOnboarding);
    }

    // Intro screen — no top bar
    if (_inIntro) {
      return _IntroScreen(onGetStarted: _startOnboarding);
    }

    // Single persistent scaffold so the TweenAnimationBuilder keeps its state
    // across the questions→pages phase transition (no reset to 0%).
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D1A),
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 16),
            _buildTopBar(),
            Expanded(
              child: _inQuestions
                  ? PageView(
                      key: const ValueKey('questions'),
                      controller: _questionPageCtrl,
                      physics: const NeverScrollableScrollPhysics(),
                      children: List.generate(
                        _kQuestions.length,
                        (i) => i == _multiSelectQuestion
                            ? _QuestionScreen(
                                key: ValueKey(i),
                                question: _kQuestions[i],
                                multiSelect: true,
                                initialMultiSelection: _multiQuestionAnswers[i],
                                onMultiAnswered: _onMultiAnswerSelected,
                              )
                            : _QuestionScreen(
                                key: ValueKey(i),
                                question: _kQuestions[i],
                                initialSelection: _questionAnswers[i],
                                onAnswered: (answerIdx) {
                                  _onAnswerSelected(i, answerIdx);
                                },
                              ),
                      ),
                    )
                  : PageView(
                      key: const ValueKey('pages'),
                      controller: _pageController,
                      physics: const NeverScrollableScrollPhysics(),
                      onPageChanged: (i) => setState(() => _currentPage = i),
                      children: const [_Page1(), _Page2(), _Page3(), _Page4()],
                    ),
            ),
            _buildFooter(),
          ],
        ),
      ),
    );
  }
}

// ── Intro screen ─────────────────────────────────────────────────────────────

class _IntroScreen extends StatefulWidget {
  final VoidCallback onGetStarted;
  const _IntroScreen({required this.onGetStarted});

  @override
  State<_IntroScreen> createState() => _IntroScreenState();
}

class _IntroScreenState extends State<_IntroScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseCtrl;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);
    _scale = Tween<double>(
      begin: 0.92,
      end: 1.05,
    ).animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D1A),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            children: [
              const Spacer(flex: 3),
              // Logo with pulse animation
              ScaleTransition(
                scale: _scale,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(28),
                  child: Image.asset(
                    'assets/app_icon.png',
                    width: 140,
                    height: 140,
                  ),
                ),
              ),
              const SizedBox(height: 36),
              Text(
                'SneakScan',
                style: GoogleFonts.poppins(
                  fontSize: 40,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'Flip sneakers like a pro',
                style: GoogleFonts.inter(
                  fontSize: 18,
                  fontWeight: FontWeight.w400,
                  color: Colors.white.withValues(alpha: 0.55),
                ),
              ),
              const Spacer(flex: 4),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: () {
                    HapticFeedback.heavyImpact();
                    widget.onGetStarted();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF646CFF),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    elevation: 0,
                  ),
                  child: Text(
                    'Get Started',
                    style: GoogleFonts.poppins(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Onboarding questions ──────────────────────────────────────────────────────

class _OnboardingQuestion {
  final String question;
  final List<String> answers;
  const _OnboardingQuestion(this.question, this.answers);
}

const _kQuestions = [
  _OnboardingQuestion('How long have you been reselling sneakers?', [
    'Just getting started',
    'Less than a year',
    '1–3 years',
    '3+ years',
  ]),
  _OnboardingQuestion('How many pairs do you flip per month?', [
    '1–5',
    '6–15',
    '16–30',
    '30+',
  ]),
  _OnboardingQuestion('Where do you primarily sell?', [
    'StockX',
    'GOAT',
    'eBay',
    'Facebook Marketplace',
    'Depop',
    'Mercari',
    'Other',
  ]),
  _OnboardingQuestion('What\'s your biggest challenge when reselling?', [
    'Finding the right sell price',
    'Knowing which shoes to buy',
    'Identifying fakes',
    'Keeping track of inventory',
  ]),
  _OnboardingQuestion('What\'s your main goal with SneakScan?', [
    'Quickly price shoes at thrift stores',
    'Authenticate before buying',
    'Maximize profit on every flip',
    'Build a full-time reselling business',
  ]),
  _OnboardingQuestion(
    'How quickly do you need to decide if a shoe is worth buying?',
    ['On the spot (seconds)', 'A few minutes', 'I take my time', 'It varies'],
  ),
  _OnboardingQuestion(
    'How much time per week do you spend researching prices?',
    ['Less than 1 hour', '1–3 hours', '3–5 hours', '5+ hours'],
  ),
  _OnboardingQuestion('What type of sneakers do you mostly flip?', [
    'Nike / Jordan',
    'Adidas / Yeezy',
    'New Balance',
    'Whatever I find',
  ]),
];

class _QuestionScreen extends StatefulWidget {
  final _OnboardingQuestion question;
  final void Function(int answerIndex)? onAnswered;
  final void Function(Set<int> answerIndices)? onMultiAnswered;
  final int? initialSelection;
  final Set<int>? initialMultiSelection;
  final bool multiSelect;

  const _QuestionScreen({
    super.key,
    required this.question,
    this.onAnswered,
    this.onMultiAnswered,
    this.initialSelection,
    this.initialMultiSelection,
    this.multiSelect = false,
  });

  @override
  State<_QuestionScreen> createState() => _QuestionScreenState();
}

class _QuestionScreenState extends State<_QuestionScreen> {
  int? _selected;
  late Set<int> _selectedSet;

  @override
  void initState() {
    super.initState();
    _selected = widget.initialSelection;
    _selectedSet = Set.from(widget.initialMultiSelection ?? {});
  }

  @override
  void didUpdateWidget(_QuestionScreen old) {
    super.didUpdateWidget(old);
    if (!widget.multiSelect &&
        old.initialSelection != widget.initialSelection) {
      _selected = widget.initialSelection;
    }
    if (widget.multiSelect &&
        old.initialMultiSelection != widget.initialMultiSelection) {
      _selectedSet = Set.from(widget.initialMultiSelection ?? {});
    }
  }

  void _onTap(int index) {
    HapticFeedback.heavyImpact();
    if (widget.multiSelect) {
      setState(() {
        if (_selectedSet.contains(index)) {
          _selectedSet.remove(index);
        } else {
          _selectedSet.add(index);
        }
      });
      widget.onMultiAnswered?.call(Set.from(_selectedSet));
    } else {
      setState(() => _selected = index);
      widget.onAnswered?.call(index);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 48),
          Text(
            widget.question.question,
            style: GoogleFonts.poppins(
              fontSize: 26,
              fontWeight: FontWeight.w700,
              color: Colors.white,
              height: 1.25,
            ),
          ),
          const SizedBox(height: 32),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: List.generate(widget.question.answers.length, (i) {
                  final isSelected = widget.multiSelect
                      ? _selectedSet.contains(i)
                      : _selected == i;
                  return GestureDetector(
                    onTap: () => _onTap(i),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOut,
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 16,
                      ),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? const Color(0xFF646CFF)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: isSelected
                              ? const Color(0xFF646CFF)
                              : Colors.white.withValues(alpha: 0.15),
                          width: 1.5,
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              widget.question.answers[i],
                              style: GoogleFonts.inter(
                                fontSize: 15,
                                fontWeight: isSelected
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                                color: isSelected
                                    ? Colors.white
                                    : Colors.white.withValues(alpha: 0.75),
                              ),
                            ),
                          ),
                          if (isSelected)
                            const Icon(
                              Icons.check_rounded,
                              color: Colors.white,
                              size: 18,
                            ),
                        ],
                      ),
                    ),
                  );
                }),
              ),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

// ── Shared page layout ────────────────────────────────────────────────────────

class _OnboardingPageLayout extends StatelessWidget {
  final Widget visual;
  final String title;
  final String description;
  final double visualHeight;

  const _OnboardingPageLayout({
    required this.visual,
    required this.title,
    required this.description,
    this.visualHeight = 210,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Column(
        children: [
          const SizedBox(height: 32),
          SizedBox(
            height: visualHeight,
            child: Center(child: visual),
          ),
          const SizedBox(height: 32),
          Text(
            title,
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(
              fontSize: 28,
              fontWeight: FontWeight.w700,
              color: Colors.white,
              height: 1.25,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            description,
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 15,
              color: Colors.grey[400],
              height: 1.6,
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

// ── Page 1: Camera viewfinder ─────────────────────────────────────────────────

class _Page1 extends StatefulWidget {
  const _Page1();

  @override
  State<_Page1> createState() => _Page1State();
}

class _Page1State extends State<_Page1> with TickerProviderStateMixin {
  late final AnimationController _bracketCtrl;
  late final AnimationController _scanCtrl;
  late final Animation<double> _bracketProgress;
  late final Animation<double> _labelFade;
  late final Animation<double> _scanPos;

  @override
  void initState() {
    super.initState();
    _bracketCtrl = AnimationController(
      duration: const Duration(milliseconds: 900),
      vsync: this,
    );
    _scanCtrl = AnimationController(
      duration: const Duration(milliseconds: 1400),
      vsync: this,
    );

    _bracketProgress = CurvedAnimation(
      parent: _bracketCtrl,
      curve: Curves.easeOut,
    );
    _labelFade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _bracketCtrl,
        curve: const Interval(0.0, 0.5, curve: Curves.easeOut),
      ),
    );
    _scanPos = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _scanCtrl, curve: Curves.easeInOut));

    Future.delayed(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      _bracketCtrl.forward().then((_) {
        if (mounted) _scanCtrl.repeat(reverse: true);
      });
    });
  }

  @override
  void dispose() {
    _bracketCtrl.dispose();
    _scanCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _OnboardingPageLayout(
      visual: AnimatedBuilder(
        animation: Listenable.merge([_bracketCtrl, _scanCtrl]),
        builder: (context, _) => _ViewfinderWidget(
          bracketProgress: _bracketProgress.value,
          labelFade: _labelFade.value,
          scanPos: _scanPos.value,
        ),
      ),
      title: 'Scan any sneaker\ninstantly',
      description:
          'Point your camera at a sneaker box label. '
          'The app instantly identifies the shoe and retrieves current resale data.',
    );
  }
}

class _ViewfinderWidget extends StatelessWidget {
  final double bracketProgress;
  final double labelFade;
  final double scanPos;

  const _ViewfinderWidget({
    required this.bracketProgress,
    required this.labelFade,
    required this.scanPos,
  });

  @override
  Widget build(BuildContext context) {
    const w = 230.0;
    const h = 155.0;
    return SizedBox(
      width: w,
      height: h,
      child: Stack(
        children: [
          // Sneaker label card
          Opacity(
            opacity: labelFade,
            child: Container(
              width: w,
              height: h,
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A2E),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white12),
              ),
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.directions_run_rounded,
                        color: Color(0xFF646CFF),
                        size: 14,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'NIKE AIR JORDAN 1',
                        style: GoogleFonts.inter(
                          color: Colors.white70,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'STYLE: 553558-174',
                    style: GoogleFonts.inter(
                      color: Colors.white54,
                      fontSize: 10,
                      letterSpacing: 0.3,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'COLOR: WHITE/BLACK-RED',
                    style: GoogleFonts.inter(
                      color: Colors.white38,
                      fontSize: 9,
                      letterSpacing: 0.3,
                    ),
                  ),
                  const Spacer(),
                  // Barcode
                  SizedBox(
                    height: 28,
                    child: Row(
                      children: List.generate(
                        24,
                        (i) => Expanded(
                          child: Container(
                            margin: const EdgeInsets.symmetric(horizontal: 0.4),
                            color: i % 3 == 0
                                ? Colors.white.withValues(alpha: 0.55)
                                : i % 2 == 0
                                ? Colors.white.withValues(alpha: 0.25)
                                : Colors.transparent,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 3),
                  Center(
                    child: Text(
                      '036204133593',
                      style: GoogleFonts.inter(
                        color: Colors.white38,
                        fontSize: 8,
                        letterSpacing: 1,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Corner brackets
          Positioned.fill(
            child: CustomPaint(
              painter: _BracketPainter(
                progress: bracketProgress,
                color: const Color(0xFF646CFF),
              ),
            ),
          ),
          // Scan line (only after brackets have appeared)
          if (bracketProgress > 0.8)
            Positioned(
              left: 10,
              right: 10,
              top: 10 + scanPos * (h - 20),
              child: Opacity(
                opacity: 0.75,
                child: Container(
                  height: 2,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [
                        Colors.transparent,
                        Color(0xFF646CFF),
                        Colors.transparent,
                      ],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF646CFF).withValues(alpha: 0.5),
                        blurRadius: 6,
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _BracketPainter extends CustomPainter {
  final double progress;
  final Color color;

  const _BracketPainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    if (progress == 0) return;
    final paint = Paint()
      ..color = color.withValues(alpha: progress.clamp(0.0, 1.0))
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    const pad = 5.0;
    const len = 18.0;
    final l = pad;
    final r = size.width - pad;
    final t = pad;
    final b = size.height - pad;

    // Scale from 130% → 100% as progress goes 0 → 1
    final s = 1.0 + (1 - progress) * 0.3;
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.scale(s);
    canvas.translate(-size.width / 2, -size.height / 2);

    // Top-left
    canvas.drawLine(Offset(l, t + len), Offset(l, t), paint);
    canvas.drawLine(Offset(l, t), Offset(l + len, t), paint);
    // Top-right
    canvas.drawLine(Offset(r - len, t), Offset(r, t), paint);
    canvas.drawLine(Offset(r, t), Offset(r, t + len), paint);
    // Bottom-left
    canvas.drawLine(Offset(l, b - len), Offset(l, b), paint);
    canvas.drawLine(Offset(l, b), Offset(l + len, b), paint);
    // Bottom-right
    canvas.drawLine(Offset(r - len, b), Offset(r, b), paint);
    canvas.drawLine(Offset(r, b), Offset(r, b - len), paint);

    canvas.restore();
  }

  @override
  bool shouldRepaint(_BracketPainter old) => old.progress != progress;
}

// ── Page 2: Resale prices ─────────────────────────────────────────────────────

class _PlatformData {
  final String name;
  final int price;
  final Color color;
  final IconData icon;
  const _PlatformData(this.name, this.price, this.color, this.icon);
}

const _kPlatforms = [
  _PlatformData('StockX', 247, Color(0xFF22C55E), Icons.trending_up_rounded),
  _PlatformData('GOAT', 215, Color(0xFFE63946), Icons.directions_run_rounded),
  _PlatformData('eBay', 189, Color(0xFFE6AC00), Icons.local_offer_rounded),
];

class _Page2 extends StatefulWidget {
  const _Page2();

  @override
  State<_Page2> createState() => _Page2State();
}

class _Page2State extends State<_Page2> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      duration: const Duration(milliseconds: 2400),
      vsync: this,
    );
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) _ctrl.forward();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _OnboardingPageLayout(
      visual: AnimatedBuilder(
        animation: _ctrl,
        builder: (context, _) {
          return SizedBox(
            width: 280,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(_kPlatforms.length, (i) {
                final slideStart = 0.05 + i * 0.22;
                final slideEnd = slideStart + 0.25;
                final t = _ctrl.value;
                final slideP = ((t - slideStart) / (slideEnd - slideStart))
                    .clamp(0.0, 1.0);
                // Ease the slide progress
                final easedSlide = Curves.easeOut.transform(slideP);

                final priceStart = 0.35 + i * 0.18;
                final priceEnd = priceStart + 0.25;
                final priceP = ((t - priceStart) / (priceEnd - priceStart))
                    .clamp(0.0, 1.0);
                final displayPrice = (_kPlatforms[i].price * priceP).round();

                return Opacity(
                  opacity: easedSlide,
                  child: Transform.translate(
                    offset: Offset(-28 * (1 - easedSlide), 0),
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1A1A2E),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white10),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: _kPlatforms[i].color.withValues(
                                alpha: 0.15,
                              ),
                              borderRadius: BorderRadius.circular(9),
                            ),
                            child: Icon(
                              _kPlatforms[i].icon,
                              color: _kPlatforms[i].color,
                              size: 18,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              _kPlatforms[i].name,
                              style: GoogleFonts.poppins(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                                fontSize: 15,
                              ),
                            ),
                          ),
                          Text(
                            '\$$displayPrice',
                            style: GoogleFonts.poppins(
                              color: _kPlatforms[i].color,
                              fontWeight: FontWeight.w700,
                              fontSize: 18,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }),
            ),
          );
        },
      ),
      title: 'See resale prices\nacross platforms',
      description:
          'Compare what sneakers are selling for across StockX, GOAT, '
          'and eBay in seconds. All in one place.',
    );
  }
}

// ── Page 3: Profit pop ────────────────────────────────────────────────────────

class _Page3 extends StatefulWidget {
  const _Page3();

  @override
  State<_Page3> createState() => _Page3State();
}

class _Page3State extends State<_Page3> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;
  late final Animation<double> _profitFade;
  late final Animation<double> _chipsFade;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );

    _scale = TweenSequence(
      [
        TweenSequenceItem(tween: Tween(begin: 0.3, end: 1.15), weight: 60),
        TweenSequenceItem(tween: Tween(begin: 1.15, end: 0.95), weight: 20),
        TweenSequenceItem(tween: Tween(begin: 0.95, end: 1.0), weight: 20),
      ],
    ).animate(CurvedAnimation(parent: _ctrl, curve: const Interval(0.0, 0.85)));
    _profitFade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _ctrl,
        curve: const Interval(0.0, 0.35, curve: Curves.easeOut),
      ),
    );
    _chipsFade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _ctrl,
        curve: const Interval(0.55, 0.9, curve: Curves.easeOut),
      ),
    );

    Future.delayed(const Duration(milliseconds: 400), () {
      if (mounted) _ctrl.forward();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _OnboardingPageLayout(
      visual: AnimatedBuilder(
        animation: _ctrl,
        builder: (context, _) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Retail price chip
              Opacity(
                opacity: _chipsFade.value,
                child: _PriceChip(label: 'Retail', value: '\$120'),
              ),
              const SizedBox(height: 20),
              // Profit amount with bounce
              Opacity(
                opacity: _profitFade.value,
                child: Transform.scale(
                  scale: _scale.value,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '+\$127',
                        style: GoogleFonts.poppins(
                          fontSize: 64,
                          fontWeight: FontWeight.w800,
                          color: const Color(0xFF22C55E),
                          height: 1,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'EST. PROFIT',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: const Color(0xFF22C55E).withValues(alpha: 0.7),
                          fontWeight: FontWeight.w600,
                          letterSpacing: 2,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              // StockX price chip
              Opacity(
                opacity: _chipsFade.value,
                child: _PriceChip(label: 'StockX', value: '\$247'),
              ),
            ],
          );
        },
      ),
      title: 'Know the profit\nbefore you buy',
      description:
          'See the potential profit instantly based on current resale prices. '
          'Know if a flip is worth it before you spend a dollar.',
    );
  }
}

class _PriceChip extends StatelessWidget {
  final String label;
  final String value;
  const _PriceChip({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white12),
      ),
      child: RichText(
        text: TextSpan(
          style: GoogleFonts.inter(fontSize: 14, color: Colors.white54),
          children: [
            TextSpan(text: '$label  →  '),
            TextSpan(
              text: value,
              style: GoogleFonts.inter(
                fontSize: 14,
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Page 4: Flip profit stats ─────────────────────────────────────────────────

class _FlipCardData {
  final String name;
  final String profit;
  const _FlipCardData(this.name, this.profit);
}

const _kFlipCards = [
  _FlipCardData('Jordan 1 Retro', '+\$85'),
  _FlipCardData('Yeezy Boost 350', '+\$110'),
  _FlipCardData('Nike Dunk Low', '+\$47'),
];

class _Page4 extends StatefulWidget {
  const _Page4();

  @override
  State<_Page4> createState() => _Page4State();
}

class _Page4State extends State<_Page4> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    );
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) _ctrl.forward();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _OnboardingPageLayout(
      visual: AnimatedBuilder(
        animation: _ctrl,
        builder: (context, _) {
          final t = _ctrl.value;

          // Stat ($40 – $120) fade-in
          final statP = ((t - 0.62) / 0.25).clamp(0.0, 1.0);
          final statEased = Curves.easeOut.transform(statP);

          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Profit range stat with glow
              Opacity(
                opacity: statEased,
                child: Text(
                  '\$40 – \$120',
                  style: GoogleFonts.poppins(
                    fontSize: 52,
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF22C55E),
                    height: 1,
                    shadows: [
                      Shadow(
                        color: const Color(
                          0xFF22C55E,
                        ).withValues(alpha: 0.55 * statEased),
                        blurRadius: 24,
                      ),
                      Shadow(
                        color: const Color(
                          0xFF22C55E,
                        ).withValues(alpha: 0.25 * statEased),
                        blurRadius: 48,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              // Flip cards stacking up
              ...List.generate(_kFlipCards.length, (i) {
                final start = 0.05 + i * 0.19;
                final end = start + 0.22;
                final p = ((t - start) / (end - start)).clamp(0.0, 1.0);
                final eased = Curves.easeOut.transform(p);
                return Opacity(
                  opacity: eased,
                  child: Transform.translate(
                    offset: Offset(0, 18 * (1 - eased)),
                    child: Container(
                      width: 280,
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 11,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1A1A2E),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white10),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: const Color(
                                0xFF22C55E,
                              ).withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(
                              Icons.directions_run_rounded,
                              color: Color(0xFF22C55E),
                              size: 16,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              _kFlipCards[i].name,
                              style: GoogleFonts.inter(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                          Text(
                            _kFlipCards[i].profit,
                            style: GoogleFonts.poppins(
                              color: const Color(0xFF22C55E),
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }),
            ],
          );
        },
      ),
      visualHeight: 270,
      title: 'Average sneaker\nflip profit',
      description: '',
    );
  }
}

// ── Pressable button ──────────────────────────────────────────────────────────

class _PressableButton extends StatefulWidget {
  final String label;
  final bool enabled;
  final VoidCallback onPressed;

  const _PressableButton({
    required this.label,
    required this.enabled,
    required this.onPressed,
  });

  @override
  State<_PressableButton> createState() => _PressableButtonState();
}

class _PressableButtonState extends State<_PressableButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final bgColor = widget.enabled
        ? const Color(0xFF646CFF)
        : const Color(0xFF646CFF).withValues(alpha: 0.30);
    final textColor = widget.enabled
        ? Colors.white
        : Colors.white.withValues(alpha: 0.40);

    return GestureDetector(
      onTapDown: widget.enabled ? (_) => setState(() => _pressed = true) : null,
      onTapUp: widget.enabled
          ? (_) {
              setState(() => _pressed = false);
              HapticFeedback.heavyImpact();
              widget.onPressed();
            }
          : null,
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: (_pressed && widget.enabled) ? 0.96 : 1.0,
        duration: const Duration(milliseconds: 80),
        curve: Curves.easeInOut,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: double.infinity,
          height: 56,
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(14),
          ),
          alignment: Alignment.center,
          child: Text(
            widget.label,
            style: GoogleFonts.poppins(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: textColor,
            ),
          ),
        ),
      ),
    );
  }
}

// ── Analysis screen ───────────────────────────────────────────────────────────

class _AnalysisScreen extends StatefulWidget {
  final Future<void> Function() onComplete;
  const _AnalysisScreen({required this.onComplete});

  @override
  State<_AnalysisScreen> createState() => _AnalysisScreenState();
}

class _AnalysisScreenState extends State<_AnalysisScreen>
    with SingleTickerProviderStateMixin {
  static const _steps = [
    'Detecting sneaker label',
    'Extracting SKU',
    'Matching sneaker database',
    'Checking StockX sales',
    'Checking GOAT listings',
    'Checking eBay sold prices',
    'Calculating profit',
  ];

  // 200ms initial delay + 350ms per step = ~2500ms for all steps
  // 700ms pause after last step → ~3200ms total before navigating
  static const _stepDelay = 350;
  static const _initialDelay = 200;
  static const _pauseAfterLastStep = 700;

  int _visibleSteps = 0;
  late final AnimationController _progressCtrl;

  @override
  void initState() {
    super.initState();

    final totalAnimMs =
        _initialDelay + (_steps.length - 1) * _stepDelay + _pauseAfterLastStep;

    _progressCtrl = AnimationController(
      duration: Duration(milliseconds: totalAnimMs),
      vsync: this,
    );

    // Show steps one by one
    for (int i = 0; i < _steps.length; i++) {
      Future.delayed(
        Duration(milliseconds: _initialDelay + i * _stepDelay),
        () {
          if (mounted) setState(() => _visibleSteps = i + 1);
        },
      );
    }

    _progressCtrl.forward();

    // Navigate after all steps appear + pause
    Future.delayed(Duration(milliseconds: totalAnimMs), () async {
      if (!mounted) return;
      await SubscriptionService.instance.awaitLaunchCheck();
      if (mounted) widget.onComplete();
    });
  }

  @override
  void dispose() {
    _progressCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D1A),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 36),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Sneaker icon
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: const Color(0xFF646CFF).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: const Icon(
                    Icons.directions_run_rounded,
                    color: Color(0xFF646CFF),
                    size: 36,
                  ),
                ),
                const SizedBox(height: 28),
                Text(
                  'Scanning sneaker\ndatabase…',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.poppins(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 32),
                // Progress bar
                AnimatedBuilder(
                  animation: _progressCtrl,
                  builder: (context, _) {
                    return ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: _progressCtrl.value,
                        backgroundColor: const Color(0xFF1A1A2E),
                        valueColor: const AlwaysStoppedAnimation(
                          Color(0xFF646CFF),
                        ),
                        minHeight: 6,
                      ),
                    );
                  },
                ),
                const SizedBox(height: 28),
                // Steps
                ...List.generate(
                  _steps.length,
                  (i) => _AnalysisStep(
                    label: _steps[i],
                    visible: i < _visibleSteps,
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

class _AnalysisStep extends StatelessWidget {
  final String label;
  final bool visible;
  const _AnalysisStep({required this.label, required this.visible});

  @override
  Widget build(BuildContext context) {
    return AnimatedSlide(
      offset: visible ? Offset.zero : const Offset(-0.4, 0),
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOut,
      child: AnimatedOpacity(
        opacity: visible ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 280),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(
            children: [
              const Icon(
                Icons.check_circle_rounded,
                color: Color(0xFF22C55E),
                size: 20,
              ),
              const SizedBox(width: 12),
              Text(
                label,
                style: GoogleFonts.inter(
                  fontSize: 15,
                  color: Colors.white,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
