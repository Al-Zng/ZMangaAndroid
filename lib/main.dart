import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'state/app_state.dart';
import 'screen/main_shell.dart';
import 'theme/app_theme.dart';
import 'utils/network_monitor.dart';

void main() {
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AppState()),
        ChangeNotifierProvider(create: (_) => NetworkMonitor()),
      ],
      child: const ZMangaApp(),
    ),
  );
}

class ZMangaApp extends StatelessWidget {
  const ZMangaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      home: const MainShell(),
    );
  }
}