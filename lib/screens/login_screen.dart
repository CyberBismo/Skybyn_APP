import 'package:flutter/material.dart';
import 'dart:ui';
import 'dart:async';
import '../services/auth_service.dart';
import '../services/notification_service.dart';
import '../services/firebase_messaging_service.dart';
import 'dart:io';
import '../widgets/background_gradient.dart';
import '../widgets/app_colors.dart';
import '../widgets/translated_text.dart';

import '../services/translation_service.dart';
import '../services/navigation_service.dart';
import 'home_screen.dart';
import 'register_screen.dart';
import 'forgot_password_screen.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter_facebook_auth/flutter_facebook_auth.dart';
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
  String? _errorMessage;



  bool _isSocialLoginEnabled = false;

  @override
  void initState() {
    super.initState();
    // Username field is no longer auto-focused
    _checkSocialLoginStatus();
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

    try {
      final notificationService = NotificationService();
      final firebaseMessagingService = FirebaseMessagingService();
      await notificationService.requestPermissions();
      await firebaseMessagingService.requestPermissions();
      final isEnabled = await notificationService.areNotificationsEnabled();
      if (Platform.isIOS) await notificationService.checkIOSNotificationStatus();

      if (isEnabled) {
        final int notificationId = await notificationService.showNotification(
          title: TranslationKeys.loginSuccessful.tr,
          body: TranslationKeys.welcomeToSkybyn.tr,
          payload: 'login_success',
        );
        if (notificationId >= 0) {
          Timer(const Duration(seconds: 3), () {
            notificationService.cancelNotification(notificationId);
          });
        }
      }
    } catch (e) {}

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
      _errorMessage = null;
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
        setState(() {
           _errorMessage = response['message'] ?? 'Google Login failed';
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Google Sign-In Error: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

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

  Future<void> _handleLogin() async {
    if (_usernameController.text.isEmpty || _passwordController.text.isEmpty) {
      setState(() {
        _errorMessage = TranslationKeys.fieldRequired.tr;
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // Debug platform info
      final response = await _authService.login(
        _usernameController.text,
        _passwordController.text,
      );

      if (!mounted) return;

      if (response['responseCode'] == '1') {
        await _onLoginSuccess();
      } else {
        setState(() {
          _errorMessage = response['message'] ?? TranslationKeys.loginFailedCheckCredentials.tr;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = TranslationKeys.connectionError.tr;
      });
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
                    const SizedBox(height: 10),
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
                                color: AppColors.getCardBackgroundColor(context).withValues(alpha: 0.1), // Keep original background
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.3), // White border in both modes
                                  width: 1.5,
                                ),
                              ),
                              child: TextField(
                                controller: _usernameController,
                                focusNode: _usernameFocusNode,
                                textInputAction: TextInputAction.next,
                                decoration: InputDecoration(
                                  filled: true,
                                  fillColor: Colors.transparent,
                                  hintText: translationService.translate(TranslationKeys.username),
                                  hintStyle: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.7), // White hint in both modes
                                    fontSize: 16,
                                  ),
                                  prefixIcon: const Icon(Icons.person, color: Colors.white), // White icon in both modes
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                    borderSide: BorderSide.none,
                                  ),
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                                ),
                                style: const TextStyle(
                                  color: Colors.white, // White text in both modes
                                  fontSize: 16,
                                ),
                                onTap: () {
                                  // Unfocus other fields to prevent context menu conflicts
                                  _passwordFocusNode.unfocus();
                                },
                                onSubmitted: (_) {
                                  // Move focus to password field when username is submitted
                                  _passwordFocusNode.requestFocus();
                                },
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 20),
                    // Password field
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
                                color: AppColors.getCardBackgroundColor(context).withValues(alpha: 0.1), // Keep original background
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.3), // White border in both modes
                                  width: 1.5,
                                ),
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
                                  hintStyle: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.7), // White hint in both modes
                                    fontSize: 16,
                                  ),
                                  prefixIcon: const Icon(Icons.lock, color: Colors.white), // White icon in both modes
                                  suffixIcon: IconButton(
                                    icon: Icon(
                                      _obscurePassword ? Icons.visibility : Icons.visibility_off,
                                      color: Colors.white.withValues(alpha: 0.7), // White icon in both modes
                                    ),
                                    onPressed: () {
                                      setState(() {
                                        _obscurePassword = !_obscurePassword;
                                      });
                                    },
                                  ),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                    borderSide: BorderSide.none,
                                  ),
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                                ),
                                style: const TextStyle(
                                  color: Colors.white, // White text in both modes
                                  fontSize: 16,
                                ),
                                onTap: () {
                                  // Unfocus other fields to prevent context menu conflicts
                                  _usernameFocusNode.unfocus();
                                },
                                onSubmitted: (_) {
                                  // Attempt login when password is submitted
                                  _handleLogin();
                                },
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                    if (_errorMessage != null) ...[
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.red.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.error_outline, color: Colors.red, size: 20),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _errorMessage!,
                                style: const TextStyle(
                                  color: Colors.red,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 30),
                    // Login button
                    SizedBox(
                      width: double.infinity, // 100% width
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
                          child: Container(
                            width: double.infinity, // 100% width
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  Color.fromRGBO(70, 130, 180, 0.8), // Steel blue
                                  Color.fromRGBO(100, 149, 237, 0.8), // Cornflower blue
                                ],
                              ),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.3), // White border in both modes
                                width: 1.5,
                              ),
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
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2.5,
                                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white), // White loading indicator in both modes
                                            ),
                                          )
                                        : const Row(
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            children: [
                                              Icon(
                                                Icons.login_rounded,
                                                color: Colors.white, // White icon in both modes
                                                size: 20,
                                              ),
                                              SizedBox(width: 8),
                                              TranslatedText(
                                                TranslationKeys.login,
                                                style: TextStyle(
                                                  fontSize: 18,
                                                  fontWeight: FontWeight.w600,
                                                  color: Colors.white, // White text in both modes
                                                  letterSpacing: 0.5,
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
                      ),
                    ),
                    if (_isSocialLoginEnabled) ...[
                      const SizedBox(height: 20),
                      // Social Login Buttons
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          icon: Image.asset(
                            'assets/images/google_logo.png', // Ensure you have this asset
                            height: 24,
                          ),
                          label: const TranslatedText(
                            TranslationKeys.signInWithGoogle,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                            ),
                          ),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            side: BorderSide(color: Colors.white.withValues(alpha: 0.5)),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            backgroundColor: Colors.white.withValues(alpha: 0.1),
                          ),
                          onPressed: _isLoading ? null : _handleGoogleLogin,
                        ),
                      ),
                      // Facebook Login Button - Removed per user request to restrict to Google only
                      /*
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          icon: const Icon(FontAwesomeIcons.facebook, color: Colors.blue),
                          label: const TranslatedText(
                            'Sign in with Facebook',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                            ),
                          ),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            side: BorderSide(color: Colors.white.withValues(alpha: 0.5)),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            backgroundColor: Colors.white.withValues(alpha: 0.1),
                          ),
                          onPressed: _isLoading ? null : _handleFacebookLogin,
                        ),
                      ),
                      */
                    ],
                    // Forgot password text
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton(
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (context) => const ForgotPasswordScreen(),
                            ),
                          );
                        },
                        child: TranslatedText(
                          TranslationKeys.forgotPassword,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.8),
                            fontSize: 18,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    // Register button
                    Center(
                      child: SizedBox(
                        width: MediaQuery.of(context).size.width * 0.7, // 80% of screen width
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: BackdropFilter(
                            filter: ImageFilter.blur(sigmaX: 3, sigmaY: 3),
                            child: Container(
                              width: double.infinity, // Take full width of SizedBox
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [
                                    Color.fromRGBO(50, 205, 50, 0.8), // Lime green
                                    Color.fromRGBO(34, 139, 34, 0.8), // Forest green
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.3), // White border in both modes
                                  width: 1.0,
                                ),
                              ),
                              child: Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  onTap: () {
                                    Navigator.of(context).push(
                                      MaterialPageRoute(builder: (context) => const RegisterScreen()),
                                    );
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(vertical: 8), // Even smaller padding
                                    child: const Center(
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Icon(
                                            Icons.person_add_rounded,
                                            color: Colors.white, // White icon in both modes
                                            size: 16, // Even smaller icon
                                          ),
                                          SizedBox(width: 6), // Smaller spacing
                                          TranslatedText(
                                            TranslationKeys.register,
                                            style: TextStyle(
                                              fontSize: 14, // Even smaller font
                                              fontWeight: FontWeight.w600,
                                              color: Colors.white, // White text in both modes
                                              letterSpacing: 0.5,
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
                        ),
                      ),
                    ),
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
