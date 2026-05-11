import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'state/app_state.dart';
import 'theme/app_theme.dart';
import 'utils/network_monitor.dart';
import 'services/download_manager.dart';
import 'screen/main_shell.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ✅ OPT: ضبط image cache — 200MB disk, 100MB memory
  PaintingBinding.instance.imageCache.maximumSize      = 150;
  PaintingBinding.instance.imageCache.maximumSizeBytes = 100 * 1024 * 1024;

  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: AppTheme.surface,
  ));

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AppState()),
        ChangeNotifierProvider(create: (_) => NetworkMonitor.shared),
        ChangeNotifierProvider.value(value: DownloadManager.shared),
      ],
      child: const ZMangaApp(),
    ),
  );
}

class ZMangaApp extends StatelessWidget {
  const ZMangaApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: AppTheme.darkTheme,
    home: const MainShell(),
    // ✅ OPT: إيقاف banner التصحيح وتحسين performance
    builder: (context, child) => ScrollConfiguration(
      behavior: _NoGlowScrollBehavior(),
      child: child!,
    ),
  );
}

// ✅ OPT: إزالة Glow effect الافتراضي على Android (مطابق iOS)
class _NoGlowScrollBehavior extends ScrollBehavior {
  @override
  Widget buildOverscrollIndicator(BuildContext context, Widget child, ScrollableDetails details) => child;
}
