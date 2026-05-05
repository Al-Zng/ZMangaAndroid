import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'app_state.dart';
import 'screen/home_screen.dart';
import 'screen/cloudflare_sheet.dart';
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
  @override
  void initState() {
    super.initState();
    // مراقبة الحالة وعرض Cloudflare Sheet عند الحاجة
    final state = context.read<AppState>();
    state.addListener(_checkCloudflare);
  }

  void _checkCloudflare() {
    final state = context.read<AppState>();
    if (state.showCloudflareSheet) {
      // إذا كانت شاشة الكلاودفلير ليست معروضة بالفعل
      if (Navigator.canPop(context)) return; // تم فتحها بالفعل
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => const CloudflareSheet(),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ZTheme.darkTheme,
      home: const HomeScreen(),
    );
  }
}