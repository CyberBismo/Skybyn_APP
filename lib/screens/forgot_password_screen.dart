import 'package:flutter/material.dart';
import 'dart:ui';
import '../widgets/background_gradient.dart';
import '../widgets/app_colors.dart';
import '../services/translation_service.dart';
import '../widgets/translated_text.dart';
import '../utils/http_client.dart';
import 'dart:convert';
import '../config/constants.dart';

enum _Stage { request, verify, setPassword, done }

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  _Stage _stage = _Stage.request;

  final _identifierController = TextEditingController();
  final _codeController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _obscureNew = true;
  bool _obscureConfirm = true;
  bool _isLoading = false;
  String? _errorMessage;
  String? _successMessage;
  String? _verifiedCode;

  @override
  void dispose() {
    _identifierController.dispose();
    _codeController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _requestReset() async {
    final identifier = _identifierController.text.trim();
    if (identifier.isEmpty) {
      setState(() => _errorMessage = TranslationKeys.fieldRequired.tr);
      return;
    }
    setState(() { _isLoading = true; _errorMessage = null; _successMessage = null; });
    try {
      final response = await globalAuthClient.post(
        Uri.parse(ApiConstants.forgotPassword),
        body: {'identifier': identifier},
      ).timeout(const Duration(seconds: 30));
      if (!mounted) return;
      final data = json.decode(response.body);
      if (response.statusCode == 200 && data['responseCode'] == '1') {
        setState(() {
          _isLoading = false;
          _stage = _Stage.verify;
          _successMessage = data['message'];
          _errorMessage = null;
        });
      } else {
        setState(() {
          _isLoading = false;
          _errorMessage = data['message'] ?? TranslationKeys.connectionError.tr;
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() { _isLoading = false; _errorMessage = TranslationKeys.connectionError.tr; });
    }
  }

  Future<void> _verifyCode() async {
    final code = _codeController.text.trim();
    if (code.isEmpty) {
      setState(() => _errorMessage = TranslationKeys.fieldRequired.tr);
      return;
    }
    setState(() { _isLoading = true; _errorMessage = null; _successMessage = null; });
    try {
      final response = await globalAuthClient.post(
        Uri.parse(ApiConstants.resetPassword),
        body: {'code': code},
      ).timeout(const Duration(seconds: 30));
      if (!mounted) return;
      final data = json.decode(response.body);
      if (response.statusCode == 200 && data['responseCode'] == '1') {
        setState(() {
          _isLoading = false;
          _verifiedCode = code;
          _stage = _Stage.setPassword;
          _errorMessage = null;
        });
      } else {
        setState(() {
          _isLoading = false;
          _errorMessage = data['message'] ?? TranslationKeys.connectionError.tr;
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() { _isLoading = false; _errorMessage = TranslationKeys.connectionError.tr; });
    }
  }

  Future<void> _setPassword() async {
    final newPw = _newPasswordController.text;
    final confirmPw = _confirmPasswordController.text;
    if (newPw.isEmpty || confirmPw.isEmpty) {
      setState(() => _errorMessage = TranslationKeys.fieldRequired.tr);
      return;
    }
    if (newPw != confirmPw) {
      setState(() => _errorMessage = TranslationKeys.passwordsDoNotMatch.tr);
      return;
    }
    setState(() { _isLoading = true; _errorMessage = null; });
    try {
      final response = await globalAuthClient.post(
        Uri.parse(ApiConstants.resetPassword),
        body: {'code': _verifiedCode!, 'new_pw': newPw, 'cnew_pw': confirmPw},
      ).timeout(const Duration(seconds: 30));
      if (!mounted) return;
      final data = json.decode(response.body);
      if (response.statusCode == 200 && data['responseCode'] == '1') {
        setState(() {
          _isLoading = false;
          _stage = _Stage.done;
          _successMessage = data['message'];
        });
        await Future.delayed(const Duration(seconds: 2));
        if (mounted) Navigator.of(context).pop();
      } else {
        setState(() {
          _isLoading = false;
          _errorMessage = data['message'] ?? TranslationKeys.connectionError.tr;
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() { _isLoading = false; _errorMessage = TranslationKeys.connectionError.tr; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          const BackgroundGradient(),
          SafeArea(
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20.0, 20.0, 20.0, 0.0),
                child: Column(
                  children: [
                    const SizedBox(height: 60),
                    Image.asset('assets/images/logo.png', width: 150, height: 150),
                    const SizedBox(height: 10),
                    _buildHeader(),
                    const SizedBox(height: 20),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 300),
                      transitionBuilder: (child, animation) =>
                          FadeTransition(opacity: animation, child: child),
                      child: KeyedSubtree(
                        key: ValueKey(_stage),
                        child: _buildStageContent(),
                      ),
                    ),
                    if (_errorMessage != null) ...[
                      const SizedBox(height: 10),
                      _buildBanner(_errorMessage!, isError: true),
                    ],
                    if (_successMessage != null && _stage != _Stage.done) ...[
                      const SizedBox(height: 10),
                      _buildBanner(_successMessage!, isError: false),
                    ],
                    const SizedBox(height: 30),
                    if (_stage != _Stage.done) _buildBackButton(),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    final subtitle = switch (_stage) {
      _Stage.request     => 'Enter your username or email',
      _Stage.verify      => TranslationKeys.enterVerificationCode.tr,
      _Stage.setPassword => TranslationKeys.resetPassword.tr,
      _Stage.done        => TranslationKeys.done.tr,
    };
    return Column(
      children: [
        const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TranslatedText(
              'intro',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w300, color: Colors.white, letterSpacing: 1.0),
            ),
            Text(
              'Skybyn',
              style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.white, letterSpacing: 1.0),
            ),
          ],
        ),
        const SizedBox(height: 10),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: Text(
            key: ValueKey(_stage),
            subtitle,
            style: TextStyle(fontSize: 14, color: Colors.white.withValues(alpha: 0.7), letterSpacing: 0.5),
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }

  Widget _buildStageContent() {
    return switch (_stage) {
      _Stage.request     => _buildRequestStage(),
      _Stage.verify      => _buildVerifyStage(),
      _Stage.setPassword => _buildSetPasswordStage(),
      _Stage.done        => _buildDoneStage(),
    };
  }

  Widget _buildRequestStage() {
    return Column(
      children: [
        _buildGlassField(
          controller: _identifierController,
          hint: 'Username or Email',
          icon: Icons.person,
          keyboardType: TextInputType.emailAddress,
          onSubmitted: (_) => _requestReset(),
        ),
        const SizedBox(height: 20),
        _buildPrimaryButton(
          label: TranslationKeys.requestPwReset.tr,
          icon: Icons.email_outlined,
          onTap: _isLoading ? null : _requestReset,
        ),
        const SizedBox(height: 12),
        _buildTextLink(
          label: 'Already have a code?',
          onTap: _isLoading
              ? null
              : () => setState(() { _stage = _Stage.verify; _errorMessage = null; _successMessage = null; }),
        ),
      ],
    );
  }

  Widget _buildVerifyStage() {
    return Column(
      children: [
        _buildGlassField(
          controller: _codeController,
          hint: TranslationKeys.verificationCode.tr,
          icon: Icons.lock_reset,
          keyboardType: TextInputType.number,
          onSubmitted: (_) => _verifyCode(),
        ),
        const SizedBox(height: 20),
        _buildPrimaryButton(
          label: TranslationKeys.confirm.tr,
          icon: Icons.check_circle_outline,
          onTap: _isLoading ? null : _verifyCode,
        ),
        const SizedBox(height: 12),
        _buildTextLink(
          label: 'Request a new code',
          onTap: _isLoading
              ? null
              : () => setState(() { _stage = _Stage.request; _errorMessage = null; _successMessage = null; }),
        ),
      ],
    );
  }

  Widget _buildSetPasswordStage() {
    return Column(
      children: [
        _buildPasswordField(
          controller: _newPasswordController,
          hint: TranslationKeys.newPassword.tr,
          obscure: _obscureNew,
          onToggle: () => setState(() => _obscureNew = !_obscureNew),
        ),
        const SizedBox(height: 16),
        _buildPasswordField(
          controller: _confirmPasswordController,
          hint: TranslationKeys.confirmNewPassword.tr,
          obscure: _obscureConfirm,
          onToggle: () => setState(() => _obscureConfirm = !_obscureConfirm),
          onSubmitted: (_) => _setPassword(),
        ),
        const SizedBox(height: 20),
        _buildPrimaryButton(
          label: TranslationKeys.resetPassword.tr,
          icon: Icons.lock_outline,
          onTap: _isLoading ? null : _setPassword,
        ),
      ],
    );
  }

  Widget _buildDoneStage() {
    return Column(
      children: [
        const Icon(Icons.check_circle_outline, color: Colors.greenAccent, size: 64),
        const SizedBox(height: 16),
        Text(
          _successMessage ?? '',
          style: const TextStyle(color: Colors.white, fontSize: 16),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildGlassField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
    void Function(String)? onSubmitted,
  }) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.getCardBackgroundColor(context).withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.white.withValues(alpha: 0.3), width: 1.5),
          ),
          child: TextField(
            controller: controller,
            keyboardType: keyboardType,
            textInputAction: onSubmitted != null ? TextInputAction.done : TextInputAction.next,
            onSubmitted: onSubmitted,
            decoration: InputDecoration(
              filled: true,
              fillColor: Colors.transparent,
              hintText: hint,
              hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 16),
              prefixIcon: Icon(icon, color: Colors.white),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            ),
            style: const TextStyle(color: Colors.white, fontSize: 16),
          ),
        ),
      ),
    );
  }

  Widget _buildPasswordField({
    required TextEditingController controller,
    required String hint,
    required bool obscure,
    required VoidCallback onToggle,
    void Function(String)? onSubmitted,
  }) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.getCardBackgroundColor(context).withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.white.withValues(alpha: 0.3), width: 1.5),
          ),
          child: TextField(
            controller: controller,
            obscureText: obscure,
            textInputAction: onSubmitted != null ? TextInputAction.done : TextInputAction.next,
            onSubmitted: onSubmitted,
            decoration: InputDecoration(
              filled: true,
              fillColor: Colors.transparent,
              hintText: hint,
              hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 16),
              prefixIcon: const Icon(Icons.lock_outline, color: Colors.white),
              suffixIcon: IconButton(
                icon: Icon(
                  obscure ? Icons.visibility_off : Icons.visibility,
                  color: Colors.white.withValues(alpha: 0.7),
                ),
                onPressed: onToggle,
              ),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            ),
            style: const TextStyle(color: Colors.white, fontSize: 16),
          ),
        ),
      ),
    );
  }

  Widget _buildPrimaryButton({required String label, required IconData icon, VoidCallback? onTap}) {
    return SizedBox(
      width: double.infinity,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
          child: Container(
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color.fromRGBO(70, 130, 180, 0.8), Color.fromRGBO(100, 149, 237, 0.8)],
              ),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white.withValues(alpha: 0.3), width: 1.5),
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onTap,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Center(
                    child: _isLoading
                        ? const SizedBox(
                            height: 24,
                            width: 24,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(icon, color: Colors.white, size: 20),
                              const SizedBox(width: 8),
                              Text(
                                label,
                                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Colors.white, letterSpacing: 0.5),
                              ),
                            ],
                          ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTextLink({required String label, VoidCallback? onTap}) {
    return TextButton(
      onPressed: onTap,
      child: Text(
        label,
        style: TextStyle(
          color: Colors.white.withValues(alpha: onTap == null ? 0.4 : 0.8),
          fontSize: 14,
          decoration: TextDecoration.underline,
          decorationColor: Colors.white.withValues(alpha: 0.4),
        ),
      ),
    );
  }

  Widget _buildBackButton() {
    return Center(
      child: SizedBox(
        width: MediaQuery.of(context).size.width * 0.7,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 3, sigmaY: 3),
            child: Container(
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color.fromRGBO(50, 205, 50, 0.8), Color.fromRGBO(34, 139, 34, 0.8)],
                ),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white.withValues(alpha: 0.3), width: 1.0),
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => Navigator.of(context).pop(),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Center(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.arrow_back_rounded, color: Colors.white, size: 16),
                          const SizedBox(width: 6),
                          TranslatedText(
                            TranslationKeys.back,
                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white, letterSpacing: 0.5),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBanner(String message, {required bool isError}) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: (isError ? Colors.red : Colors.green).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: (isError ? Colors.red : Colors.green).withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(
            isError ? Icons.error_outline : Icons.check_circle_outline,
            color: isError ? Colors.red : Colors.green,
            size: 20,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: isError ? Colors.red : Colors.green, fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }
}
