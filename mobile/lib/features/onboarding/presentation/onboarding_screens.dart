import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../../core/localization/app_language.dart';
import '../../../core/localization/app_strings.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/ui/app_ui.dart';
import '../../shared/presentation/app_controller.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            'assets/images/hero_farm_bg.jpg',
            fit: BoxFit.cover,
            alignment: const Alignment(0.2, 0),
          ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0x33000000),
                  Color(0x52000000),
                  Color(0xE8112018),
                ],
                stops: [0, 0.45, 1],
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 18, 24, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const BrandMark(dark: true),
                  const Spacer(),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 520),
                    child: Text(
                      context.tr('welcomeTitle'),
                      style: Theme.of(context).textTheme.displaySmall
                          ?.copyWith(color: Colors.white),
                    ),
                  ),
                  const SizedBox(height: 14),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 500),
                    child: Text(
                      context.tr('welcomeBody'),
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: Colors.white.withValues(alpha: 0.88),
                      ),
                    ),
                  ),
                  const SizedBox(height: 26),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: AppColors.forest,
                      ),
                      onPressed: () => context.push('/auth'),
                      child: Text(context.tr('getStarted')),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: TextButton(
                      onPressed: () => context.push('/onboarding/language'),
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.white,
                        minimumSize: const Size.fromHeight(48),
                      ),
                      child: Text(context.tr('chooseLanguage')),
                    ),
                  ),
                ],
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
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _createAccount = false;
  bool _obscure = true;

  @override
  void dispose() {
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
          final confirmed = await showModalBottomSheet<bool>(
            context: context,
            isScrollControlled: true,
            showDragHandle: true,
            builder: (context) =>
                _SignUpConfirmationSheet(email: _emailController.text.trim()),
          );
          if (confirmed ?? false) {
            if (!mounted) return;
            setState(() => _createAccount = false);
            showAppSnackBar(
              context,
              'Email confirmed. Sign in to continue.',
              success: true,
            );
          }
        }
      } else {
        await controller.signIn(
          _emailController.text,
          _passwordController.text,
        );
        if (!mounted) return;
        context.go('/onboarding/profile');
      }
    } on ApiException catch (error) {
      if (!mounted) return;
      showAppSnackBar(context, context.localizedError(error));
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AppController>();
    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        top: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final expanded = constraints.maxWidth >= 840;
            final form = _buildForm(context, controller);
            if (expanded) {
              return Row(
                children: [
                  const Expanded(
                    flex: 11,
                    child: Padding(
                      padding: EdgeInsetsDirectional.fromSTEB(24, 8, 12, 24),
                      child: _AuthHero(expanded: true),
                    ),
                  ),
                  Expanded(
                    flex: 9,
                    child: SingleChildScrollView(
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      child: AppContent(
                        maxWidth: 560,
                        child: Padding(
                          padding: const EdgeInsetsDirectional.fromSTEB(
                            28,
                            24,
                            28,
                            40,
                          ),
                          child: form,
                        ),
                      ),
                    ),
                  ),
                ],
              );
            }
            return SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              child: AppContent(
                maxWidth: 560,
                child: Padding(
                  padding: const EdgeInsets.only(top: 4, bottom: 32),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const _AuthHero(expanded: false),
                      const SizedBox(height: 24),
                      form,
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildForm(BuildContext context, AppController controller) {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const BrandMark(size: 46),
          const SizedBox(height: 28),
          Text(
            _createAccount ? context.tr('createAccount') : context.tr('signIn'),
            style: Theme.of(context).textTheme.headlineLarge,
          ),
          const SizedBox(height: 8),
          Text(
            _createAccount ? 'Create your private farmer account.' : 'Welcome back. Your farm records stay private to your account.',
            style: Theme.of(context).textTheme.bodyLarge
                ?.copyWith(color: AppColors.mutedInk),
          ),
          const SizedBox(height: 24),
          if (!controller.config.isCognitoConfigured) ...[
            InlineNotice(
              title: context.tr('demoMode'),
              message: context.tr('authNotConfigured'),
              icon: LucideIcons.cloudOff,
              color: AppColors.amber,
            ),
            const SizedBox(height: 20),
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
                tooltip: _obscure ? 'Show password' : 'Hide password',
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
                onPressed: controller.config.isCognitoConfigured
                    ? () => showModalBottomSheet<void>(
                        context: context,
                        isScrollControlled: true,
                        showDragHandle: true,
                        builder: (context) => _PasswordRecoverySheet(
                          initialEmail: _emailController.text.trim(),
                        ),
                      )
                    : null,
                child: Text(context.tr('forgotPassword')),
              ),
            )
          else
            const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed:
                  controller.busy || !controller.config.isCognitoConfigured
                  ? null
                  : _submit,
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
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: () => context.go('/onboarding/profile?preview=true'),
              child: Text(context.tr('usePreview')),
            ),
          ),
          const SizedBox(height: 12),
          Center(
            child: TextButton(
              onPressed: () => setState(() => _createAccount = !_createAccount),
              child: Text(
                _createAccount
                    ? 'Already have an account? Sign in'
                    : 'New to KrishiSathi? Create account',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AuthHero extends StatelessWidget {
  const _AuthHero({required this.expanded});

  final bool expanded;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      image: true,
      label: 'Healthy Indian crops growing in a sunlit field',
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.medium),
        child: SizedBox(
          height: expanded ? double.infinity : 156,
          width: double.infinity,
          child: Image.asset(
            'assets/images/auth_field_hero.webp',
            alignment: expanded
                ? const Alignment(0.05, 0)
                : const Alignment(0, 0.12),
            fit: BoxFit.cover,
            filterQuality: FilterQuality.medium,
            excludeFromSemantics: true,
          ),
        ),
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
                decoration: const InputDecoration(
                  labelText: 'Confirmation code',
                  prefixIcon: Icon(LucideIcons.badgeCheck),
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
                      : const Text('Confirm email'),
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
        if (mounted) setState(() => _codeSent = true);
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
                _codeSent ? 'Set a new password' : 'Reset your password',
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
                decoration: const InputDecoration(
                  labelText: 'Email address',
                  prefixIcon: Icon(LucideIcons.mail),
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
                  decoration: const InputDecoration(
                    labelText: 'Recovery code',
                    prefixIcon: Icon(LucideIcons.badgeCheck),
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
                    labelText: 'New password',
                    prefixIcon: const Icon(LucideIcons.lockKeyhole),
                    suffixIcon: IconButton(
                      tooltip: _obscure ? 'Show password' : 'Hide password',
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
                      : Text(_codeSent ? 'Update password' : 'Send code'),
                ),
              ),
              if (_codeSent)
                Center(
                  child: TextButton(
                    onPressed: busy
                        ? null
                        : () => setState(() => _codeSent = false),
                    child: const Text('Use a different email'),
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
                    await context.read<AppController>().setFarmerName(
                      _nameController.text,
                    );
                    if (context.mounted) {
                      context.push(
                        '/onboarding/language?preview=${widget.preview}',
                      );
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
                        onTap: () => context.read<AppController>().setLocale(
                          language.code,
                        ),
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
                    onPressed: () => context.push(
                      '/onboarding/permissions?preview=$preview',
                    ),
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
                onChanged: controller.setLocationEnabled,
              ),
              const Divider(),
              _PermissionRow(
                icon: LucideIcons.bell,
                title: context.tr('notificationPermission'),
                value: controller.notificationsEnabled,
                onChanged: controller.setNotifications,
              ),
              const Divider(),
              _PermissionRow(
                icon: LucideIcons.camera,
                title: context.tr('cameraPermission'),
                value: controller.cameraEnabled,
                onChanged: controller.setCameraEnabled,
              ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () async {
                    await context.read<AppController>().completeOnboarding(
                      preview: preview,
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
