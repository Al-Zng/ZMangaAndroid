import 'package:flutter/material.dart';
import '../theme.dart';
import 'home_screen.dart';
import 'search_screen.dart';
import 'library_screen.dart';
import 'history_screen.dart';
import 'cloudflare_sheet.dart'; // لاستيراد CloudflareSheet (قد لا تحتاجه هنا لكنه موجود في main)

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _currentIndex = 0;

  final List<Widget> _tabs = const [
    HomeScreen(),
    SearchScreen(),
    LibraryScreen(),
    HistoryScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ZTheme.bg,
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
        backgroundColor: ZTheme.surface,
        selectedItemColor: ZTheme.accent,
        unselectedItemColor: ZTheme.textTertiary,
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
          BottomNavigationBarItem(icon: Icon(Icons.search), label: 'Search'),
          BottomNavigationBarItem(icon: Icon(Icons.library_books), label: 'Library'),
          BottomNavigationBarItem(icon: Icon(Icons.history), label: 'History'),
        ],
      ),
      body: IndexedStack(
        index: _currentIndex,
        children: _tabs,
      ),
    );
  }
}