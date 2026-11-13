import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/suggestion_engine.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import 'ui.dart';

class SuggestionCard extends StatefulWidget {
  final Suggestion suggestion;
  const SuggestionCard({super.key, required this.suggestion});

  @override
  State<SuggestionCard> createState() => _SuggestionCardState();
}

class _SuggestionCardState extends State<SuggestionCard> {
  bool _busy = false;

  Future<void> _act(bool apply) async {
    final app = context.read<AppState>();
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    if (apply) {
      await app.applySuggestion(widget.suggestion);
      messenger.showSnackBar(SnackBar(content: Text(app.t('Suggestion applied', 'යෝජනාව යොදන ලදී'))));
    } else {
      await app.dismissSuggestion(widget.suggestion);
      messenger.showSnackBar(SnackBar(
          content: Text(app.t("Got it — you'll see fewer like this", 'හරි — මෙවැනි යෝජනා අඩුවෙන් පෙන්වයි'))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final p = context.pal;
    final s = widget.suggestion;
    final impact = s.impact >= 0.6
        ? (app.t('High impact', 'ඉහළ බලපෑම'), AppColors.rose)
        : s.impact >= 0.4
            ? (app.t('Medium impact', 'මධ්‍යම බලපෑම'), AppColors.amber)
            : (app.t('Small win', 'කුඩා වාසියක්'), AppColors.teal);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AppCard(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            IconBadge(s.icon, s.color, size: 42, radius: 13),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(s.title, style: ts(14.5, w: FontWeight.w800, c: p.text, h: 1.3)),
                const SizedBox(height: 6),
                Pill(impact.$1, impact.$2),
              ]),
            ),
          ]),
          const SizedBox(height: 12),
          Text(s.body, style: ts(13, c: p.textSoft, h: 1.5)),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(color: p.surfaceAlt, borderRadius: BorderRadius.circular(10)),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.insights_rounded, size: 15, color: s.color),
              const SizedBox(width: 8),
              Expanded(child: Text(s.why, style: ts(12, w: FontWeight.w600, c: p.textSoft, h: 1.4))),
            ]),
          ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: _busy ? null : () => _act(true),
                icon: const Icon(Icons.check_rounded, size: 18),
                label: Text(app.t('Apply', 'යොදන්න')),
                style: FilledButton.styleFrom(
                  backgroundColor: s.color,
                  minimumSize: const Size(0, 42),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton(
                onPressed: _busy ? null : () => _act(false),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 42),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: Text(app.t('Not now', 'දැන් නොවේ')),
              ),
            ),
          ]),
        ]),
      ),
    );
  }
}
