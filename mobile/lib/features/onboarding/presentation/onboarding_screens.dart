import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../../core/localization/app_language.dart';
import '../../../core/localization/app_strings.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/permissions/app_permission_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/ui/app_ui.dart';
import '../../shared/presentation/app_controller.dart';
import 'auth_visuals.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth >= 840) {
            return Row(
              children: [
                const Expanded(flex: 6, child: _WelcomeHeroImage()),
                Expanded(
                  flex: 4,
                  child: SafeArea(
                    child: SingleChildScrollView(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          minHeight:
                              constraints.maxHeight -
                              MediaQuery.paddingOf(context).vertical,
                        ),
                        child: const _WelcomeContent(),
                      ),
                    ),
                  ),
                ),
              ],
            );
          }

          final shortViewport = constraints.maxHeight < 650;
          return Stack(
            children: [
              Positioned.fill(child: _WelcomeHeroImage()),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: SafeArea(
                  top: false,
                  child: _WelcomeContent(compact: shortViewport),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _WelcomeHeroImage extends StatelessWidget {
  const _WelcomeHeroImage();

  @override
  Widget build(BuildContext context) => Stack(
    key: const ValueKey('welcome-hero-image'),
    fit: StackFit.expand,
    children: [
      Image.asset(
        'assets/images/welcome_field.webp',
        fit: BoxFit.cover,
        alignment: Alignment.bottomCenter,
        semanticLabel: 'Farmer holding a young plant in a field',
        errorBuilder: (_, _, _) => Image.asset(
          'assets/images/hero_farm_bg.jpg',
          fit: BoxFit.cover,
          alignment: Alignment.center,
        ),
      ),
      const DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            stops: [0.0, 0.35, 0.75, 1.0],
            colors: [
              Color(0x00000000),
              Color(0x14000000),
              Color(0xB0173B2C),
              Color(0xF5173B2C),
            ],
          ),
        ),
      ),
    ],
  );
}

class _WelcomeContent extends StatelessWidget {
  const _WelcomeContent({this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(24, compact ? 12 : 18, 24, 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          BrandMark(size: compact ? 34 : 40, dark: true),
          SizedBox(height: compact ? 14 : 22),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Text(
              context.tr('welcomeTitle'),
              style: Theme.of(context).textTheme.displaySmall?.copyWith(
                color: Colors.white,
                shadows: [
                  Shadow(
                    color: Colors.black.withValues(alpha: 0.3),
                    blurRadius: 12,
                  ),
                ],
              ),
            ),
          ),
          if (!compact) ...[
            const SizedBox(height: 10),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 500),
              child: Text(
                context.tr('welcomeBody'),
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: Colors.white.withValues(alpha: 0.78),
                  height: 1.5,
                ),
              ),
            ),
          ],
          SizedBox(height: compact ? 20 : 30),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () => context.push('/auth'),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: AppColors.forest,
                minimumSize: const Size(double.infinity, 54),
              ),
              child: Text(
                context.tr('getStarted'),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _createAccount = false;
  bool _obscure = true;

  Future<bool> _showEmailConfirmation() async {
    final cachedEmail = _emailController.text.trim();
    final cachedPassword = _passwordController.text;
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => _SignUpConfirmationSheet(email: cachedEmail),
    );
    if (!(confirmed ?? false) || !mounted) return confirmed ?? false;
    // Auto sign-in after OTP confirmation so the user doesn't have to
    // manually switch tabs and tap Sign In again.
    final controller = context.read<AppController>();
    try {
      await controller.signIn(cachedEmail, cachedPassword);
      if (!mounted) return true;
      if (controller.onboardingComplete) {
        context.go('/home');
      } else if (controller.hasFarmerName) {
        context.go('/onboarding/language');
      } else {
        context.go('/onboarding/profile');
      }
    } on ApiException {
      // Auto sign-in failed silently — fallback to the old manual flow.
      if (mounted) {
        setState(() => _createAccount = false);
        showAppSnackBar(
          context,
          'Email confirmed. Sign in to continue.',
          success: true,
        );
      }
    }
    return true;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final controller = context.read<AppController>();
    try {
      if (_createAccount) {
        final alreadyConfirmed = await controller.signUp(
          _nameController.text,
          _emailController.text,
          _passwordController.text,
        );
        if (!mounted) return;
        if (alreadyConfirmed) {
          setState(() => _createAccount = false);
          showAppSnackBar(
            context,
            'Account created. Sign in to continue.',
            success: true,
          );
        } else {
          await _showEmailConfirmation();
        }
      } else {
        await controller.signIn(
          _emailController.text,
          _passwordController.text,
        );
        if (!mounted) return;
        if (controller.onboardingComplete) {
          context.go('/home');
        } else if (controller.hasFarmerName) {
          context.go('/onboarding/language');
        } else {
          context.go('/onboarding/profile');
        }
      }
    } on ApiException catch (error) {
      if (!mounted) return;
      if (error.code == 'AUTH_EMAIL_UNCONFIRMED') {
        await _showEmailConfirmation();
        return;
      }
      if (error.code == 'AUTH_INCORRECT_CREDENTIALS') {
        _passwordController.clear();
      }
      showAppSnackBar(context, context.localizedError(error));
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AppController>();
    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          final expanded = constraints.maxWidth >= 840;
          final horizontalPadding = expanded ? 40.0 : 16.0;
          final verticalPadding = expanded ? 32.0 : 16.0;
          final form = AuthSurface(child: _buildForm(context, controller));
          return Stack(
            fit: StackFit.expand,
            children: [
              const AuthHero(),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    stops: [0, 0.38, 1],
                    colors: [
                      Color(0x4D071B10),
                      Color(0x7307140C),
                      Color(0xE608120B),
                    ],
                  ),
                ),
              ),
              SafeArea(
                child: SingleChildScrollView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: EdgeInsets.symmetric(
                    horizontal: horizontalPadding,
                    vertical: verticalPadding,
                  ),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight:
                          constraints.maxHeight -
                          MediaQuery.paddingOf(context).vertical -
                          (verticalPadding * 2),
                    ),
                    child: expanded
                        ? Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              const Expanded(child: AuthStory()),
                              const SizedBox(width: 48),
                              ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxWidth: 500,
                                ),
                                child: form,
                              ),
                            ],
                          )
                        : Column(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              const SizedBox(height: 82),
                              ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxWidth: 520,
                                ),
                                child: form,
                              ),
                            ],
                          ),
                  ),
                ),
              ),
              SafeArea(
                child: Align(
                  alignment: AlignmentDirectional.topStart,
                  child: Padding(
                    padding: const EdgeInsetsDirectional.only(
                      start: 12,
                      top: 6,
                    ),
                    child: IconButton.filled(
                      tooltip: MaterialLocalizations.of(context)
                          .backButtonTooltip,
                      onPressed: () => context.pop(),
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.black.withValues(alpha: 0.38),
                        foregroundColor: Colors.white,
                      ),
                      icon: const Icon(LucideIcons.arrowLeft),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildForm(BuildContext context, AppController controller) {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const BrandMark(size: 38, showName: false),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'KrishiSathi',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final vertical =
                    constraints.maxWidth < 340 ||
                    MediaQuery.textScalerOf(context).scale(1) > 1.35;
                return SegmentedButton<bool>(
                  direction: vertical ? Axis.vertical : Axis.horizontal,
                  showSelectedIcon: false,
                  segments: [
                    ButtonSegment<bool>(
                      value: false,
                      icon: const Icon(LucideIcons.logIn, size: 18),
                      label: Text(context.tr('signIn')),
                    ),
                    ButtonSegment<bool>(
                      value: true,
                      icon: const Icon(LucideIcons.userPlus, size: 18),
                      label: Text(context.tr('createAccount')),
                    ),
                  ],
                  selected: {_createAccount},
                  onSelectionChanged: (selection) {
                    setState(() => _createAccount = selection.single);
                  },
                );
              },
            ),
          ),
          const SizedBox(height: 26),
          Text(
            _createAccount ? context.tr('createAccount') : context.tr('signIn'),
            style: Theme.of(context).textTheme.headlineLarge,
          ),
          const SizedBox(height: 8),
          Text(
            context.tr(
              _createAccount
                  ? 'createPrivateAccountBody'
                  : 'welcomeBackPrivateBody',
            ),
            style: Theme.of(context).textTheme.bodyLarge
                ?.copyWith(color: Colors.white.withValues(alpha: 0.76)),
          ),
          const SizedBox(height: 24),
          if (_createAccount) ...[
            TextFormField(
              controller: _nameController,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.name],
              decoration: InputDecoration(
                labelText: context.tr('nameHint'),
                prefixIcon: const Icon(LucideIcons.userRound, size: 20),
              ),
              validator: (value) {
                final normalized = value?.trim() ?? '';
                if (normalized.isEmpty) return 'Enter your name.';
                if (normalized.length > 100) {
                  return 'Keep the name under 100 characters.';
                }
                return null;
              },
            ),
            const SizedBox(height: 14),
          ],
          TextFormField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.email],
            decoration: InputDecoration(
              labelText: context.tr('email'),
              prefixIcon: const Icon(LucideIcons.mail, size: 20),
            ),
            validator: (value) {
              final normalized = value?.trim() ?? '';
              if (!normalized.contains('@') || !normalized.contains('.')) {
                return 'Enter a valid email address.';
              }
              return null;
            },
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: _passwordController,
            obscureText: _obscure,
            autofillHints: _createAccount
                ? const [AutofillHints.newPassword]
                : const [AutofillHints.password],
            decoration: InputDecoration(
              labelText: context.tr('password'),
              prefixIcon: const Icon(LucideIcons.lockKeyhole, size: 20),
              suffixIcon: IconButton(
                tooltip: context.tr(_obscure ? 'showPassword' : 'hidePassword'),
                onPressed: () => setState(() => _obscure = !_obscure),
                icon: Icon(
                  _obscure ? LucideIcons.eye : LucideIcons.eyeOff,
                  size: 20,
                ),
              ),
            ),
            validator: (value) =>
                (value?.length ?? 0) < 8 ? 'Use at least 8 characters.' : null,
          ),
          if (!_createAccount)
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: TextButton(
                onPressed: () => showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  showDragHandle: true,
                  builder: (context) => _PasswordRecoverySheet(
                    initialEmail: _emailController.text.trim(),
                  ),
                ),
                child: Text(context.tr('forgotPassword')),
              ),
            )
          else
            const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: controller.busy ? null : _submit,
              child: controller.busy
                  ? const SizedBox.square(
                      dimension: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(
                      _createAccount
                          ? context.tr('createAccount')
                          : context.tr('signIn'),
                    ),
            ),
          ),
          const SizedBox(height: 8),
          const SizedBox(height: 20),
          Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 10,
            runSpacing: 8,
            children: [
              Icon(
                LucideIcons.lock,
                size: 12,
                color: Colors.white.withValues(alpha: 0.68),
              ),
              const SizedBox(width: 2),
              Text(
                'Secure',
                style: Theme.of(context).textTheme.labelSmall
                    ?.copyWith(color: Colors.white.withValues(alpha: 0.68)),
              ),
              Container(
                width: 3,
                height: 3,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.5),
                  shape: BoxShape.circle,
                ),
              ),
              Icon(
                LucideIcons.wheat,
                size: 12,
                color: Colors.white.withValues(alpha: 0.68),
              ),
              const SizedBox(width: 2),
              Text(
                'Made for India',
                style: Theme.of(context).textTheme.labelSmall
                    ?.copyWith(color: Colors.white.withValues(alpha: 0.68)),
              ),
              Container(
                width: 3,
                height: 3,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.5),
                  shape: BoxShape.circle,
                ),
              ),
              Icon(
                LucideIcons.languages,
                size: 12,
                color: Colors.white.withValues(alpha: 0.68),
              ),
              const SizedBox(width: 2),
              Text(
                '22 Indian languages',
                style: Theme.of(context).textTheme.labelSmall
                    ?.copyWith(color: Colors.white.withValues(alpha: 0.68)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SignUpConfirmationSheet extends StatefulWidget {
  const _SignUpConfirmationSheet({required this.email});

  final String email;

  @override
  State<_SignUpConfirmationSheet> createState() =>
      _SignUpConfirmationSheetState();
}

class _SignUpConfirmationSheetState extends State<_SignUpConfirmationSheet> {
  final _key = GlobalKey<FormState>();
  final _code = TextEditingController();
  bool _resending = false;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    if (!_key.currentState!.validate()) return;
    try {
      await context.read<AppController>().confirmSignUp(
        widget.email,
        _code.text,
      );
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (error) {
      if (mounted) showAppSnackBar(context, context.localizedError(error));
    }
  }

  Future<void> _resend() async {
    if (_resending) return;
    setState(() => _resending = true);
    try {
      await context.read<AppController>().resendSignUpCode(widget.email);
      if (mounted) {
        showAppSnackBar(
          context,
          'A new confirmation code was sent.',
          success: true,
        );
      }
    } on ApiException catch (error) {
      if (mounted) showAppSnackBar(context, context.localizedError(error));
    } finally {
      if (mounted) setState(() => _resending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final busy = context.watch<AppController>().busy;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          24,
          4,
          24,
          24 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Form(
          key: _key,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Confirm your email',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 8),
              Text(
                'Enter the code sent to ${widget.email}.',
                style: Theme.of(context).textTheme.bodyLarge
                    ?.copyWith(color: AppColors.mutedInk),
              ),
              const SizedBox(height: 20),
              TextFormField(
                controller: _code,
                autofocus: true,
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.done,
                autofillHints: const [AutofillHints.oneTimeCode],
                decoration: InputDecoration(
                  labelText: context.tr('confirmationCode'),
                  prefixIcon: const Icon(LucideIcons.badgeCheck),
                ),
                validator: (value) => (value?.trim().length ?? 0) < 4
                    ? 'Enter the code from your email.'
                    : null,
                onFieldSubmitted: (_) => busy ? null : _confirm(),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: busy ? null : _confirm,
                  child: busy
                      ? const SizedBox.square(
                          dimension: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(context.tr('confirmEmail')),
                ),
              ),
              Align(
                alignment: AlignmentDirectional.center,
                child: TextButton.icon(
                  onPressed: busy || _resending ? null : _resend,
                  icon: _resending
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(LucideIcons.refreshCw, size: 17),
                  label: Text(context.tr('resendConfirmationCode')),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PasswordRecoverySheet extends StatefulWidget {
  const _PasswordRecoverySheet({required this.initialEmail});

  final String initialEmail;

  @override
  State<_PasswordRecoverySheet> createState() => _PasswordRecoverySheetState();
}

class _PasswordRecoverySheetState extends State<_PasswordRecoverySheet> {
  final _key = GlobalKey<FormState>();
  late final TextEditingController _email;
  final _code = TextEditingController();
  final _newPassword = TextEditingController();
  bool _codeSent = false;
  bool _obscure = true;

  @override
  void initState() {
    super.initState();
    _email = TextEditingController(text: widget.initialEmail);
  }

  @override
  void dispose() {
    _email.dispose();
    _code.dispose();
    _newPassword.dispose();
    super.dispose();
  }

  Future<void> _continue() async {
    if (!_key.currentState!.validate()) return;
    try {
      if (!_codeSent) {
        await context.read<AppController>().requestPasswordReset(_email.text);
        if (mounted) {
          setState(() => _codeSent = true);
          showAppSnackBar(
            context,
            'Recovery code sent to your email.',
            success: true,
          );
        }
        return;
      }
      await context.read<AppController>().confirmPasswordReset(
        email: _email.text,
        code: _code.text,
        newPassword: _newPassword.text,
      );
      if (!mounted) return;
      showAppSnackBar(
        context,
        'Password updated. You can sign in now.',
        success: true,
      );
      Navigator.of(context).pop();
    } on ApiException catch (error) {
      if (mounted) showAppSnackBar(context, context.localizedError(error));
    }
  }

  @override
  Widget build(BuildContext context) {
    final busy = context.watch<AppController>().busy;
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          24,
          4,
          24,
          24 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Form(
          key: _key,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.tr(_codeSent ? 'setNewPassword' : 'resetYourPassword'),
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 8),
              Text(
                _codeSent
                    ? 'Enter the email code and choose a new password.'
                    : 'We will send a recovery code to your account email.',
                style: Theme.of(context).textTheme.bodyLarge
                    ?.copyWith(color: AppColors.mutedInk),
              ),
              const SizedBox(height: 20),
              TextFormField(
                controller: _email,
                enabled: !_codeSent && !busy,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email],
                decoration: InputDecoration(
                  labelText: context.tr('email'),
                  prefixIcon: const Icon(LucideIcons.mail),
                ),
                validator: (value) {
                  final normalized = value?.trim() ?? '';
                  return !normalized.contains('@') || !normalized.contains('.')
                      ? 'Enter a valid email address.'
                      : null;
                },
              ),
              if (_codeSent) ...[
                const SizedBox(height: 14),
                TextFormField(
                  controller: _code,
                  keyboardType: TextInputType.number,
                  autofillHints: const [AutofillHints.oneTimeCode],
                  decoration: InputDecoration(
                    labelText: context.tr('recoveryCode'),
                    prefixIcon: const Icon(LucideIcons.badgeCheck),
                  ),
                  validator: (value) => (value?.trim().length ?? 0) < 4
                      ? 'Enter the code from your email.'
                      : null,
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _newPassword,
                  obscureText: _obscure,
                  autofillHints: const [AutofillHints.newPassword],
                  decoration: InputDecoration(
                    labelText: context.tr('newPassword'),
                    prefixIcon: const Icon(LucideIcons.lockKeyhole),
                    suffixIcon: IconButton(
                      tooltip: context.tr(
                        _obscure ? 'showPassword' : 'hidePassword',
                      ),
                      onPressed: () => setState(() => _obscure = !_obscure),
                      icon: Icon(
                        _obscure ? LucideIcons.eye : LucideIcons.eyeOff,
                      ),
                    ),
                  ),
                  validator: (value) => (value?.length ?? 0) < 8
                      ? 'Use at least 8 characters.'
                      : null,
                ),
              ],
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: busy ? null : _continue,
                  child: busy
                      ? const SizedBox.square(
                          dimension: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(
                          context.tr(_codeSent ? 'updatePassword' : 'sendCode'),
                        ),
                ),
              ),
              if (_codeSent)
                Center(
                  child: TextButton(
                    onPressed: busy
                        ? null
                        : () => setState(() => _codeSent = false),
                    child: Text(context.tr('useDifferentEmail')),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class ProfileSetupScreen extends StatefulWidget {
  const ProfileSetupScreen({super.key, required this.preview});

  final bool preview;

  @override
  State<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends State<ProfileSetupScreen> {
  late final TextEditingController _nameController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(
      text: context.read<AppController>().farmerName,
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        top: false,
        child: AppContent(
          maxWidth: 600,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _StepIndicator(current: 1),
              const SizedBox(height: 32),
              Text(
                context.tr('yourName'),
                style: Theme.of(context).textTheme.headlineLarge,
              ),
              const SizedBox(height: 10),
              Text(
                'We use this only to make the app feel personal.',
                style: Theme.of(context).textTheme.bodyLarge
                    ?.copyWith(color: AppColors.mutedInk),
              ),
              const SizedBox(height: 28),
              TextField(
                controller: _nameController,
                autofocus: true,
                textInputAction: TextInputAction.done,
                decoration: InputDecoration(
                  labelText: context.tr('nameHint'),
                  prefixIcon: const Icon(LucideIcons.userRound, size: 20),
                ),
              ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () async {
                    try {
                      await context.read<AppController>().setFarmerName(
                        _nameController.text,
                      );
                      if (context.mounted) {
                        context.push(
                          '/onboarding/language?preview=${widget.preview}',
                        );
                      }
                    } on ApiException catch (error) {
                      if (context.mounted) {
                        showAppSnackBar(context, context.localizedError(error));
                      }
                    }
                  },
                  child: Text(context.tr('continue')),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}

class LanguageSetupScreen extends StatelessWidget {
  const LanguageSetupScreen({super.key, required this.preview});

  final bool preview;

  @override
  Widget build(BuildContext context) {
    final selected = context.watch<AppController>().locale.languageCode;
    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        top: false,
        child: AppContent(
          maxWidth: 720,
          padding: EdgeInsets.zero,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 20),
                child: _StepIndicator(current: 2),
              ),
              const SizedBox(height: 24),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Text(
                  context.tr('chooseLanguage'),
                  style: Theme.of(context).textTheme.headlineLarge,
                ),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Text(
                  context.tr('languageHelp'),
                  style: Theme.of(context).textTheme.bodyLarge
                      ?.copyWith(color: AppColors.mutedInk),
                ),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  itemCount: AppLanguage.supported.length,
                  separatorBuilder: (_, _) => const Divider(indent: 68),
                  itemBuilder: (context, index) {
                    final language = AppLanguage.supported[index];
                    final isSelected = language.code == selected;
                    return Semantics(
                      selected: isSelected,
                      button: true,
                      child: ListTile(
                        minTileHeight: 62,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppRadius.medium),
                        ),
                        selected: isSelected,
                        selectedTileColor: AppColors.leaf.withValues(
                          alpha: 0.08,
                        ),
                        leading: Container(
                          width: 40,
                          height: 40,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: isSelected
                                ? AppColors.forest
                                : AppColors.divider.withValues(alpha: 0.65),
                            borderRadius: BorderRadius.circular(
                              AppRadius.medium,
                            ),
                          ),
                          child: Text(
                            language.nativeName.characters.first,
                            style: TextStyle(
                              color: isSelected ? Colors.white : AppColors.ink,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        title: Text(language.nativeName),
                        subtitle: language.nativeName == language.englishName
                            ? null
                            : Text(language.englishName),
                        trailing: isSelected
                            ? const Icon(
                                LucideIcons.circleCheck,
                                color: AppColors.leaf,
                              )
                            : null,
                        onTap: () async {
                          try {
                            await context.read<AppController>().setLocale(
                              language.code,
                            );
                          } on ApiException catch (error) {
                            if (context.mounted) {
                              showAppSnackBar(
                                context,
                                context.localizedError(error),
                              );
                            }
                          }
                        },
                      ),
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () {
                      final controller = context.read<AppController>();
                      if (!controller.isAuthenticated) {
                        context.go('/auth');
                        return;
                      }
                      context.push('/onboarding/permissions?preview=$preview');
                    },
                    child: Text(context.tr('continue')),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class PermissionsSetupScreen extends StatelessWidget {
  const PermissionsSetupScreen({super.key, required this.preview});

  final bool preview;

  Future<void> _setPermission(
    BuildContext context,
    AppPermissionKind kind,
    bool enabled,
  ) async {
    final controller = context.read<AppController>();
    final state = switch (kind) {
      AppPermissionKind.location => await controller.setLocationEnabled(
        enabled,
      ),
      AppPermissionKind.camera => await controller.setCameraEnabled(enabled),
      AppPermissionKind.microphone =>
        enabled
            ? await controller.requestMicrophonePermission()
            : controller.microphonePermission,
      AppPermissionKind.notifications => await controller.setNotifications(
        enabled,
      ),
    };
    if (!context.mounted || !enabled || state.isAllowed) return;
    if (!state.requiresSettings) {
      showAppSnackBar(
        context,
        'Permission was not granted. You can enable it later in Settings.',
      );
      return;
    }
    final openSettings = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.tr('permissionBlocked')),
        content: Text(context.tr('permissionBlockedBody')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(context.tr('notNow')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(context.tr('openSettings')),
          ),
        ],
      ),
    );
    if (openSettings ?? false) {
      await controller.openAppPermissionSettings();
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AppController>();
    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        top: false,
        child: AppContent(
          maxWidth: 640,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _StepIndicator(current: 3),
              const SizedBox(height: 30),
              Text(
                context.tr('permissionsTitle'),
                style: Theme.of(context).textTheme.headlineLarge,
              ),
              const SizedBox(height: 10),
              Text(
                'You can use KrishiSathi without these. Enable each only when it is useful to you.',
                style: Theme.of(context).textTheme.bodyLarge
                    ?.copyWith(color: AppColors.mutedInk),
              ),
              const SizedBox(height: 26),
              _PermissionRow(
                icon: LucideIcons.mapPin,
                title: context.tr('locationPermission'),
                value: controller.locationEnabled,
                onChanged: (value) =>
                    _setPermission(context, AppPermissionKind.location, value),
              ),
              const Divider(),
              _PermissionRow(
                icon: LucideIcons.bell,
                title: context.tr('notificationPermission'),
                value: controller.notificationsEnabled,
                onChanged: (value) => _setPermission(
                  context,
                  AppPermissionKind.notifications,
                  value,
                ),
              ),
              const Divider(),
              _PermissionRow(
                icon: LucideIcons.camera,
                title: context.tr('cameraPermission'),
                value: controller.cameraEnabled,
                onChanged: (value) =>
                    _setPermission(context, AppPermissionKind.camera, value),
              ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () async {
                    await context.read<AppController>().completeOnboarding(
                      preview: false,
                    );
                    if (context.mounted) context.go('/home');
                  },
                  child: Text(context.tr('finishSetup')),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}

class _StepIndicator extends StatelessWidget {
  const _StepIndicator({required this.current});

  final int current;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(3, (index) {
        final active = index + 1 <= current;
        return Expanded(
          child: AnimatedContainer(
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : const Duration(milliseconds: 240),
            curve: Curves.easeOutCubic,
            height: 4,
            margin: EdgeInsetsDirectional.only(end: index == 2 ? 0 : 6),
            decoration: BoxDecoration(
              color: active ? AppColors.leaf : AppColors.divider,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        );
      }),
    );
  }
}

class _PermissionRow extends StatelessWidget {
  const _PermissionRow({
    required this.icon,
    required this.title,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.leaf.withValues(alpha: 0.09),
              borderRadius: BorderRadius.circular(AppRadius.medium),
            ),
            child: Icon(icon, color: AppColors.forest, size: 21),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(title, style: Theme.of(context).textTheme.titleMedium),
          ),
          Switch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}
