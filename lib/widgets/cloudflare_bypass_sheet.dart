import 'dart:async';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../state/app_state.dart';
import '../core/cloudflare/cookie_service.dart';
import '../core/network/user_agent.dart';

class CloudflareBypassSheet extends StatefulWidget {
  final String url;
  final AppState appState;

  const CloudflareBypassSheet({
    super.key,
    required this.url,
    required this.appState,
  });

  @override
  State<CloudflareBypassSheet> createState() => _CloudflareBypassSheetState();
}

class _CloudflareBypassSheetState extends State<CloudflareBypassSheet> {
  late WebViewController _controller;
  bool _solved  = false;
  bool _closed  = false;
  bool _isLoading   = true;
  bool _isVerifying = false; // نحن في مرحلة التحقق بعد اكتشاف صفحة نظيفة
  int  _consecutiveClean = 0;
  int  _challengeRound   = 1; // عدد جولات CF
  Timer? _checkTimer;

  // ─── Stealth JS مبسّط ────────────────────────────────────────────
  // نخفي webdriver فقط — أي تعديل إضافي يسبب تناقض fingerprint
  static const String _stealthJS = r'''
(function(){
  try {
    Object.defineProperty(navigator, 'webdriver', {
      get: () => undefined,
      configurable: true
    });
  } catch(e) {}
})();
''';

  // ─── اكتشاف صفحة CF عبر JS (أدق من title فقط) ──────────────────
  static const String _cfDetectJS = r'''
(function(){
  try { if (typeof window._cf_chl_opt !== 'undefined') return 'challenge'; } catch(e){}
  var t = (document.title || '').toLowerCase();
  if (!t) return 'challenge';
  var w = ['just a moment','cloudflare','checking','please wait',
           'attention required','one moment','security check','ddos','لحظة'];
  if (w.some(function(x){ return t.indexOf(x) !== -1; })) return 'challenge';
  return 'clean';
})()
''';

  String get _baseDomain {
    try { return Uri.parse(widget.url).host; } catch (_) { return ''; }
  }

  @override
  void initState() {
    super.initState();

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      // ✅ Android Chrome UA — متوافق مع fingerprint الـ WebView الفعلي
      ..setUserAgent(AppUserAgent.androidChrome)
      ..addJavaScriptChannel('FlutterBridge', onMessageReceived: (_) {})
      ..setNavigationDelegate(NavigationDelegate(
        onPageStarted: (_) {
          _checkTimer?.cancel();
          // لا نعيد _consecutiveClean هنا — فقط في _performCheck عند اكتشاف تحدي فعلي
          if (mounted) setState(() { _isLoading = true; _isVerifying = false; });
          _controller.runJavaScript(_stealthJS).catchError((_) {});
        },
        onPageFinished: (url) {
          if (mounted) setState(() => _isLoading = false);
          _controller.runJavaScript(_stealthJS).catchError((_) {});
          if (!_solved && !_closed) _scheduleCheck();
        },
        onNavigationRequest: (_) => NavigationDecision.navigate,
      ))
      ..loadRequest(Uri.parse(widget.url));
  }

  // ─── جدولة الفحص ────────────────────────────────────────────────
  void _scheduleCheck() {
    _checkTimer?.cancel();
    // 3 ثوانٍ أولى قبل الفحص — Cloudflare يحتاج وقتاً بعد تحميل الصفحة
    _checkTimer = Timer(const Duration(seconds: 3), _performCheck);
  }

  Future<void> _performCheck() async {
    if (_solved || _closed || !mounted) return;
    try {
      final raw = await _controller
          .runJavaScriptReturningResult(_cfDetectJS);
      final result = raw.toString().replaceAll('"', '').trim();
      final isChallenge = result != 'clean';

      if (!isChallenge) {
        _consecutiveClean++;
        if (mounted) setState(() => _isVerifying = true);

        if (_consecutiveClean >= 3) {
          // ✅ ثلاثة فحوصات نظيفة متتالية (3×3s = 9s) — نتحقق ونغلق
          _checkTimer?.cancel();
          await _extractAndSolve();
        } else {
          // فحص بعد 3 ثوانٍ إضافية
          _checkTimer = Timer(const Duration(seconds: 3), _performCheck);
        }
      } else {
        // ─── اكتُشف تحدي ────────────────────────────────────────
        // لو كنا في مرحلة التحقق، معناه CF بدأ جولة جديدة
        if (_isVerifying || _consecutiveClean > 0) {
          if (mounted) setState(() => _challengeRound++);
        }
        _consecutiveClean = 0;
        if (mounted) setState(() => _isVerifying = false);
        // لا نعيد الجدولة — ننتظر onPageFinished القادم
      }
    } catch (e) {
      debugPrint('CF check: $e');
    }
  }

  Future<void> _extractAndSolve() async {
    if (_solved || _closed) return;

    // ✅ انتظار إضافي — Cloudflare يحتاج وقتاً لضبط cf_clearance بعد اكتمال التحدي
    await Future.delayed(const Duration(seconds: 5));
    if (_solved || _closed || !mounted) return;

    // تحقق نهائي: هل الصفحة لا تزال نظيفة؟
    try {
      final raw = await _controller
          .runJavaScriptReturningResult(_cfDetectJS);
      final result = raw.toString().replaceAll('"', '').trim();
      if (result != 'clean') {
        // CF لا يزال نشطاً — ارجع للانتظار
        if (mounted) setState(() { _consecutiveClean = 0; _isVerifying = false; });
        return;
      }
    } catch (_) {}

    // استخرج الكوكيز المتاحة بـ JS (cf_clearance هي HttpOnly — لن تظهر)
    // لكن cf_clearance موجودة في Android cookie store المشترك
    try {
      final cookieResult = await _controller.runJavaScriptReturningResult(
        r'(function(){ try{ return document.cookie||""; }catch(e){ return ""; } })()',
      );
      final cookies = cookieResult.toString().replaceAll('"', '').trim();
      if (cookies.isNotEmpty && cookies != 'null') {
        await CookieService().saveCookies(cookies, _baseDomain);
      }
    } catch (e) {
      debugPrint('Cookie save: $e');
    }

    await _finalize(solved: true);
  }

  Future<void> _finalize({required bool solved}) async {
    if (_closed) return;
    _closed = true;
    _solved = solved;
    _checkTimer?.cancel();
    if (solved) {
      widget.appState.onCloudflareSolved();
    } else {
      widget.appState.onCloudflareDismissed();
    }
    if (mounted) Navigator.of(context).pop(solved);
  }

  void _handleClose() { if (!_closed) _finalize(solved: false); }

  @override
  void dispose() {
    _checkTimer?.cancel();
    super.dispose();
  }

  // ─── UI Helpers ─────────────────────────────────────────────────

  String get _titleText {
    if (_challengeRound > 1) return 'تحقق الأمان — الجولة $_challengeRound';
    return 'تحقق من الأمان';
  }

  String get _subtitleText {
    if (_isLoading)    return 'جارٍ التحميل...';
    if (_isVerifying)  return '⏳ جارٍ التحقق... لا تغلق النافذة';
    if (_challengeRound > 1) {
      return 'جولة جديدة — اضغط على المربع وانتظر ✓';
    }
    return 'اضغط على "أنا لست روبوتاً" ثم انتظر';
  }

  Color get _statusColor {
    if (_isVerifying) return Colors.green;
    if (_challengeRound > 1) return Colors.amber[700]!;
    return Colors.orange;
  }

  IconData get _statusIcon {
    if (_isVerifying) return Icons.verified_outlined;
    return Icons.shield_outlined;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvoked: (_) => _handleClose(),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.88,
        child: Column(
          children: [
            _buildHeader(),
            // ─── شريط الجولات لو أكثر من جولة واحدة ───────────────
            if (_challengeRound > 1) _buildRoundsBar(),
            Expanded(
              child: Stack(
                children: [
                  WebViewWidget(controller: _controller),
                  if (_isLoading)
                    Container(
                      color: Colors.black.withOpacity(0.04),
                      child: const Center(child: CircularProgressIndicator()),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() => Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    decoration: BoxDecoration(
      color: Theme.of(context).scaffoldBackgroundColor,
      boxShadow: [BoxShadow(
        color: Colors.black.withOpacity(0.08),
        blurRadius: 4, offset: const Offset(0, 2),
      )],
    ),
    child: Row(
      children: [
        Icon(_statusIcon, size: 20, color: _statusColor),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_titleText,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
              Text(_subtitleText,
                style: TextStyle(fontSize: 11,
                  color: _isVerifying ? Colors.green[700] : Colors.grey[500])),
            ],
          ),
        ),
        if (_isLoading || _isVerifying)
          SizedBox(width: 16, height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: _isVerifying ? Colors.green : null,
            )),
        const SizedBox(width: 10),
        GestureDetector(
          onTap: _handleClose,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.red.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.red.withOpacity(0.3)),
            ),
            child: const Text('إغلاق',
              style: TextStyle(color: Colors.redAccent,
                fontSize: 13, fontWeight: FontWeight.w500)),
          ),
        ),
      ],
    ),
  );

  Widget _buildRoundsBar() => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    color: Colors.amber.withOpacity(0.1),
    child: Row(
      children: [
        Icon(Icons.info_outline, size: 14, color: Colors.amber[800]),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            'هذا الموقع يطلب عدة جولات من التحقق — هذا طبيعي، استمر في الحل',
            style: TextStyle(fontSize: 11, color: Colors.amber[900]),
          ),
        ),
      ],
    ),
  );
}
