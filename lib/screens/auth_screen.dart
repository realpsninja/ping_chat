import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/api_service.dart';
import '../services/crypto_service.dart';
import '../services/socket_service.dart';
import 'chats_screen.dart';

class AuthScreen extends StatefulWidget {
  final String? savedNickname;
  const AuthScreen({super.key, this.savedNickname});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen>
    with TickerProviderStateMixin {
  final _pinController = TextEditingController();
  final _nicknameController = TextEditingController();

  bool _isLogin = false;
  bool _loading = false;
  // ignore: unused_field
  String? _error;

  static const int pinLength = 4;
  late final List<AnimationController> _pinAnimations;

  @override
  void initState() {
    super.initState();

    _pinAnimations = List.generate(
      pinLength,
      (_) => AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 180),
      ),
    );

    if (widget.savedNickname != null) {
      _isLogin = true;
      _nicknameController.text = widget.savedNickname!;
    }
  }

  @override
  void dispose() {
    for (final c in _pinAnimations) {
      c.dispose();
    }
    _pinController.dispose();
    _nicknameController.dispose();
    super.dispose();
  }

  // ================= AUTH =================

  Future<void> _submit() async {
    final pin = _pinController.text.trim();

    if (pin.length != pinLength) {
      setState(() => _error = 'PIN-код должен содержать $pinLength цифры');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      Map<String, dynamic> response;

      if (_isLogin) {
        final nickname = _nicknameController.text.trim();
        if (nickname.isEmpty) {
          setState(() => _error = 'Введите логин (никнейм)');
          return;
        }
        response = await ApiService().login(nickname, pin);
      } else {
        response = await ApiService().register(pin);
      }

      final token = response['token'];
      final user = response['user'];

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('token', token);
      await prefs.setString('nickname', user['nickname']);
      await prefs.setInt('userId', user['id']);

      ApiService().setToken(token);
      await CryptoService().loadOrGenerateKeys();

      final publicKey = CryptoService().getPublicKeyPem();
      await ApiService().savePublicKey(publicKey);

      SocketService().connect(token);

      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const ChatsScreen()),
      );
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _loading = false);
    }
  }

  // ================= PIN UI =================

  Widget _buildPinDisplay() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(pinLength, (i) {
        final hasValue = _pinController.text.length > i;

        if (hasValue) {
          _pinAnimations[i].forward(from: 0);
        }

        return Container(
          width: 32,
          margin: const EdgeInsets.symmetric(horizontal: 8),
          padding: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                width: 2,
                color: hasValue
                    ? const Color(0xFF7373d3)
                    : const Color(0xFF33333e),
              ),
            ),
          ),
          alignment: Alignment.center,
          child: ScaleTransition(
            scale: Tween(begin: 0.6, end: 1.0).animate(
              CurvedAnimation(
                parent: _pinAnimations[i],
                curve: Curves.easeOutBack,
              ),
            ),
            child: Text(
              hasValue ? _pinController.text[i] : '',
              style: const TextStyle(
                fontSize: 24,
                color: Colors.white,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        );
      }),
    );
  }

  // ================= CUSTOM KEYPAD =================

  void _addDigit(String digit) {
    if (_pinController.text.length >= pinLength) return;

    HapticFeedback.lightImpact();

    setState(() {
      _pinController.text += digit;
    });

    if (_pinController.text.length == pinLength) {
      HapticFeedback.mediumImpact();
      Future.delayed(const Duration(milliseconds: 120), _submit);
    }
  }

  void _removeDigit() {
    if (_pinController.text.isEmpty) return;

    HapticFeedback.selectionClick();

    setState(() {
      _pinController.text =
          _pinController.text.substring(0, _pinController.text.length - 1);
    });
  }

  Widget _key(String label, {VoidCallback? onTap}) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: SizedBox(
        height: 60,
        child: Center(
          child: label == '⌫'
              ? const Icon(Icons.backspace, color: Colors.white)
              : Text(
                  label,
                  style: const TextStyle(
                    fontSize: 22,
                    color: Colors.white,
                    fontWeight: FontWeight.w500,
                  ),
                ),
        ),
      ),
    );
  }

  Widget _buildKeyboard() {
    return GridView.count(
      shrinkWrap: true,
      crossAxisCount: 3,
      childAspectRatio: 1.6,
      physics: const NeverScrollableScrollPhysics(),
      children: [
        for (var i = 1; i <= 9; i++)
          _key('$i', onTap: () => _addDigit('$i')),
        const SizedBox.shrink(),
        _key('0', onTap: () => _addDigit('0')),
        _key('⌫', onTap: _removeDigit),
      ],
    );
  }

  // ================= BUTTON =================

  Widget _button(String text, VoidCallback onTap, Color color) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        onPressed: _loading ? null : onTap,
        child: Text(
          text,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
        ),
      ),
    );
  }

  // ================= UI =================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1c1c1c),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
          child: Column(
            children: [
              const SizedBox(height: 14),

              // ICON
              Container(
                width: 66,
                height: 66,
                decoration: BoxDecoration(
                  color: const Color(0xFF33333e),
                  borderRadius: BorderRadius.circular(18),
                ),
                child:
                    const Icon(Icons.lock, color: Colors.white, size: 32),
              ),

              const SizedBox(height: 16),

              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      if (!_isLogin) ...[
                        const Text(
                          'Регистрация',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          'Придумайте пин-код для аккаунта,\nникнейм будет\nсгенерирован автоматически.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white70,
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 28),
                        _buildPinDisplay(),
                        const SizedBox(height: 28),
                        _buildKeyboard(),
                        const SizedBox(height: 16),
                        _button(
                          'Войти в существующий аккаунт',
                          () => setState(() {
                            _isLogin = true;
                            _pinController.clear();
                          }),
                          const Color(0xFF33333e),
                        ),
                      ] else ...[
                        const Text(
                          'Авторизация',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 28),
                        TextField(
                          controller: _nicknameController,
                          style: const TextStyle(color: Colors.white),
                          decoration: _input('Никнейм'),
                          autofocus: true,
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: _pinController,
                          obscureText: true,
                          keyboardType: TextInputType.number,
                          style: const TextStyle(color: Colors.white),
                          decoration: _input('Пин-код'),
                          maxLength: pinLength,
                          maxLengthEnforcement: MaxLengthEnforcement.enforced,
                        ),
                        const SizedBox(height: 28),
                        _button(
                          'Войти',
                          _submit,
                          const Color(0xFF7373d3),
                        ),
                        const SizedBox(height: 16),
                        _button(
                          'Создать новый аккаунт',
                          () => setState(() {
                            _isLogin = false;
                            _pinController.clear();
                            _nicknameController.clear();
                          }),
                          const Color(0xFF33333e),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  InputDecoration _input(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Colors.white54),
        filled: true,
        fillColor: const Color(0xFF33333e),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      );
}
