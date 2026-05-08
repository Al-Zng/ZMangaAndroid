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
  bool _solved = false;
  bool _closed = false;
  bool _isLoading = true;
  Timer? _checkTimer;
  int _consecutiveClean = 0;

  // JS يُخفي علامات WebView عن Cloudflare
  static const String _stealthJS = '''
(function() {
  // أخفِ webdriver
  Object.defineProperty(navigator, 'webdriver', {
    get: () => undefined,
    configurable: true
  });

  // أضف plugins مثل Safari
  Object.defineProperty(navigator, 'plugins', {
    get: () => {
      const arr = [
        { name: 'PDF Viewer', filename: 'internal-pdf-viewer', description: 'Portable Document Format' },
        { name: 'Chrome PDF Viewer', filename: 'mhjfbmdgcfjbbpaeojofohoefgiehjai', description: '' },
        { name: 'Chromium PDF Viewer', filename: 'internal-pdf-viewer', description: '' },
      ];
      arr.item = i => arr[i];
      arr.namedItem = name => arr.find(p => p.name === name) || null;
      arr.refresh = () => {};
      Object.setPrototypeOf(arr, PluginArray.prototype);
      return arr;
    },
    configurable: true
  });

  // languages
  Object.defineProperty(navigator, 'languages', {
    get: () => ['ar', 'ar-SA', 'en-US', 'en'],
    configurable: true
  });

  // platform مثل iPhone
  Object.defineProperty(navigator, 'platform', {
    get: () => 'iPhone',
    configurable: true
  });

  // vendor
  Object.defineProperty(navigator, 'vendor', {
    get: () => 'Apple Computer, Inc.',
    configurable: true
  });

  // maxTouchPoints
  Object.defineProperty(navigator, 'maxTouchPoints', {
    get: () => 5,
    configurable: true
  });

  // hardwareConcurrency
  Object.defineProperty(navigator, 'hardwareConcurrency', {
    get: () => 4,
    configurable: true
  });

  // deviceMemory
  try {
    Object.defineProperty(navigator, 'deviceMemory', {
      get: () => 4,
      configurable: true
    });
  } catch(e) {}

  // connection
  try {
    Object.defineProperty(navigator, 'connection', {
      get: () => ({ effectiveType: '4g', rtt: 50, downlink: 10, saveData: false }),
      configurable: true
    });
  } catch(e) {}

  // أخفِ chrome object
  try {
    if (window.chrome) {
      window.chrome = undefined;
    }
  } catch(e) {}

  // permissions — Cloudflare يفحصها
  if (navigator.permissions) {
    const originalQuery = navigator.permissions.query.bind(navigator.permissions);
    navigator.permissions.query = (parameters) => {
      if (parameters.name === 'notifications') {
        return Promise.resolve({ state: 'denied', onchange: null });
      }
      return originalQuery(parameters);
    };
  }

  // أصلح toString لإخفاء التعديلات
  const nativeToString = Function.prototype.toString;
  Function.prototype.toString = function() {
    if (this === navigator.permissions?.query) {
      return 'function query() { [native code] }';
    }
    return nativeToString.call(this);
  };

})();
''';

  String get _baseDomain {
    try {
      return Uri.parse(widget.url).host;
    } catch (_) {
      return '';
    }
  }

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent(AppUserAgent.iosSafari)
      // حقن الـ stealth script قبل أي JS من الصفحة
      ..addJavaScriptChannel(
        'FlutterBridge',
        onMessageReceived: (_) {},
      )
      ..setNavigationDelegate(NavigationDelegate(
        onPageStarted: (_) {
          _checkTimer?.cancel();
          _consecutiveClean = 0;
          if (mounted) setState(() => _isLoading = true);
          // حقن الـ stealth JS فور بداية التحميل
          _controller.runJavaScript(_stealthJS).catchError((_) {});
        },
        onPageFinished: (url) {
          if (mounted) setState(() => _isLoading = false);
          // حقن مرة ثانية بعد اكتمال التحميل
          _controller.runJavaScript(_stealthJS).catchError((_) {});
          if (!_solved && !_closed) {
            _scheduleCheck();
          }
        },
        onNavigationRequest: (_) => NavigationDecision.navigate,
      ))
      ..loadRequest(Uri.parse(widget.url));
  }

  void _scheduleCheck() {
    _checkTimer?.cancel();
    _checkTimer = Timer(const Duration(seconds: 2), _performCheck);
  }

  Future<void> _performCheck() async {
    if (_solved || _closed || !mounted) return;

    try {
      final rawTitle = await _controller.runJavaScriptReturningResult(
        'document.title || ""',
      );
      final title = rawTitle.toString()
          .replaceAll('"', '')
          .toLowerCase()
          .trim();

      final isChallenge = _isChallengeTitle(title);

      if (!isChallenge) {
        _consecutiveClean++;
        if (_consecutiveClean >= 2) {
          _checkTimer?.cancel();
          await _extractAndSolve();
        } else {
          _checkTimer = Timer(const Duration(seconds: 1), _performCheck);
        }
      } else {
        _consecutiveClean = 0;
        // لا تعد جدولة — انتظر onPageFinished القادم
      }
    } catch (e) {
      debugPrint('CF check: $e');
    }
  }

  bool _isChallengeTitle(String title) {
    if (title.isEmpty) return true;
    const challengeWords = [
      'just a moment', 'cloudflare', 'checking',
      'please wait', 'attention required', 'لحظة',
      'one moment', 'security check', 'ddos',
    ];
    return challengeWords.any((w) => title.contains(w));
  }

  Future<void> _extractAndSolve() async {
    if (_solved || _closed) return;
    try {
      final cookieResult = await _controller.runJavaScriptReturningResult(
        r'(function(){ try{ return document.cookie || ""; }catch(e){ return ""; } })()',
      );
      final jsCookies = cookieResult.toString().replaceAll('"', '').trim();
      if (jsCookies.isNotEmpty && jsCookies != 'null') {
        await CookieService().saveCookies(jsCookies, _baseDomain);
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

  void _handleClose() {
    if (_closed) return;
    _finalize(solved: false);
  }

  @override
  void dispose() {
    _checkTimer?.cancel();
    super.dispose();
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
            _header(),
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

  Widget _header() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            const Icon(Icons.shield_outlined, size: 20, color: Colors.orange),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('تحقق من الأمان',
                      style: TextStyle(
                          fontSize: 15, fontWeight: FontWeight.bold)),
                  Text(
                    _isLoading
                        ? 'جارٍ التحميل...'
                        : 'اضغط على "أنا لست روبوتاً" ثم انتظر',
                    style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                  ),
                ],
              ),
            ),
            if (_isLoading)
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            const SizedBox(width: 10),
            GestureDetector(
              onTap: _handleClose,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.withOpacity(0.3)),
                ),
                child: const Text('إغلاق',
                    style: TextStyle(
                        color: Colors.redAccent,
                        fontSize: 13,
                        fontWeight: FontWeight.w500)),
              ),
            ),
          ],
        ),
      );
}
