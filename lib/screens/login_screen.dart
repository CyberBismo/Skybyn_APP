import 'package:flutter/material.dart';
import 'dart:ui';
import '../services/auth_service.dart';
import '../widgets/background_gradient.dart';
import '../widgets/app_colors.dart';
import '../widgets/translated_text.dart';
import '../services/translation_service.dart';
import '../services/navigation_service.dart';
import '../widgets/app_banner.dart';
import '../config/constants.dart';
import 'home_screen.dart';
import 'register_screen.dart';
import 'forgot_password_screen.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final FocusNode _usernameFocusNode = FocusNode();
  final FocusNode _passwordFocusNode = FocusNode();
  final AuthService _authService = AuthService();
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _isSocialLoginEnabled = false;

  // Remembered accounts
  List<Map<String, String?>> _accounts = [];
  int _selectedAccountIndex = 0;
  bool _accountsChecked = false;
  bool _showFullForm = false;

  @override
  void initState() {
    super.initState();
    _checkSocialLoginStatus();
    _loadAccounts();
  }

  Future<void> _loadAccounts() async {
    final accounts = await _authService.getRememberedAccounts();
    if (mounted) {
      setState(() {
        _accounts = accounts;
        _accountsChecked = true;
        _showFullForm = accounts.isEmpty;
      });
    }
  }

  Future<void> _checkSocialLoginStatus() async {
    try {
      final enabled = await _authService.getSocialLoginStatus();
      if (mounted) {
        setState(() {
          _isSocialLoginEnabled = enabled;
        });
      }
    } catch (e) {
      // Ignore errors, default is false
    }
  }

  Future<void> _onLoginSuccess() async {
    if (!mounted) return;

    await NavigationService.saveLastRoute('/home');

    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (context) => const HomeScreen()),
      );
    }
  }

  Future<void> _handleGoogleLogin() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final GoogleSignIn googleSignIn = GoogleSignIn();
      await googleSignIn.signOut();
      final GoogleSignInAccount? googleUser = await googleSignIn.signIn();

      if (googleUser == null) {
        setState(() {
          _isLoading = false;
        });
        return;
      }

      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
      final String? idToken = googleAuth.idToken;

      if (idToken == null) {
        throw Exception('Failed to get ID Token from Google');
      }

      final response = await _authService.loginWithSocial('google', idToken);

      if (!mounted) return;

      if (response['responseCode'] == '1') {
        await _onLoginSuccess();
      } else {
        AppBanner.error(response['message'] ?? 'Google Login failed');
      }
    } catch (e) {
      if (!mounted) return;
      AppBanner.error('Google Sign-In Error: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  /*
  Future<void> _handleFacebookLogin() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final LoginResult result = await FacebookAuth.instance.login(
        permissions: ['public_profile', 'email'],
      );

      if (result.status == LoginStatus.success) {
        final AccessToken accessToken = result.accessToken!;
        final response = await _authService.loginWithSocial('facebook', accessToken.tokenString);
        
        if (!mounted) return;

        if (response['responseCode'] == '1') {
          await _onLoginSuccess();
        } else {
          setState(() {
             _errorMessage = response['message'] ?? 'Facebook Login failed';
          });
        }
      } else if (result.status == LoginStatus.cancelled) {
         // User cancelled
      } else {
         setState(() {
           _errorMessage = result.message ?? 'Facebook Login failed';
         });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Facebook Sign-In Error: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }
  */

  Future<void> _handleLogin() async {
    final username = (!_showFullForm && _accounts.isNotEmpty)
        ? (_accounts[_selectedAccountIndex]['username'] ?? '')
        : _usernameController.text;

    if (username.isEmpty || _passwordController.text.isEmpty) {
      AppBanner.error(TranslationKeys.fieldRequired.tr);
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final response = await _authService.login(
        username,
        _passwordController.text,
      );

      if (!mounted) return;

      if (response['responseCode'] == '1') {
        await _onLoginSuccess();
      } else {
        AppBanner.error(response['message'] ?? TranslationKeys.loginFailedCheckCredentials.tr);
      }
    } catch (e) {
      if (!mounted) return;
      AppBanner.error(TranslationKeys.connectionError.tr);
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _usernameFocusNode.dispose();
    _passwordFocusNode.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Widget _buildPasswordField() {
    return ListenableBuilder(
      listenable: TranslationService(),
      builder: (context, _) {
        final translationService = TranslationService();
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
                controller: _passwordController,
                focusNode: _passwordFocusNode,
                obscureText: _obscurePassword,
                textInputAction: TextInputAction.go,
                decoration: InputDecoration(
                  filled: true,
                  fillColor: Colors.transparent,
                  hintText: translationService.translate(TranslationKeys.password),
                  hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 16),
                  prefixIcon: const Icon(Icons.lock, color: Colors.white),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscurePassword ? Icons.visibility : Icons.visibility_off,
                      color: Colors.white.withValues(alpha: 0.7),
                    ),
                    onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                  ),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                ),
                style: const TextStyle(color: Colors.white, fontSize: 16),
                onSubmitted: (_) => _handleLogin(),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildLoginButton() {
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
                onTap: _isLoading ? null : _handleLogin,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Center(
                    child: _isLoading
                        ? const SizedBox(
                            height: 24,
                            width: 24,
                            child: CircularProgressIndicator(strokeWidth: 2.5, valueColor: AlwaysStoppedAnimation<Color>(Colors.white)),
                          )
                        : const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.login_rounded, color: Colors.white, size: 20),
                              SizedBox(width: 8),
                              TranslatedText(TranslationKeys.login, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Colors.white, letterSpacing: 0.5)),
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

  Widget _buildRegisterButton() {
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
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (context) => const RegisterScreen())),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: const Center(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.person_add_rounded, color: Colors.white, size: 16),
                          SizedBox(width: 6),
                          TranslatedText(TranslationKeys.register, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white, letterSpacing: 0.5)),
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

  String _buildAvatarUrl(String? path) {
    if (path == null || path.isEmpty) return '';
    if (path.startsWith('http')) return path;
    return '${ApiConstants.webBase}/$path';
  }

  Widget _buildAccountBubble(int index) {
    final account = _accounts[index];
    final username = account['username'] ?? '';
    final avatarUrl = _buildAvatarUrl(account['avatar']);
    final isSelected = index == _selectedAccountIndex;

    return GestureDetector(
      onTap: () => setState(() {
        _selectedAccountIndex = index;
        _passwordController.clear();
      }),
      child: Column(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: isSelected ? Colors.white : Colors.transparent,
                width: 3,
              ),
            ),
            child: CircleAvatar(
              radius: isSelected ? 36 : 28,
              backgroundColor: Colors.white.withValues(alpha: 0.2),
              backgroundImage: avatarUrl.isNotEmpty ? NetworkImage(avatarUrl) : null,
              child: avatarUrl.isEmpty ? const Icon(Icons.person, color: Colors.white) : null,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            username,
            style: TextStyle(
              color: isSelected ? Colors.white : Colors.white60,
              fontSize: isSelected ? 13 : 11,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildAccountsView() {
    final selected = _accounts[_selectedAccountIndex];
    final username = selected['username'] ?? '';

    return Column(
      children: [
        const SizedBox(height: 8),
        // Avatar bubbles row
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (int i = 0; i < _accounts.length; i++) ...[
              if (i > 0) const SizedBox(width: 16),
              _buildAccountBubble(i),
            ],
          ],
        ),
        const SizedBox(height: 16),
        // Selected username
        Text(
          username,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
        ),
        const SizedBox(height: 20),
        _buildPasswordField(),
        const SizedBox(height: 20),
        _buildLoginButton(),
        const SizedBox(height: 16),
        TextButton.icon(
          onPressed: () => setState(() {
            _showFullForm = true;
            _passwordController.clear();
          }),
          icon: const Icon(Icons.add, color: Colors.white70, size: 18),
          label: const Text('Add account', style: TextStyle(color: Colors.white70, fontSize: 16)),
        ),
      ],
    );
  }

  Widget _buildFullLoginForm() {
    return Column(
      children: [
        if (_accounts.isNotEmpty) ...[
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => setState(() {
                _showFullForm = false;
                _usernameController.clear();
                _passwordController.clear();
              }),
              icon: const Icon(Icons.arrow_back, color: Colors.white70, size: 18),
              label: const Text('Back', style: TextStyle(color: Colors.white70, fontSize: 14)),
            ),
          ),
          const SizedBox(height: 4),
        ],
        // Username field
        ListenableBuilder(
          listenable: TranslationService(),
          builder: (context, _) {
            final translationService = TranslationService();
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
                    controller: _usernameController,
                    focusNode: _usernameFocusNode,
                    textInputAction: TextInputAction.next,
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: Colors.transparent,
                      hintText: translationService.translate(TranslationKeys.username),
                      hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 16),
                      prefixIcon: const Icon(Icons.person, color: Colors.white),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                    ),
                    style: const TextStyle(color: Colors.white, fontSize: 16),
                    onSubmitted: (_) => _passwordFocusNode.requestFocus(),
                  ),
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 20),
        _buildPasswordField(),
        const SizedBox(height: 30),
        _buildLoginButton(),
        if (_isSocialLoginEnabled) ...[
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              icon: Image.asset('assets/images/google_logo.png', height: 24),
              label: const TranslatedText(TranslationKeys.signInWithGoogle, style: TextStyle(color: Colors.white, fontSize: 16)),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12),
                side: BorderSide(color: Colors.white.withValues(alpha: 0.5)),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                backgroundColor: Colors.white.withValues(alpha: 0.1),
              ),
              onPressed: _isLoading ? null : _handleGoogleLogin,
            ),
          ),
        ],
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (context) => const ForgotPasswordScreen())),
            child: TranslatedText(TranslationKeys.forgotPassword, style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 18)),
          ),
        ),
      ],
    );
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
                    // Logo
                    Image.asset(
                      'assets/images/logo.png',
                      width: 150,
                      height: 150,
                    ),
                    // Welcome text
                    Column(
                      children: [
                        const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            TranslatedText(
                              'intro',
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w300,
                                color: Colors.white,
                                letterSpacing: 1.0,
                              ),
                            ),
                            Text(
                              'Skybyn',
                              style: TextStyle(
                                fontSize: 32,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                                letterSpacing: 1.0,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    if (_accountsChecked && !_showFullForm && _accounts.isNotEmpty)
                      _buildAccountsView()
                    else if (_accountsChecked)
                      _buildFullLoginForm(),
                    const SizedBox(height: 20),
                    _buildRegisterButton(),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
