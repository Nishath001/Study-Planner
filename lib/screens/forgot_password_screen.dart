import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/ui.dart';

/// Offline password reset: email → security question → new password.
/// Pops with the email on success so the login page can prefill it.
class ForgotPasswordScreen extends StatefulWidget {
  final String initialEmail;
  const ForgotPasswordScreen({super.key, this.initialEmail = ''});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  late final _email = TextEditingController(text: widget.initialEmail);
  final _answer = TextEditingController();
  final _pass = TextEditingController();
  final _confirm = TextEditingController();
  int? _question;
  bool _busy = false, _show = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _answer.dispose();
    _pass.dispose();
    _confirm.dispose();
    super.dispose();
  }

  String _message(AppState app, String code) {
    final n = code.contains(':') ? code.split(':').last : '';
    return switch (code.split(':').first) {
      'email' => app.t('Please enter a valid email.', 'වලංගු ඊමේල් ලිපිනයක් ඇතුළත් කරන්න.'),
      'notfound' => app.t('No account found with this email.', 'මෙම ඊමේල් සමඟ ගිණුමක් නැත.'),
      'noquestion' => app.t(
          'This account has no security question yet. If you remember your password, sign in and add one in Profile.',
          'මෙම ගිණුමට ආරක්ෂක ප්‍රශ්නයක් නැත. මුරපදය මතක නම්, පිවිස පැතිකඩෙහි එකක් එක් කරන්න.'),
      'locked' => app.t('Too many wrong answers. Try again in $n min.', 'වැරදි පිළිතුරු වැඩියි. මිනිත්තු $n කින් නැවත උත්සාහ කරන්න.'),
      'wrong_answer' => app.t('That answer is not correct. $n attempt${n == '1' ? '' : 's'} left.',
          'පිළිතුර වැරදියි. තවත් උත්සාහ $n ක් ඉතිරියි.'),
      'password' => app.t('Password must be at least 6 characters.', 'මුරපදය අවම අකුරු 6ක් විය යුතුය.'),
      'mismatch' => app.t("Passwords don't match.", 'මුරපද නොගැළපේ.'),
      'empty' => app.t('Please enter your answer.', 'ඔබේ පිළිතුර ඇතුළත් කරන්න.'),
      _ => app.t('Something went wrong.', 'දෝෂයක් සිදුවිය.'),
    };
  }

  /// Firebase mode: one step — send the reset email.
  Future<void> _sendLink() async {
    final app = context.read<AppState>();
    setState(() {
      _busy = true;
      _error = null;
    });
    final err = await app.sendPasswordReset(_email.text);
    if (!mounted) return;
    if (err == null) {
      Navigator.pop(context, _email.text.trim().toLowerCase());
      return;
    }
    setState(() {
      _busy = false;
      _error = switch (err) {
        'email' => _message(app, 'email'),
        'notfound' => _message(app, 'notfound'),
        'network' => app.t('No internet connection. Connect and try again.', 'අන්තර්ජාල සම්බන්ධතාවයක් නැත.'),
        'toomany' => app.t('Too many requests. Please wait a few minutes.', 'ඉල්ලීම් වැඩියි. මිනිත්තු කිහිපයක් රැඳී සිටින්න.'),
        _ => _message(app, 'unknown'),
      };
    });
  }

  void _findAccount() {
    final app = context.read<AppState>();
    final (q, err) = app.recoveryQuestion(_email.text);
    setState(() {
      _error = err == null ? null : _message(app, err);
      _question = q;
    });
  }

  Future<void> _reset() async {
    final app = context.read<AppState>();
    String? err;
    if (_answer.text.trim().isEmpty) {
      err = 'empty';
    } else if (_pass.text.length < 6) {
      err = 'password';
    } else if (_pass.text != _confirm.text) {
      err = 'mismatch';
    }
    if (err == null) {
      setState(() => _busy = true);
      err = await app.resetPassword(_email.text, _answer.text, _pass.text);
      if (!mounted) return;
    }
    if (err == null) {
      Navigator.pop(context, _email.text.trim().toLowerCase());
      return;
    }
    setState(() {
      _busy = false;
      _error = _message(app, err!);
      if (err.startsWith('locked')) _question = null; // back to step 1
    });
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final p = context.pal;
    final step2 = _question != null;

    return Scaffold(
      body: Stack(children: [
        Container(
          height: 330,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF312E81), Color(0xFF4F46E5), Color(0xFF7C3AED)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.vertical(bottom: Radius.circular(40)),
          ),
        ),
        SafeArea(
          child: Align(
            alignment: Alignment.topCenter,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Column(children: [
                  Row(children: [
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                    ),
                    const Spacer(),
                    const LangToggle(),
                  ]),
                  const SizedBox(height: 4),
                  Container(
                    width: 74,
                    height: 74,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.16),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: Colors.white.withOpacity(0.3), width: 1.5),
                    ),
                    child: const Icon(Icons.lock_reset_rounded, color: Colors.white, size: 38),
                  ),
                  const SizedBox(height: 16),
                  Text(app.t('Reset your password', 'මුරපදය යළි සකසන්න'), style: ts(26, w: FontWeight.w800, c: Colors.white)),
                  const SizedBox(height: 4),
                  Text(
                    app.cloudEnabled
                        ? app.t("We'll email you a link to set a new password", 'නව මුරපදයක් සැකසීමට සබැඳියක් ඊමේල් කරමු')
                        : step2
                        ? app.t('Answer your security question', 'ඔබේ ආරක්ෂක ප්‍රශ්නයට පිළිතුරු දෙන්න')
                        : app.t('Enter the email you registered with', 'ලියාපදිංචි වූ ඊමේල් ලිපිනය ඇතුළත් කරන්න'),
                    textAlign: TextAlign.center,
                    style: ts(13.5, c: Colors.white70),
                  ),
                  const SizedBox(height: 26),
                  AppCard(
                    padding: const EdgeInsets.all(20),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      if (!app.cloudEnabled) ...[
                        _Steps(step: step2 ? 2 : 1,
                            labels: (app.t('Find account', 'ගිණුම'), app.t('New password', 'නව මුරපදය'))),
                        const SizedBox(height: 20),
                      ],
                      TextField(
                        controller: _email,
                        enabled: !step2,
                        keyboardType: TextInputType.emailAddress,
                        onSubmitted: (_) => app.cloudEnabled ? _sendLink() : _findAccount(),
                        decoration: InputDecoration(
                          hintText: app.t('Email address', 'ඊමේල් ලිපිනය'),
                          prefixIcon: const Icon(Icons.alternate_email_rounded),
                          suffixIcon: step2
                              ? IconButton(
                                  tooltip: app.t('Change email', 'ඊමේල් වෙනස් කරන්න'),
                                  icon: const Icon(Icons.edit_rounded, size: 18),
                                  onPressed: () => setState(() {
                                    _question = null;
                                    _error = null;
                                  }),
                                )
                              : null,
                        ),
                      ),
                      AnimatedSize(
                        duration: const Duration(milliseconds: 280),
                        curve: Curves.easeOutCubic,
                        child: !step2
                            ? const SizedBox(width: double.infinity)
                            : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                                const SizedBox(height: 16),
                                Container(
                                  padding: const EdgeInsets.all(14),
                                  decoration: BoxDecoration(
                                    color: AppColors.primary.withOpacity(p.isDark ? 0.16 : 0.08),
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  child: Row(children: [
                                    const Icon(Icons.help_outline_rounded, color: AppColors.primary, size: 20),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(app.securityQuestion(_question!),
                                          style: ts(13.5, w: FontWeight.w700, c: p.text, h: 1.4)),
                                    ),
                                  ]),
                                ),
                                const SizedBox(height: 12),
                                TextField(
                                  controller: _answer,
                                  autofocus: true,
                                  decoration: InputDecoration(
                                    hintText: app.t('Your answer', 'ඔබේ පිළිතුර'),
                                    prefixIcon: const Icon(Icons.key_rounded),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                TextField(
                                  controller: _pass,
                                  obscureText: !_show,
                                  onChanged: (_) => setState(() {}),
                                  decoration: InputDecoration(
                                    hintText: app.t('New password (min 6)', 'නව මුරපදය (අවම 6)'),
                                    prefixIcon: const Icon(Icons.lock_outline_rounded),
                                    suffixIcon: IconButton(
                                      icon: Icon(_show ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                                      onPressed: () => setState(() => _show = !_show),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                _Strength(password: _pass.text),
                                const SizedBox(height: 12),
                                TextField(
                                  controller: _confirm,
                                  obscureText: !_show,
                                  onSubmitted: (_) => _reset(),
                                  decoration: InputDecoration(
                                    hintText: app.t('Confirm new password', 'නව මුරපදය තහවුරු කරන්න'),
                                    prefixIcon: const Icon(Icons.lock_rounded),
                                  ),
                                ),
                              ]),
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 14),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppColors.rose.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            const Icon(Icons.error_outline_rounded, color: AppColors.rose, size: 18),
                            const SizedBox(width: 8),
                            Expanded(child: Text(_error!, style: ts(12.5, w: FontWeight.w600, c: AppColors.rose, h: 1.4))),
                          ]),
                        ),
                      ],
                      const SizedBox(height: 20),
                      GradientButton(
                        label: app.cloudEnabled
                            ? app.t('Send reset link', 'යළි සැකසීමේ සබැඳිය යවන්න')
                            : step2
                                ? app.t('Reset password', 'මුරපදය යළි සකසන්න')
                                : app.t('Continue', 'ඉදිරියට'),
                        icon: app.cloudEnabled
                            ? Icons.mark_email_read_rounded
                            : (step2 ? Icons.check_rounded : Icons.arrow_forward_rounded),
                        loading: _busy,
                        onPressed: app.cloudEnabled ? _sendLink : (step2 ? _reset : _findAccount),
                      ),
                    ]),
                  ),
                  const SizedBox(height: 18),
                  Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(Icons.shield_outlined, size: 14, color: p.textMuted),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        app.cloudEnabled
                            ? app.t('Check your spam folder if the email does not arrive in a few minutes.',
                                'ඊමේල් නොලැබුණොත් spam ෆෝල්ඩරය බලන්න.')
                            : app.t('Your answer is encrypted on this device. 5 wrong answers lock reset for 15 minutes.',
                                'ඔබේ පිළිතුර මෙම උපාංගයේ සංකේතනය කර ඇත. වැරදි පිළිතුරු 5කින් මිනිත්තු 15ක් අගුළු වැටේ.'),
                        textAlign: TextAlign.center,
                        style: ts(11.5, c: p.textMuted),
                      ),
                    ),
                  ]),
                ]),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}

class _Steps extends StatelessWidget {
  final int step;
  final (String, String) labels;
  const _Steps({required this.step, required this.labels});

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    Widget dot(int n, String label) {
      final active = step >= n;
      return Expanded(
        child: Row(children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              gradient: active ? AppColors.brandGradient : null,
              color: active ? null : p.surfaceAlt,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: step > n
                  ? const Icon(Icons.check_rounded, size: 16, color: Colors.white)
                  : Text('$n', style: ts(12, w: FontWeight.w800, c: active ? Colors.white : p.textMuted)),
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: ts(12.5, w: FontWeight.w700, c: active ? p.text : p.textMuted)),
          ),
        ]),
      );
    }

    return Row(children: [
      dot(1, labels.$1),
      Container(width: 24, height: 2, margin: const EdgeInsets.symmetric(horizontal: 6),
          color: step > 1 ? AppColors.primary : p.border),
      dot(2, labels.$2),
    ]);
  }
}

/// Simple password strength hint.
class _Strength extends StatelessWidget {
  final String password;
  const _Strength({required this.password});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    var score = 0;
    if (password.length >= 6) score++;
    if (password.length >= 10) score++;
    if (RegExp(r'[0-9]').hasMatch(password) && RegExp(r'[A-Za-z]').hasMatch(password)) score++;
    if (RegExp(r'[^A-Za-z0-9]').hasMatch(password) || RegExp(r'[A-Z]').hasMatch(password)) score++;
    final (label, color) = switch (score) {
      0 || 1 => (app.t('Weak', 'දුර්වල'), AppColors.rose),
      2 => (app.t('Fair', 'සාමාන්‍ය'), AppColors.amber),
      3 => (app.t('Good', 'හොඳයි'), AppColors.teal),
      _ => (app.t('Strong', 'ශක්තිමත්'), AppColors.green),
    };
    if (password.isEmpty) return const SizedBox.shrink();
    return Row(children: [
      for (var i = 0; i < 4; i++)
        Expanded(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            height: 5,
            margin: const EdgeInsets.only(right: 4),
            decoration: BoxDecoration(
              color: i < score ? color : context.pal.surfaceAlt,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ),
      const SizedBox(width: 6),
      Text(label, style: ts(11.5, w: FontWeight.w800, c: color)),
    ]);
  }
}
