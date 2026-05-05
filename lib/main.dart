import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'app_state.dart';
import 'screen/main_shell.dart';
import 'screen/cloudflare_sheet.dart';   // ✅ import مهم
import 'theme.dart';

void main() {
  runApp(
    ChangeNotifierProvider(
      create: (_) => AppState(),
      child: const ZMangaApp(),
    ),
  );
}

class ZMangaApp extends StatefulWidget {
  const ZMangaApp({super.key});

  @override
  State<ZMangaApp> createState() => _ZMangaAppState();
}

class _ZMangaAppState extends State<ZMangaApp> {
  bool _cloudflareOpen = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final state = context.read<AppState>();
      state.addListener(_checkCloudflare);
    });
  }

  @override
  void dispose() {
    context.read<AppState>().removeListener(_checkCloudflare);
    super.dispose();
  }

  void _checkCloudflare() {
    final state = context.read<AppState>();
    if (!state.showCloudflareSheet || _cloudflareOpen) return;
    _cloudflareOpen = true;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => CloudflareSheet(),   // ✅ إزالة const
          settings: const RouteSettings(name: '/cloudflare'),
        ),
      ).then((_) {
        _cloudflareOpen = false;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ZTheme.darkTheme,
      home: const MainShell(),
    );
  }
}