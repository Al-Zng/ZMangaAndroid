import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../utils/network_monitor.dart';
import '../widgets/cloudflare_bypass_sheet.dart';
import 'home_screen.dart';
import 'search_screen.dart';
import 'library_screen.dart';
import 'downloads_screen.dart';
import 'history_screen.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> with WidgetsBindingObserver {
  int _currentIndex = 0;
  bool _isShowingCloudflare = false;

  // ✅ FIX BG: نتتبع وقت الدخول للخلفية لمنع إعادة التحقق الغير ضرورية
  DateTime? _lastBackgroundTime;

  final List<Widget> _tabs = const [
    HomeScreen(),
    SearchScreen(),
    LibraryScreen(),
    DownloadsScreen(),
    HistoryScreen(),
  ];

  // ─── أيكونات outlined/filled مطابقة لنسخة iOS ────────────────
  static const _navItems = [
    _NavItem(icon: Icons.home_outlined,       activeIcon: Icons.home,              label: 'Home'),
    _NavItem(icon: Icons.search,              activeIcon: Icons.search,             label: 'Search'),
    _NavItem(icon: Icons.library_books_outlined, activeIcon: Icons.library_books,  label: 'Library'),
    _NavItem(icon: Icons.download_outlined,   activeIcon: Icons.download,           label: 'Downloads'),
    _NavItem(icon: Icons.access_time_outlined,activeIcon: Icons.access_time_filled, label: 'History'),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // ✅ FIX BG: مراقبة دورة حياة التطبيق
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _lastBackgroundTime = DateTime.now();
    } else if (state == AppLifecycleState.resumed) {
      _onAppResumed();
    }
  }

  void _onAppResumed() {
    if (_lastBackgroundTime == null) return;
    final bgDuration = DateTime.now().difference(_lastBackgroundTime!);

    // ✅ FIX BG: إذا كان التطبيق في الخلفية لأقل من 3 دقائق، لا نُعيد التحقق
    // فقط إذا تجاوز 3 دقائق نتحقق من CF
    if (bgDuration.inMinutes >= 3) {
      // أعد تعيين حالة CF لتجنب خلفية WebView معطلة
      final appState = context.read<AppState>();
      appState.markCfExpiredFromBackground();
    }
  }

  void _showCloudflareBypass(BuildContext context, AppState appState) {
    if (_isShowingCloudflare) return;
    _isShowingCloudflare = true;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => CloudflareBypassSheet(
        url: appState.cloudflareURL!,
        appState: appState,
      ),
    ).whenComplete(() => _isShowingCloudflare = false);
  }

  @override
  Widget build(BuildContext context) {
    final net = context.watch<NetworkMonitor>();
    final appState = context.watch<AppState>();

    if (appState.showCloudflareSheet && appState.cloudflareURL != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_isShowingCloudflare) {
          _showCloudflareBypass(context, appState);
        }
      });
    }

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        systemNavigationBarColor: AppTheme.surface,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: AppTheme.bg,
        body: IndexedStack(index: _currentIndex, children: _tabs),
        bottomNavigationBar: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ─── شريط بدون اتصال ──────────────────────────────────
            if (!net.isConnected)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
                color: Colors.red.withOpacity(0.9),
                child: const Row(
                  children: [
                    Icon(Icons.wifi_off, color: Colors.white, size: 14),
                    SizedBox(width: 8),
                    Text('No Internet Connection',
                        style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w500)),
                  ],
                ),
              ),
            // ─── شريط التنقل ──────────────────────────────────────
            Container(
              decoration: const BoxDecoration(
                color: AppTheme.surface,
                border: Border(top: BorderSide(color: AppTheme.border, width: 0.5)),
              ),
              child: SafeArea(
                top: false,
                child: BottomNavigationBar(
                  currentIndex: _currentIndex,
                  onTap: (i) => setState(() => _currentIndex = i),
                  backgroundColor: Colors.transparent,
                  selectedItemColor: AppTheme.accent,
                  unselectedItemColor: AppTheme.textTertiary,
                  type: BottomNavigationBarType.fixed,
                  elevation: 0,
                  selectedFontSize: 10,
                  unselectedFontSize: 10,
                  items: List.generate(_navItems.length, (i) {
                    final item = _navItems[i];
                    return BottomNavigationBarItem(
                      icon: Icon(i == _currentIndex ? item.activeIcon : item.icon),
                      label: item.label,
                    );
                  }),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NavItem {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  const _NavItem({required this.icon, required this.activeIcon, required this.label});
}
