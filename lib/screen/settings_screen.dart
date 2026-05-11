import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../services/download_manager.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppState>();
    final dm = context.watch<DownloadManager>();

    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        backgroundColor: AppTheme.surface,
        title: Text('Settings', style: GoogleFonts.inter(color: AppTheme.textPrimary, fontWeight: FontWeight.w600, fontSize: 17)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: AppTheme.textSecondary, size: 18),
          onPressed: () => Navigator.pop(context)),
      ),
      body: ListView(children: [

        // ─── Reading ────────────────────────────────────────────────
        _section('Reading'),
        _toggle('Auto-load next chapter', 'Loads the next chapter as you reach the end',
          store.autoLoadNextChapter, (v) => store.setAutoLoadNextChapter(v)),
        _toggle('Keep Screen On While Reading', null,
          store.keepScreenOn, (v) => store.setKeepScreenOn(v)),
        _toggle('Reduce Motion', 'Fewer animations for a calmer experience',
          store.reduceMotion, (v) => store.setReduceMotion(v)),
        const Divider(color: AppTheme.border, height: 1),

        // ─── Storage ────────────────────────────────────────────────
        _section('Storage'),
        _infoRow('Downloaded Chapters', '${dm.downloadedChapterCount} chapters'),
        ListTile(
          leading: const Icon(Icons.delete_sweep_outlined, color: AppTheme.danger),
          title: Text('Delete All Downloads', style: GoogleFonts.inter(color: AppTheme.danger, fontSize: 15)),
          onTap: () => _confirmDelete(context, dm),
        ),
        const Divider(color: AppTheme.border, height: 1),

        // ─── About ──────────────────────────────────────────────────
        _section('About'),
        _infoRow('Version', '1.0.0'),
        _infoRow('Source', 'lekmanga.site'),
        const SizedBox(height: 40),
      ]),
    );
  }

  Widget _section(String title) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 20, 16, 6),
    child: Text(title.toUpperCase(),
        style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700,
            color: AppTheme.textSecondary, letterSpacing: 1.5)),
  );

  Widget _toggle(String title, String? subtitle, bool value, ValueChanged<bool> onChanged) =>
    SwitchListTile(
      title: Text(title, style: GoogleFonts.inter(color: AppTheme.textPrimary, fontSize: 15)),
      subtitle: subtitle != null
          ? Text(subtitle, style: GoogleFonts.inter(color: AppTheme.textTertiary, fontSize: 12))
          : null,
      value: value,
      onChanged: onChanged,
      activeColor: AppTheme.accent,
    );

  Widget _infoRow(String label, String value) => ListTile(
    title: Text(label, style: GoogleFonts.inter(color: AppTheme.textPrimary, fontSize: 15)),
    trailing: Text(value, style: GoogleFonts.inter(color: AppTheme.textSecondary, fontSize: 14)),
  );

  void _confirmDelete(BuildContext context, DownloadManager dm) {
    showDialog(context: context, builder: (_) => AlertDialog(
      backgroundColor: AppTheme.surface,
      title: Text('Delete All Downloads', style: GoogleFonts.inter(color: AppTheme.textPrimary, fontWeight: FontWeight.w600)),
      content: Text('This will delete all downloaded chapters permanently.',
          style: GoogleFonts.inter(color: AppTheme.textSecondary)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context),
          child: Text('Cancel', style: GoogleFonts.inter(color: AppTheme.textSecondary))),
        TextButton(onPressed: () { dm.removeAllDownloads(); Navigator.pop(context); },
          child: Text('Delete', style: GoogleFonts.inter(color: AppTheme.danger, fontWeight: FontWeight.w600))),
      ],
    ));
  }
}
