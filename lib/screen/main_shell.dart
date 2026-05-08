import 'package:flutter/material.dart';
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

// مطابق لـ iOS ContentView
class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _currentIndex = 0;
  bool _isShowingCloudflare = false;

  final List<Widget> _tabs = const [
    HomeScreen(),
    SearchScreen(),
    LibraryScreen(),
    DownloadsScreen(),
    HistoryScreen(),
  ];

  // مطابق لـ iOS: .sheet(item: $store.activeChallenge)
  void _showCloudflareSheet(AppState appState) {
    if (_isShowingCloudflare || appState.cloudflareURL == null) return;
    _isShowingCloudflare = true;
    final cfUrl = appState.cloudflareURL!;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: const Color(0xFF1C1C1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      builder: (_) => CloudflareBypassSheet(
        url: cfUrl,
        appState: appState,
      ),
    ).whenComplete(() {
      _isShowingCloudflare = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final net = context.watch<NetworkMonitor>();
    final appState = context.watch<AppState>();

    // مثل iOS .sheet(item: $store.activeChallenge)
    if (appState.showCloudflareSheet && appState.cloudflareURL != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showCloudflareSheet(appState);
      });
    }

    return Scaffold(
      backgroundColor: AppTheme.bg,
      body: IndexedStack(
        index: _currentIndex,
        children: _tabs,
      ),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!net.isConnected)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
              color: Colors.black.withOpacity(0.9),
              child: const Row(
                children: [
                  Icon(Icons.wifi_off, color: Colors.white, size: 16),
                  SizedBox(width: 8),
                  Text('No Internet Connection',
                      style: TextStyle(color: Colors.white, fontSize: 13)),
                ],
              ),
            ),
          BottomNavigationBar(
            currentIndex: _currentIndex,
            onTap: (index) => setState(() => _currentIndex = index),
            backgroundColor: AppTheme.surface,
            selectedItemColor: AppTheme.accent,
            unselectedItemColor: AppTheme.textTertiary,
            type: BottomNavigationBarType.fixed,
            items: const [
              BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
              BottomNavigationBarItem(
                  icon: Icon(Icons.search), label: 'Search'),
              BottomNavigationBarItem(
                  icon: Icon(Icons.library_books), label: 'Library'),
              BottomNavigationBarItem(
                  icon: Icon(Icons.download), label: 'Downloads'),
              BottomNavigationBarItem(
                  icon: Icon(Icons.history), label: 'History'),
            ],
          ),
        ],
      ),
    );
  }
}
