import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../state/app_state.dart';

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
  bool _isLoading = true;
  int _navCount = 0;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent(
        'Mozilla/5.0 (Linux; Android 13; Pixel 7) '
        'AppleWebKit/537.36 (KHTML, like Gecko) '
        'Chrome/120.0.0.0 Mobile Safari/537.36',
      )
      ..setNavigationDelegate(NavigationDelegate(
        onPageStarted: (_) {
          if (mounted) setState(() => _isLoading = true);
        },
        onPageFinished: (url) {
          if (mounted) setState(() => _isLoading = false);
          _didFinishNavigation(url);
        },
        onNavigationRequest: (_) => NavigationDecision.navigate,
      ))
      ..loadRequest(Uri.parse(widget.url));
  }

  Future<void> _didFinishNavigation(String currentUrl) async {
    if (_solved) return;
    _navCount++;

    await Future.delayed(const Duration(milliseconds: 800));
    if (_solved || !mounted) return;

    await _checkTitleAndSucceed();
  }

  Future<void> _checkTitleAndSucceed() async {
    if (_solved) return;
    try {
      final rawTitle =
          await _controller.runJavaScriptReturningResult('document.title');
      final title =
          rawTitle.toString().replaceAll('"', '').toLowerCase().trim();

      final isCloudflare = title.contains('just a moment') ||
          title.contains('attention required') ||
          title.contains('checking your browser') ||
          title.contains('cloudflare') ||
          title.contains('please wait');

      if (!isCloudflare && title.isNotEmpty) {
        await _succeed();
      }
    } catch (_) {}
  }

  Future<void> _succeed() async {
    if (_solved) return;
    _solved = true;

    // استخرج الكوكيز من الـ WebView وأرسلها لـ AppState
    String? cookies;
    try {
      final result = await _controller.runJavaScriptReturningResult(
        r'(function(){ try{ return document.cookie || ""; }catch(e){ return ""; } })()',
      );
      final raw = result.toString().replaceAll('"', '').trim();
      if (raw.isNotEmpty && raw != 'null') cookies = raw;
    } catch (_) {}

    widget.appState.onCloudflareSolved(cookies: cookies);

    if (mounted) {
      await Future.delayed(const Duration(milliseconds: 100));
      if (mounted) Navigator.of(context).pop(true);
    }
  }

  void _cancel() {
    if (_solved) return;
    widget.appState.onCloudflareDismissed();
    Navigator.of(context).pop(false);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvoked: (_) => _cancel(),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.88,
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: const Color(0xFF1C1C1E),
                border: Border(
                    bottom:
                        BorderSide(color: Colors.white.withOpacity(0.08))),
              ),
              child: Column(
                children: [
                  Container(
                    width: 36,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Row(
                    children: [
                      TextButton(
                        onPressed: _cancel,
                        style: TextButton.styleFrom(
                          foregroundColor: const Color(0xFFCC8C14),
                          padding: EdgeInsets.zero,
                        ),
                        child: const Text('إغلاق',
                            style: TextStyle(fontSize: 15)),
                      ),
                      const Spacer(),
                      if (_isLoading)
                        const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Color(0xFFCC8C14)),
                        )
                      else
                        const Icon(Icons.shield_outlined,
                            color: Color(0xFFCC8C14), size: 18),
                      const SizedBox(width: 8),
                      const Text(
                        'تحقق من الأمان',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                      const Spacer(),
                      TextButton(
                        onPressed: _solved ? null : _succeed,
                        style: TextButton.styleFrom(
                          foregroundColor: const Color(0xFFCC8C14),
                          padding: EdgeInsets.zero,
                        ),
                        child: const Text('تم',
                            style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'أكمل التحقق أدناه للمتابعة',
                    style: TextStyle(
                        fontSize: 12,
                        color: Colors.white.withOpacity(0.4)),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Stack(
                children: [
                  WebViewWidget(controller: _controller),
                  if (_isLoading)
                    Container(
                      color: const Color(0xFF0F0F0F).withOpacity(0.6),
                      child: const Center(
                        child: CircularProgressIndicator(
                            color: Color(0xFFCC8C14)),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
