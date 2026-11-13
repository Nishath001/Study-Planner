import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/ui.dart';
import 'forgot_password_screen.dart';
import 'splash_screen.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  bool _register = false;
  bool _busy = false;
  bool _showPass = false;
  String? _error;
  String? _success;
  int? _question;
  final _answer = TextEditingController();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _pass = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _pass.dispose();
    _answer.dispose();
    super.dispose();
  }

  String _message(AppState app, String code) => switch (code) {
        'name' => app.t('Please enter your name.', 'කරුණාකර ඔබේ නම ඇතුළත් කරන්න.'),
        'email' => app.t('Please enter a valid email.', 'වලංගු ඊමේල් ලිපිනයක් ඇතුළත් කරන්න.'),
        'password' => app.t('Password must be at least 6 characters.', 'මුරපදය අවම අකුරු 6ක් විය යුතුය.'),
        'exists' => app.t('This email is already registered. Sign in instead.', 'මෙම ඊමේල් දැනටමත් ලියාපදිංචියි. පිවිසෙන්න.'),
        'empty' => app.t('Please fill in all fields.', 'සියලු ක්ෂේත්‍ර පුරවන්න.'),
        'notfound' => app.t('No account found. Create one below.', 'ගිණුමක් හමු නොවීය. අලුතින් සාදන්න.'),
        'wrong' => app.t('Incorrect password. Forgot it? Tap "Forgot password?" below.',
            'මුරපදය වැරදියි. අමතකද? පහත "මුරපදය අමතකද?" ඔබන්න.'),
        'question' => app.t('Please choose a security question.', 'ආරක්ෂක ප්‍රශ්නයක් තෝරන්න.'),
        'credentials' => app.t('Email or password is incorrect.', 'ඊමේල් හෝ මුරපදය වැරදියි.'),
        'network' => app.t('No internet connection. Connect and try again.', 'අන්තර්ජාල සම්බන්ධතාවයක් නැත. නැවත උත්සාහ කරන්න.'),
        'toomany' => app.t('Too many attempts. Please wait a few minutes.', 'උත්සාහයන් වැඩියි. මිනිත්තු කිහිපයක් රැඳී සිටින්න.'),
        'disabled' => app.t('This account has been disabled.', 'මෙම ගිණුම අක්‍රිය කර ඇත.'),
        'notenabled' => app.t('Email sign-in is not enabled in Firebase yet (see FIREBASE_SETUP.md).',
            'Firebase හි ඊමේල් පිවිසුම තවම සක්‍රිය කර නැත.'),
        'answer' => app.t('Please answer your security question.', 'ඔබේ ආරක්ෂක ප්‍රශ්නයට පිළිතුරු දෙන්න.'),
        _ => app.t('Something went wrong.', 'දෝෂයක් සිදුවිය.'),
      };

  Future<void> _submit() async {
    final app = context.read<AppState>();
    setState(() {
      _busy = true;
      _error = null;
      _success = null;
    });
    if (_register) {
      final err = await app.register(_name.text, _email.text, _pass.text, questionId: _question, answer: _answer.text);
      if (!mounted) return;
      setState(() {
        _busy = false;
        if (err != null) {
          _error = _message(app, err);
          return;
        }
        // Registered: switch to Sign in with the email filled in.
        _register = false;
        _email.text = _email.text.trim().toLowerCase();
        _pass.clear();
        _name.clear();
        _answer.clear();
        _question = null;
        _showPass = false;
        _success = app.t('Account created! Sign in with your email and password.',
            'ගිණුම සාදන ලදී! ඔබේ ඊමේල් සහ මුරපදයෙන් පිවිසෙන්න.');
      });
      return;
    }
    final err = await app.signIn(_email.text, _pass.text);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = err == null ? null : _message(app, err);
    });
  }

  Future<void> _forgot() async {
    final app = context.read<AppState>();
    final email = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => ForgotPasswordScreen(initialEmail: _email.text.trim())),
    );
    if (email == null || !mounted) return;
    setState(() {
      _email.text = email;
      _pass.clear();
      _error = null;
      _success = app.cloudEnabled
          ? app.t('Reset link sent to $email. Set a new password from the email, then sign in here.',
              '$email වෙත සබැඳියක් යවන ලදී. ඊමේල් එකෙන් නව මුරපදයක් සකසා මෙහි පිවිසෙන්න.')
          : app.t('Password reset! Sign in with your new password.', 'මුරපදය යළි සකසන ලදී! නව මුරපදයෙන් පිවිසෙන්න.');
    });
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final p = context.pal;

    return Scaffold(
      body: Stack(children: [
        Container(
          height: 400,
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
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Column(children: [
                  const Align(alignment: Alignment.centerRight, child: LangToggle()),
                  const SizedBox(height: 8),
                  const AppLogo(size: 74),
                  const SizedBox(height: 16),
                  Text(
                    _register ? app.t('Create your account', 'ගිණුමක් සාදන්න') : app.t('Welcome back', 'නැවත සාදරයෙන් පිළිගනිමු'),
                    style: ts(26, w: FontWeight.w800, c: Colors.white),
                  ),
                  const SizedBox(height: 4),
                  Text(app.t('Plan smarter. Study calmer.', 'බුද්ධිමත්ව සැලසුම් කරන්න. සන්සුන්ව ඉගෙන ගන්න.'),
                      style: ts(13.5, c: Colors.white70)),
                  const SizedBox(height: 26),
                  AppCard(
                    padding: const EdgeInsets.all(20),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      _Segment(
                        left: app.t('Sign in', 'පිවිසෙන්න'),
                        right: app.t('Register', 'ලියාපදිංචිය'),
                        rightSelected: _register,
                        onChanged: (v) => setState(() {
                          _register = v;
                          _error = null;
                          _success = null;
                        }),
                      ),
                      const SizedBox(height: 20),
                      AnimatedSize(
                        duration: const Duration(milliseconds: 250),
                        curve: Curves.easeOutCubic,
                        child: _register
                            ? Padding(
                                padding: const EdgeInsets.only(bottom: 14),
                                child: TextField(
                                  controller: _name,
                                  textCapitalization: TextCapitalization.words,
                                  decoration: InputDecoration(
                                    hintText: app.t('Full name', 'සම්පූර්ණ නම'),
                                    prefixIcon: const Icon(Icons.person_outline_rounded),
                                  ),
                                ),
                              )
                            : const SizedBox(width: double.infinity),
                      ),
                      TextField(
                        controller: _email,
                        keyboardType: TextInputType.emailAddress,
                        autofillHints: const [AutofillHints.email],
                        decoration: InputDecoration(
                          hintText: app.t('Email address', 'ඊමේල් ලිපිනය'),
                          prefixIcon: const Icon(Icons.alternate_email_rounded),
                        ),
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: _pass,
                        obscureText: !_showPass,
                        onSubmitted: (_) => _submit(),
                        decoration: InputDecoration(
                          hintText: app.t('Password', 'මුරපදය'),
                          prefixIcon: const Icon(Icons.lock_outline_rounded),
                          suffixIcon: IconButton(
                            icon: Icon(_showPass ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                            onPressed: () => setState(() => _showPass = !_showPass),
                          ),
                        ),
                      ),
                      // Register: security question, used by "Forgot password?".
                      AnimatedSize(
                        duration: const Duration(milliseconds: 250),
                        curve: Curves.easeOutCubic,
                        // Firebase mode resets passwords by email, so no security question is needed.
                        child: !_register || app.cloudEnabled
                            ? const SizedBox(width: double.infinity)
                            : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                                const SizedBox(height: 14),
                                DropdownButtonFormField<int>(
                                  value: _question,
                                  isExpanded: true,
                                  borderRadius: BorderRadius.circular(16),
                                  dropdownColor: p.surface,
                                  decoration: InputDecoration(
                                    hintText: app.t('Security question', 'ආරක්ෂක ප්‍රශ්නය'),
                                    prefixIcon: const Icon(Icons.shield_outlined),
                                  ),
                                  items: [
                                    for (var i = 0; i < 6; i++)
                                      DropdownMenuItem(
                                        value: i,
                                        child: Text(app.securityQuestion(i),
                                            maxLines: 2, overflow: TextOverflow.ellipsis, style: ts(13.5, w: FontWeight.w600, c: p.text)),
                                      ),
                                  ],
                                  onChanged: (v) => setState(() => _question = v),
                                ),
                                const SizedBox(height: 14),
                                TextField(
                                  controller: _answer,
                                  decoration: InputDecoration(
                                    hintText: app.t('Your answer', 'ඔබේ පිළිතුර'),
                                    prefixIcon: const Icon(Icons.key_rounded),
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  app.t('Used to reset your password if you forget it.',
                                      'මුරපදය අමතක වුවහොත් යළි සැකසීමට භාවිතා වේ.'),
                                  style: ts(11.5, c: p.textMuted),
                                ),
                              ]),
                      ),
                      // Sign in: forgot password.
                      if (!_register)
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            style: TextButton.styleFrom(padding: const EdgeInsets.only(top: 8), minimumSize: Size.zero),
                            onPressed: _busy ? null : _forgot,
                            child: Text(app.t('Forgot password?', 'මුරපදය අමතකද?'),
                                style: ts(13, w: FontWeight.w800, c: AppColors.primary)),
                          ),
                        ),
                      if (_success != null) ...[
                        const SizedBox(height: 14),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppColors.green.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(children: [
                            const Icon(Icons.check_circle_rounded, color: AppColors.green, size: 18),
                            const SizedBox(width: 8),
                            Expanded(child: Text(_success!, style: ts(12.5, w: FontWeight.w700, c: AppColors.green))),
                          ]),
                        ),
                      ],
                      if (_error != null) ...[
                        const SizedBox(height: 14),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppColors.rose.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(children: [
                            const Icon(Icons.error_outline_rounded, color: AppColors.rose, size: 18),
                            const SizedBox(width: 8),
                            Expanded(child: Text(_error!, style: ts(12.5, w: FontWeight.w600, c: AppColors.rose))),
                          ]),
                        ),
                      ],
                      const SizedBox(height: 20),
                      GradientButton(
                        label: _register ? app.t('Create account', 'ගිණුම සාදන්න') : app.t('Sign in', 'පිවිසෙන්න'),
                        icon: Icons.arrow_forward_rounded,
                        loading: _busy,
                        onPressed: _submit,
                      ),
                      const SizedBox(height: 16),
                      Row(children: [
                        Expanded(child: Divider(color: p.border)),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Text(app.t('or', 'හෝ'), style: ts(12, c: p.textMuted)),
                        ),
                        Expanded(child: Divider(color: p.border)),
                      ]),
                      const SizedBox(height: 16),
                      OutlinedButton.icon(
                        onPressed: _busy ? null : app.continueAsGuest,
                        icon: const Icon(Icons.person_outline_rounded, size: 20),
                        label: Text(app.t('Continue as guest', 'අමුත්තෙකු ලෙස ඉදිරියට')),
                      ),
                    ]),
                  ),
                  const SizedBox(height: 18),
                  Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(Icons.lock_rounded, size: 13, color: p.textMuted),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        app.t('Your data stays on this device. Passwords are encrypted.',
                            'ඔබේ දත්ත මෙම උපාංගයේම පවතී. මුරපද සංකේතනය කර ඇත.'),
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

class _Segment extends StatelessWidget {
  final String left, right;
  final bool rightSelected;
  final ValueChanged<bool> onChanged;
  const _Segment({required this.left, required this.right, required this.rightSelected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Container(
      height: 46,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: p.surfaceAlt, borderRadius: BorderRadius.circular(14)),
      child: Stack(children: [
        AnimatedAlign(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutCubic,
          alignment: rightSelected ? Alignment.centerRight : Alignment.centerLeft,
          child: FractionallySizedBox(
            widthFactor: 0.5,
            child: Container(
              decoration: BoxDecoration(
                color: p.surface,
                borderRadius: BorderRadius.circular(11),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 8, offset: const Offset(0, 2))],
              ),
            ),
          ),
        ),
        Row(children: [
          for (final (i, label) in [left, right].indexed)
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onChanged(i == 1),
                child: Center(
                  child: Text(label,
                      style: ts(13.5, w: FontWeight.w700,
                          c: (i == 1) == rightSelected ? p.text : p.textMuted)),
                ),
              ),
            ),
        ]),
      ]),
    );
  }
}
