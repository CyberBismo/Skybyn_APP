import 'package:flutter/material.dart';
import 'dart:ui';
import '../services/auth_service.dart';
import '../services/notification_service.dart';
import 'dart:io';
import '../widgets/background_gradient.dart';
import '../widgets/app_colors.dart';
import 'home_screen.dart';
import 'register_screen.dart';

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

  @override
  void initState() {
    super.initState();
    // Auto-focus the username field when the screen opens
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _usernameFocusNode.requestFocus();
      }
    });
  }

  Future<void> _handleLogin() async {
    if (_usernameController.text.isEmpty || _passwordController.text.isEmpty) {
      setState(() {
        _errorMessage = 'Please fill in all fields';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // Debug platform info
      print('Platform: ${Platform.isAndroid ? 'Android' : 'iOS'}');
      
      final response = await _authService.login(
        _usernameController.text,
        _passwordController.text,
      );

      if (!mounted) return;

      if (response['responseCode'] == '1') {
        if (mounted) {
          // Show login success notification
          print('🔔 Attempting to show login success notification...');
          try {
            final notificationService = NotificationService();
            await notificationService.requestPermissions();
            
            // Check if notifications are enabled
            final isEnabled = await notificationService.areNotificationsEnabled();
            print('📱 Notifications enabled: $isEnabled');
            
            // For iOS, check notification status
            if (Platform.isIOS) {
              await notificationService.checkIOSNotificationStatus();
            }
            
            if (isEnabled) {
              // Show system notification for login success
              await notificationService.showNotification(
                title: 'Login successful',
                body: 'Welcome to Skybyn',
                payload: 'login_success',
              );
              print('✅ Login success notification sent successfully');
            }
          } catch (e) {
            print('❌ Error showing login notification: $e');
          }
          
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (context) => const HomeScreen()),
          );
        }
      } else {
        setState(() {
          _errorMessage = response['message'] ?? 'Login failed. Please check your credentials and try again.';
        });
      }
    } catch (e) {
      print('Login error: $e');
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Connection error. Please check your internet connection and try again.';
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
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  children: [
                    const SizedBox(height: 60),
                    // Logo
                    Image.asset(
                      'assets/images/logo.png',
                      width: 150,
                      height: 150,
                    ),
                    const SizedBox(height: 60),
                    // Username field
                    ClipRRect(
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
                            decoration: InputDecoration(
                              filled: true,
                              fillColor: Colors.transparent,
                              hintText: 'Username',
                              hintStyle: TextStyle(
                                color: Colors.white.withValues(alpha: 0.7), // White hint in both modes
                                fontSize: 16,
                              ),
                              prefixIcon: Icon(Icons.person, color: Colors.white), // White icon in both modes
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: BorderSide.none,
                              ),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                            ),
                            style: TextStyle(
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
                    ),
                    const SizedBox(height: 20),
                    // Password field
                    ClipRRect(
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
                            decoration: InputDecoration(
                              filled: true,
                              fillColor: Colors.transparent,
                              hintText: 'Password',
                              hintStyle: TextStyle(
                                color: Colors.white.withValues(alpha: 0.7), // White hint in both modes
                                fontSize: 16,
                              ),
                              prefixIcon: Icon(Icons.lock, color: Colors.white), // White icon in both modes
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
                            style: TextStyle(
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
                    ClipRRect(
                      borderRadius: BorderRadius.circular(15),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
                        child: Container(
                          width: double.infinity,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                const Color(0xFF4682B4).withValues(alpha: 0.8),  // Steel blue
                                const Color(0xFF6495ED).withValues(alpha: 0.8),  // Cornflower blue
                              ],
                            ),
                            borderRadius: BorderRadius.circular(15),
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
                                      ? SizedBox(
                                          height: 24,
                                          width: 24,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2.5,
                                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white), // White loading indicator in both modes
                                          ),
                                        )
                                      : Row(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            Icon(
                                              Icons.login_rounded,
                                              color: Colors.white, // White icon in both modes
                                              size: 20,
                                            ),
                                            const SizedBox(width: 8),
                                                                                          Text(
                                                'Login',
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
                    const SizedBox(height: 20),
                    // Register button
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 3, sigmaY: 3),
                        child: Container(
                          width: double.infinity * 0.3, // Make it much shorter in width
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                const Color(0xFF32CD32).withValues(alpha: 0.8),  // Lime green
                                const Color(0xFF228B22).withValues(alpha: 0.8),  // Forest green
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
                                child: Center(
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        Icons.person_add_rounded,
                                        color: Colors.white, // White icon in both modes
                                        size: 16, // Even smaller icon
                                      ),
                                      const SizedBox(width: 6), // Smaller spacing
                                      Text(
                                        'Register',
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