import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/role_catalog.dart';
import '../../../core/storage/ui_prefs.dart';
import '../../../core/utils/error_messages.dart';
import '../../../core/widgets/cadmir_logo.dart';
import '../application/auth_controller.dart';

/// Экран входа «Цадмир». Два режима одной формы:
///  • Вход — email + пароль.
///  • Создать аккаунт — email + пароль + ФИО (без выбора роли).
/// Новый аккаунт создаётся БЕЗ прав — роль назначает супер-админ через консоль.
/// Кнопки быстрого входа по роли доступны только в debug-сборке (kDebugMode).
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _fullName = TextEditingController();
  final _emailFocus = FocusNode();
  final _passwordFocus = FocusNode();
  final _formKey = GlobalKey<FormState>();
  bool _loading = false;
  bool _obscurePassword = true;
  bool _remember = true;
  bool _signUpMode = false;
  // ⚠️ ВРЕМЕННО: режим саморегистрации супер-админа (кнопка ниже; убрать потом).
  bool _superRegMode = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _prefillRememberedEmail();
  }

  /// Restores the last remembered email (if «Запомнить логин» was on) and
  /// jumps the cursor straight to the password — one field away from working.
  Future<void> _prefillRememberedEmail() async {
    final saved = await ref.read(uiPrefsProvider).readRememberedEmail();
    if (!mounted || saved == null || saved.isEmpty) return;
    if (_email.text.isNotEmpty) return; // user already started typing
    setState(() => _email.text = saved);
    _passwordFocus.requestFocus();
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _fullName.dispose();
    _emailFocus.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  void _toggleMode() {
    setState(() {
      _signUpMode = !_signUpMode;
      _error = null;
    });
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    // Captured before any await: on success the router disposes this screen.
    final prefs = ref.read(uiPrefsProvider);
    final auth = ref.read(authControllerProvider.notifier);
    final messenger = ScaffoldMessenger.of(context);
    final email = _email.text.trim();
    try {
      if (_superRegMode) {
        // ⚠️ ВРЕМЕННО: регистрируемся супер-админом и остаёмся в системе —
        // роутер уводит на домашний экран.
        await auth.registerSuperadminTemp(
          email,
          _password.text,
          _fullName.text.trim(),
        );
      } else if (_signUpMode) {
        await auth.signUp(email, _password.text, _fullName.text.trim());
        // Аккаунт создаётся обезоруженным (без прав) и сразу выходит из системы:
        // возвращаем форму в режим входа и показываем пояснение.
        if (mounted) {
          setState(() {
            _signUpMode = false;
            _password.clear();
          });
          messenger.showSnackBar(
            const SnackBar(
              content: Text(
                'Аккаунт создан. Доступ выдаёт администратор — '
                'обратитесь к нему для назначения роли.',
              ),
            ),
          );
        }
      } else {
        await auth.login(email, _password.text);
        // Persist (or clear) the remembered email only after a successful login.
        await prefs.writeRememberedEmail(_remember ? email : null);
      }
      // Router redirect handles navigation on success.
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Быстрый вход по роли — ТОЛЬКО для отладки (вызывается из-под kDebugMode).
  /// В release-сборке ветка вызова отсутствует, метод отшейкивается вместе с
  /// [AuthController.loginAsRole].
  Future<void> _quickLogin(String role) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final auth = ref.read(authControllerProvider.notifier);
    try {
      await auth.loginAsRole(role);
      // Router redirect handles navigation on success.
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const CadmirLogo(size: 56),
                      const SizedBox(height: 12),
                      Text(
                        'Цадмир',
                        textAlign: TextAlign.center,
                        style: textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: scheme.primary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Гематологический центр',
                        textAlign: TextAlign.center,
                        style: textTheme.bodySmall,
                      ),
                      // Быстрый вход по роли — только в debug-сборке; в release
                      // ветка (kDebugMode == false) вырезается компилятором.
                      if (!_signUpMode && kDebugMode) ...[
                        const SizedBox(height: 24),
                        Text(
                          'Быстрый вход (для теста)',
                          textAlign: TextAlign.center,
                          style: textTheme.labelMedium?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: FilledButton.tonalIcon(
                                onPressed: _loading
                                    ? null
                                    : () => _quickLogin(roleReception),
                                icon: const Icon(
                                  Icons.badge_outlined,
                                  size: 18,
                                ),
                                label: const Text('Ресепшен'),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: FilledButton.tonalIcon(
                                onPressed: _loading
                                    ? null
                                    : () => _quickLogin(roleSuperadmin),
                                icon: const Icon(
                                  Icons.shield_outlined,
                                  size: 18,
                                ),
                                label: const Text('Супер-админ'),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        Row(
                          children: [
                            const Expanded(child: Divider()),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                              ),
                              child: Text(
                                'или вручную',
                                style: textTheme.bodySmall,
                              ),
                            ),
                            const Expanded(child: Divider()),
                          ],
                        ),
                        const SizedBox(height: 8),
                      ] else
                        const SizedBox(height: 28),
                      TextFormField(
                        controller: _email,
                        focusNode: _emailFocus,
                        autofocus: true,
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.next,
                        onFieldSubmitted: (_) => _passwordFocus.requestFocus(),
                        decoration: const InputDecoration(
                          labelText: 'Email',
                          prefixIcon: Icon(Icons.person_outline),
                        ),
                        validator: (v) => (v == null || !v.contains('@'))
                            ? 'Введите email'
                            : null,
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _password,
                        focusNode: _passwordFocus,
                        obscureText: _obscurePassword,
                        textInputAction: _signUpMode
                            ? TextInputAction.next
                            : TextInputAction.done,
                        onFieldSubmitted: (_) {
                          if (!_signUpMode) _submit();
                        },
                        decoration: InputDecoration(
                          labelText: 'Пароль',
                          prefixIcon: const Icon(Icons.lock_outline),
                          suffixIcon: IconButton(
                            tooltip: _obscurePassword
                                ? 'Показать пароль'
                                : 'Скрыть пароль',
                            icon: Icon(
                              _obscurePassword
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                            ),
                            onPressed: () => setState(
                              () => _obscurePassword = !_obscurePassword,
                            ),
                          ),
                        ),
                        validator: (v) {
                          if (v == null || v.isEmpty) return 'Введите пароль';
                          if ((_signUpMode || _superRegMode) && v.length < 6) {
                            return 'Минимум 6 символов';
                          }
                          return null;
                        },
                      ),
                      if (_signUpMode || _superRegMode) ...[
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _fullName,
                          textInputAction: TextInputAction.next,
                          textCapitalization: TextCapitalization.words,
                          decoration: const InputDecoration(
                            labelText: 'ФИО',
                            prefixIcon: Icon(Icons.badge_outlined),
                          ),
                          validator: (v) => (v == null || v.trim().isEmpty)
                              ? 'Введите ФИО'
                              : null,
                        ),
                      ],
                      if (_signUpMode) ...[
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: scheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                Icons.info_outline,
                                size: 18,
                                color: scheme.onSurfaceVariant,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'Новый аккаунт создаётся без прав — доступ '
                                  'выдаёт администратор.',
                                  style: textTheme.bodySmall?.copyWith(
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      // ⚠️ ВРЕМЕННО: предупреждение режима саморегистрации супера.
                      if (_superRegMode) ...[
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: scheme.errorContainer,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                Icons.warning_amber_rounded,
                                size: 18,
                                color: scheme.onErrorContainer,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  '⚠️ Временно: аккаунт получит ПОЛНЫЙ доступ '
                                  '(супер-админ + управление клиниками). Уберите '
                                  'эту кнопку перед реальным продом.',
                                  style: textTheme.bodySmall?.copyWith(
                                    color: scheme.onErrorContainer,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      if (!_signUpMode && !_superRegMode) ...[
                        const SizedBox(height: 8),
                        CheckboxListTile(
                          value: _remember,
                          onChanged: _loading
                              ? null
                              : (v) => setState(() => _remember = v ?? true),
                          title: const Text('Запомнить логин'),
                          controlAffinity: ListTileControlAffinity.leading,
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                        ),
                      ],
                      if (_error != null) ...[
                        const SizedBox(height: 16),
                        Text(_error!, style: TextStyle(color: scheme.error)),
                      ],
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: _loading ? null : _submit,
                        child: _loading
                            ? const SizedBox(
                                height: 22,
                                width: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : Text(
                                _superRegMode
                                    ? 'Стать супер-админом'
                                    : (_signUpMode
                                          ? 'Создать аккаунт'
                                          : 'Войти'),
                              ),
                      ),
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: _loading
                            ? null
                            : () {
                                if (_superRegMode) {
                                  setState(() {
                                    _superRegMode = false;
                                    _error = null;
                                  });
                                } else {
                                  _toggleMode();
                                }
                              },
                        child: Text(
                          _superRegMode
                              ? 'Назад ко входу'
                              : (_signUpMode
                                    ? 'Уже есть аккаунт? Войти'
                                    : 'Создать аккаунт'),
                        ),
                      ),
                      // ⚠️ ВРЕМЕННО — УБРАТЬ вместе с TEMP-строкой в firestore.rules
                      // и методами registerSuperadminTemp.
                      if (!_signUpMode && !_superRegMode)
                        TextButton(
                          onPressed: _loading
                              ? null
                              : () => setState(() {
                                  _superRegMode = true;
                                  _error = null;
                                }),
                          style: TextButton.styleFrom(
                            foregroundColor: scheme.error,
                          ),
                          child: const Text(
                            'Регистрация супер-админа (временно)',
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
