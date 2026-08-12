import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../strings.dart';

/// Sign in with Google, email or phone.
///
/// Reached only from Settings, and never forced: the app has always worked
/// signed out and must keep doing so. An account buys a backup, nothing else.
class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key, required this.auth});

  final AuthService auth;

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

enum _Mode { pick, email, phone, code }

class _SignInScreenState extends State<SignInScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _phone = TextEditingController();
  final _code = TextEditingController();

  _Mode _mode = _Mode.pick;
  String? _error;
  bool _busy = false;
  bool _newAccount = false;
  String? _verificationId;

  @override
  void dispose() {
    for (final c in [_email, _password, _phone, _code]) {
      c.dispose();
    }
    super.dispose();
  }

  String _message(AuthFailure f) => switch (f.kind) {
    AuthError.wrongPassword => AppStrings.authWrongPassword,
    AuthError.network => AppStrings.offline,
    AuthError.needsLinking => AppStrings.authNeedsLinking,
    _ => f.detail ?? AppStrings.authFailed,
  };

  /// Wraps an action with the busy flag and error handling.
  ///
  /// A cancelled Google sheet resolves silently: backing out is a decision,
  /// not a failure, and showing a red banner for it is just wrong.
  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
      if (mounted) Navigator.of(context).pop(true);
    } on AuthFailure catch (f) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = f.kind == AuthError.cancelled ? null : _message(f);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = '$e';
      });
    }
  }

  Future<void> _sendCode() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    await widget.auth.startPhoneSignIn(
      _phone.text,
      onCodeSent: (id) {
        if (!mounted) return;
        setState(() {
          _verificationId = id;
          _mode = _Mode.code;
          _busy = false;
        });
      },
      onFailed: (f) {
        if (!mounted) return;
        setState(() {
          _busy = false;
          _error = _message(f);
        });
      },
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(AppStrings.signInTitle)),
    body: Padding(
      padding: const EdgeInsets.all(16),
      child: _busy
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                Text(AppStrings.signInWhy),
                const SizedBox(height: 24),
                if (_error != null) ...[
                  Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                ...switch (_mode) {
                  _Mode.pick => _pick(),
                  _Mode.email => _emailForm(),
                  _Mode.phone => _phoneForm(),
                  _Mode.code => _codeForm(),
                },
              ],
            ),
    ),
  );

  List<Widget> _pick() => [
    FilledButton.icon(
      icon: const Icon(Icons.account_circle_outlined),
      label: Text(AppStrings.signInGoogle),
      onPressed: () => _run(widget.auth.signInWithGoogle),
    ),
    const SizedBox(height: 12),
    OutlinedButton.icon(
      icon: const Icon(Icons.mail_outline),
      label: Text(AppStrings.signInEmail),
      onPressed: () => setState(() => _mode = _Mode.email),
    ),
    const SizedBox(height: 12),
    OutlinedButton.icon(
      icon: const Icon(Icons.phone_outlined),
      label: Text(AppStrings.signInPhone),
      onPressed: () => setState(() => _mode = _Mode.phone),
    ),
  ];

  List<Widget> _emailForm() => [
    TextField(
      controller: _email,
      keyboardType: TextInputType.emailAddress,
      autocorrect: false,
      decoration: InputDecoration(labelText: AppStrings.emailLabel),
    ),
    const SizedBox(height: 12),
    TextField(
      controller: _password,
      obscureText: true,
      decoration: InputDecoration(labelText: AppStrings.passwordLabel),
    ),
    const SizedBox(height: 16),
    FilledButton(
      onPressed: () => _run(
        () => _newAccount
            ? widget.auth.signUpWithEmail(_email.text, _password.text)
            : widget.auth.signInWithEmail(_email.text, _password.text),
      ),
      child: Text(
        _newAccount ? AppStrings.createAccount : AppStrings.signInTitle,
      ),
    ),
    TextButton(
      onPressed: () => setState(() => _newAccount = !_newAccount),
      child: Text(
        _newAccount ? AppStrings.haveAccount : AppStrings.needAccount,
      ),
    ),
    TextButton(
      onPressed: () async {
        await widget.auth.sendPasswordReset(_email.text);
        if (mounted) setState(() => _error = AppStrings.resetSent);
      },
      child: Text(AppStrings.forgotPassword),
    ),
  ];

  List<Widget> _phoneForm() => [
    TextField(
      controller: _phone,
      keyboardType: TextInputType.phone,
      decoration: InputDecoration(
        labelText: AppStrings.phoneLabel,
        // Firebase rejects anything without a country code, and the error it
        // gives back is unhelpful, so say it here instead.
        hintText: '+62…',
      ),
    ),
    const SizedBox(height: 16),
    FilledButton(onPressed: _sendCode, child: Text(AppStrings.sendCode)),
  ];

  List<Widget> _codeForm() => [
    Text(AppStrings.codeSentTo(_phone.text)),
    const SizedBox(height: 12),
    TextField(
      controller: _code,
      keyboardType: TextInputType.number,
      decoration: InputDecoration(labelText: AppStrings.codeLabel),
    ),
    const SizedBox(height: 16),
    FilledButton(
      onPressed: () => _run(
        () => widget.auth.confirmPhoneCode(_verificationId!, _code.text),
      ),
      child: Text(AppStrings.confirmCode),
    ),
  ];
}
