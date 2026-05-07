import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'app_state.dart';
import 'screens/home_screen.dart';
import 'screens/manga_detail_screen.dart';
import 'screens/chapter_reader_screen.dart';
import 'screens/library_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/cloudflare_bypass_sheet.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  if (Platform.isAndroid) {
    await InAppWebViewController.setWebContentsDebuggingEnabled(false);
    
    AndroidInAppWebViewController.setWebContentsDebuggingEnabled(false);
  }
  
  final prefs = await SharedPreferences.getInstance();
  
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AppState>(
          create: (_) => AppState(prefs),
        ),
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
      title: 'ZManga',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1A1A2E),
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: const Color(0xFF0F0F1A),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF1A1A2E),
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        cardTheme: CardTheme(
          color: const Color(0xFF1A1A2E),
          elevation: 4,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFF2A2A3E),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFE94560)),
          ),
        ),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
      onGenerateRoute: (settings) {
        if (settings.name == '/manga_detail') {
          final mangaUrl = settings.arguments as String;
          return MaterialPageRoute(
            builder: (_) => MangaDetailScreen(mangaUrl: mangaUrl),
          );
        }
        if (settings.name == '/chapter_reader') {
          final args = settings.arguments as Map<String, dynamic>;
          return MaterialPageRoute(
            builder: (_) => ChapterReaderScreen(
              chapterUrl: args['chapterUrl'] as String,
              mangaTitle: args['mangaTitle'] as String,
              chapterTitle: args['chapterTitle'] as String,
            ),
          );
        }
        if (settings.name == '/library') {
          return MaterialPageRoute(
            builder: (_) => const LibraryScreen(),
          );
        }
        if (settings.name == '/settings') {
          return MaterialPageRoute(
            builder: (_) => const SettingsScreen(),
          );
        }
        return null;
      },
    );
  }
}