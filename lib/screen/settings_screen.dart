import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../services/download_manager.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        backgroundColor: AppTheme.surface,
        title: const Text('Settings', style: TextStyle(color: AppTheme.textPrimary)),
      ),
      body: ListView(
        children: [
          const SizedBox(height: 8),
          _section('Reading', [
            SwitchListTile(
              title: const Text('Auto-load next chapter', style: TextStyle(color: AppTheme.textPrimary)),
              value: true,
              onChanged: (val) {},
              activeColor: AppTheme.accent,
              secondary: const Icon(Icons.auto_stories, color: AppTheme.textSecondary),
            ),
          ]),
          _section('Storage', [
            ListTile(
              leading: const Icon(Icons.cached, color: AppTheme.textSecondary),
              title: const Text('Image Cache', style: TextStyle(color: AppTheme.textPrimary)),
              trailing: Text(_formatBytes(0), style: const TextStyle(color: AppTheme.textSecondary)),
            ),
            ListTile(
              leading: const Icon(Icons.download, color: AppTheme.textSecondary),
              title: const Text('Downloads', style: TextStyle(color: AppTheme.textPrimary)),
              trailing: Text(_formatBytes(0), style: const TextStyle(color: AppTheme.textSecondary)),
            ),
            ListTile(
              leading: const Icon(Icons.delete_sweep, color: AppTheme.danger),
              title: const Text('Clear Image Cache', style: TextStyle(color: AppTheme.danger)),
              onTap: () {},
            ),
            ListTile(
              leading: const Icon(Icons.delete_forever, color: AppTheme.danger),
              title: const Text('Delete All Downloads', style: TextStyle(color: AppTheme.danger)),
              onTap: () => DownloadManager.shared.removeAllDownloads(), // ✅
            ),
          ]),
          _section('About', [
            ListTile(
              leading: const Icon(Icons.info_outline, color: AppTheme.textSecondary),
              title: const Text('Version', style: TextStyle(color: AppTheme.textPrimary)),
              trailing: const Text('1.0', style: TextStyle(color: AppTheme.textTertiary)),
            ),
          ]),
        ],
      ),
    );
  }

  Widget _section(String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text(title, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.textSecondary, letterSpacing: 1.5)),
        ),
        ...children,
        const Divider(color: AppTheme.border),
      ],
    );
  }

  String _formatBytes(int bytes) => '0 KB';
}