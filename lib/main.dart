import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'app_state.dart';
import 'screen/home_screen.dart';      // ✅ عدل من screens إلى screen
import 'theme.dart';

void main() {
  runApp(
    ChangeNotifierProvider(
      create: (_) => AppState(),
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
      theme: ZTheme.darkTheme,
      home: HomeScreen(),
    );
  }
}