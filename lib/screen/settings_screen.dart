import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../services/download_manager.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();

    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        backgroundColor: AppTheme.surface,
        title: const Text('Settings',
            style: TextStyle(color: AppTheme.textPrimary)),
      ),
      body: ListView(
        children: [
          const SizedBox(height: 8),

          // ─── وضع الأجهزة الضعيفة ─────────────────────────────────
          _sectionHeader('⚡ Performance'),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            decoration: BoxDecoration(
              color: AppTheme.accentDim,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.accent.withOpacity(0.3)),
            ),
            child: SwitchListTile(
              // ✅ FIX: وضع الأجهزة الضعيفة — يُحسّن الأداء ويقلل التعليق
              title: const Text('وضع الأجهزة الضعيفة',
                  style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.bold)),
              subtitle: const Text(
                  'يُقلل التحميل التلقائي ويُبسّط التنقل بين الفصول — مناسب للأجهزة البطيئة',
                  style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
              value: appState.lowEndMode,
              onChanged: (val) => appState.setLowEndMode(val),
              activeColor: AppTheme.accent,
              secondary: Icon(
                appState.lowEndMode ? Icons.bolt : Icons.phone_android,
                color: AppTheme.accent,
              ),
            ),
          ),
          const SizedBox(height: 4),
          SwitchListTile(
            title: const Text('Reduce Motion',
                style: TextStyle(color: AppTheme.textPrimary)),
            subtitle: const Text('يُقلل الأنيميشن لتحسين الأداء',
                style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
            value: appState.reduceMotion,
            onChanged: (val) => appState.setReduceMotion(val),
            activeColor: AppTheme.accent,
            secondary: const Icon(Icons.animation, color: AppTheme.textSecondary),
          ),
          const Divider(color: AppTheme.border),

          // ─── Reading ─────────────────────────────────────────────
          _sectionHeader('Reading'),
          SwitchListTile(
            // ✅ FIX: متصل بـ AppState
            title: const Text('Auto-load next chapter',
                style: TextStyle(color: AppTheme.textPrimary)),
            subtitle: const Text('يحمل الفصل التالي تلقائياً أثناء القراءة',
                style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
            value: appState.autoLoadNextChapter,
            onChanged: (val) => appState.setAutoLoadNextChapter(val),
            activeColor: AppTheme.accent,
            secondary:
                const Icon(Icons.auto_stories, color: AppTheme.textSecondary),
          ),
          SwitchListTile(
            title: const Text('Keep Screen On While Reading',
                style: TextStyle(color: AppTheme.textPrimary)),
            value: appState.keepScreenOn,
            onChanged: (val) => appState.setKeepScreenOn(val),
            activeColor: AppTheme.accent,
            secondary: const Icon(Icons.screen_lock_portrait,
                color: AppTheme.textSecondary),
          ),
          const Divider(color: AppTheme.border),

          // ─── Storage ─────────────────────────────────────────────
          _sectionHeader('Storage'),
          ListTile(
            leading:
                const Icon(Icons.delete_sweep, color: AppTheme.danger),
            title: const Text('Delete All Downloads',
                style: TextStyle(color: AppTheme.danger)),
            onTap: () => _confirmDeleteDownloads(context),
          ),
          const Divider(color: AppTheme.border),

          // ─── About ───────────────────────────────────────────────
          _sectionHeader('About'),
          const ListTile(
            leading: Icon(Icons.info_outline, color: AppTheme.textSecondary),
            title: Text('Version',
                style: TextStyle(color: AppTheme.textPrimary)),
            trailing: Text('1.0',
                style: TextStyle(color: AppTheme.textTertiary)),
          ),
          const Divider(color: AppTheme.border),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _sectionHeader(String title) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Text(title,
            style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: AppTheme.textSecondary,
                letterSpacing: 1.5)),
      );

  void _confirmDeleteDownloads(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: const Text('Delete All Downloads',
            style: TextStyle(color: AppTheme.textPrimary)),
        content: const Text('Are you sure? This cannot be undone.',
            style: TextStyle(color: AppTheme.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel',
                style: TextStyle(color: AppTheme.textSecondary)),
          ),
          TextButton(
            onPressed: () {
              DownloadManager.shared.removeAllDownloads();
              Navigator.pop(context);
            },
            child: const Text('Delete',
                style: TextStyle(color: AppTheme.danger)),
          ),
        ],
      ),
    );
  }
}
