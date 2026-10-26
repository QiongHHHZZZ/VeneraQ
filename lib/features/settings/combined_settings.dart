import 'package:flutter/material.dart';
import 'package:venera_next/components/appbar.dart';
import 'package:venera_next/components/scroll.dart';
import 'package:venera_next/features/settings/debug.dart';
import 'package:venera_next/features/settings/logs.dart';
import 'package:venera_next/features/settings/setting_components.dart';
import 'package:venera_next/foundation/context.dart';
import 'package:venera_next/foundation/translations.dart';

/// Diagnostics in a single scroll view: debug controls, then the log viewer.
class DiagnosticsSettings extends StatelessWidget {
  const DiagnosticsSettings({super.key});

  @override
  Widget build(BuildContext context) {
    return Material(
      child: SmoothCustomScrollView(
        slivers: [
          SliverAppbar(title: Text("Advanced & Diagnostics".tl)),
          const SettingPartTitle(title: "Debug", icon: Icons.bug_report),
          const DebugPage(embedded: true),
          const SettingPartTitle(title: "Logs", icon: Icons.article_outlined),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              child: FilledButton.tonalIcon(
                onPressed: () => context.to(() => const LogsPage()),
                icon: const Icon(Icons.article_outlined),
                label: Text("Open Log".tl),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
