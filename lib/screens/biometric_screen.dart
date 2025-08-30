import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/local_auth_service.dart';
import 'home_screen.dart'; // Or your main app screen
import 'login_screen.dart';
import '../services/auth_service.dart';

class BiometricScreen extends StatefulWidget {
  const BiometricScreen({super.key});

  @override
  State<BiometricScreen> createState() => _BiometricScreenState();
}

class _BiometricScreenState extends State<BiometricScreen> {
  @override
  void initState() {
    super.initState();
    _authenticateAndNavigate();
  }

  Future<void> _authenticateAndNavigate() async {
    final isAuthenticated = await LocalAuthService.authenticate();
    if (!mounted) return;

    if (isAuthenticated) {
      final authService = AuthService();
      final userId = await authService.getStoredUserId();
      if (mounted && userId != null) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (context) => const HomeScreen()),
        );
      } else if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (context) => const LoginScreen()),
        );
      }
    } else {
      // Show a dialog or a message on the screen to retry
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          backgroundColor: Colors.grey[900],
          title: const Text(
            'Authentication Failed',
            style: TextStyle(color: Colors.white),
          ),
          content: const Text(
            'Could not verify your identity. Please try again.',
            style: TextStyle(color: Colors.white70),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                _authenticateAndNavigate(); // Retry
              },
              child: const Text(
                'Try Again',
                style: TextStyle(color: Colors.blue),
              ),
            ),
            TextButton(
              onPressed: () => SystemNavigator.pop(), // Exit app
              child: const Text(
                'Exit',
                style: TextStyle(color: Colors.red),
              ),
            ),
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF243B55), // Dark blue from web dark mode
              Color(0xFF141E30), // Almost black from web dark mode
            ],
          ),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Image.asset(
                'assets/images/logo.png',
                height: 120,
              ),
              const SizedBox(height: 20),
              const Text(
                'Authenticating...',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 10),
              const CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            ],
          ),
        ),
      ),
    );
  }
} 