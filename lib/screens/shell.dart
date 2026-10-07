import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/ui.dart';
import 'ai_planner_screen.dart';
import 'focus_screen.dart';
import 'home_screen.dart';
import 'insights_screen.dart';
import 'plan_screen.dart';

/// Lets any screen switch tabs or hand a task to the focus timer.
class ShellNav extends ChangeNotifier {
  int index = 0;
  StudyTask? focusTask;

  void go(int i) {
    index = i;
    notifyListeners();
  }

  void startFocus(StudyTask? task) {
    focusTask = task;
    go(3);
  }
}

class MainShell extends StatefulWidget {
  final int initialIndex;
  const MainShell({super.key, this.initialIndex = 0});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> with WidgetsBindingObserver {
  late final _nav = ShellNav()..index = widget.initialIndex;
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Keep "missed" status fresh so the adaptive planner can react.
    _tick = Timer.periodic(const Duration(minutes: 1), (_) => context.read<AppState>().markMissed());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.resumed) context.read<AppState>().markMissed();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tick?.cancel();
    _nav.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    return ChangeNotifierProvider.value(
      value: _nav,
      child: Consumer<ShellNav>(
        builder: (context, nav, _) => Scaffold(
          extendBody: true,
          body: IndexedStack(
            index: nav.index,
            children: const [HomeScreen(), PlanScreen(), AIPlannerScreen(), FocusScreen(), InsightsScreen()],
          ),
          bottomNavigationBar: _NavBar(
            index: nav.index,
            onTap: nav.go,
            items: [
              (Icons.space_dashboard_outlined, Icons.space_dashboard_rounded, app.t('Today', 'අද')),
              (Icons.calendar_month_outlined, Icons.calendar_month_rounded, app.t('Plan', 'සැලැස්ම')),
              (Icons.auto_awesome_outlined, Icons.auto_awesome_rounded, 'AI'),
              (Icons.timer_outlined, Icons.timer_rounded, app.t('Focus', 'අවධානය')),
              (Icons.insights_outlined, Icons.insights_rounded, app.t('Insights', 'විශ්ලේෂණ')),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavBar extends StatelessWidget {
  final int index;
  final ValueChanged<int> onTap;
  final List<(IconData, IconData, String)> items;
  const _NavBar({required this.index, required this.onTap, required this.items});

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return SafeArea(
      minimum: const EdgeInsets.fromLTRB(14, 0, 14, 12),
      child: Container(
        height: 70,
        decoration: BoxDecoration(
          color: p.surface,
          borderRadius: BorderRadius.circular(26),
          border: Border.all(color: p.border),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(p.isDark ? 0.4 : 0.08),
              blurRadius: 30,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Row(
          children: List.generate(items.length, (i) {
            final sel = i == index;
            final item = items[i];
            if (i == 2) {
              return Expanded(
                child: GestureDetector(
                  onTap: () => onTap(i),
                  child: Center(
                    child: AnimatedScale(
                      scale: sel ? 1.06 : 1,
                      duration: const Duration(milliseconds: 200),
                      child: Container(
                        width: 54,
                        height: 54,
                        decoration: BoxDecoration(
                          gradient: AppColors.aiGradient,
                          borderRadius: BorderRadius.circular(18),
                          boxShadow: [
                            BoxShadow(color: AppColors.violet.withOpacity(0.45), blurRadius: 16, offset: const Offset(0, 6)),
                          ],
                        ),
                        child: const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 26),
                      ),
                    ),
                  ),
                ),
              );
            }
            return Expanded(
              child: InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: () => onTap(i),
                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                    decoration: BoxDecoration(
                      color: sel ? AppColors.primary.withOpacity(0.12) : Colors.transparent,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(sel ? item.$2 : item.$1, size: 23, color: sel ? AppColors.primary : p.textMuted),
                  ),
                  const SizedBox(height: 3),
                  Text(item.$3,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: ts(10.5, w: sel ? FontWeight.w800 : FontWeight.w600, c: sel ? AppColors.primary : p.textMuted)),
                ]),
              ),
            );
          }),
        ),
      ),
    );
  }
}
