import 'package:flutter/material.dart';
import '../widgets/background_gradient.dart';
import '../widgets/custom_app_bar.dart';
import '../utils/translation_keys.dart';
import '../widgets/translated_text.dart';
import '../services/translation_service.dart';
import 'admin/user_management_screen.dart';
import 'admin/moderation_tools_screen.dart';
import 'admin/notification_test_screen.dart';

class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final statusBarHeight = mediaQuery.padding.top;
    const appBarHeight = 60.0;

    return Scaffold(
      body: Stack(
        children: [
          // Background gradient
          const BackgroundGradient(),
          
          // Content
          Column(
            children: [
              // App bar
              CustomAppBar(
                logoPath: 'assets/images/logo_faded_clean.png',
                onLogoPressed: () {
                  Navigator.of(context).pop();
                },
                appBarHeight: appBarHeight,
              ),
              
              // Main content
              Expanded(
                child: SingleChildScrollView(
                  padding: EdgeInsets.only(
                    top: statusBarHeight,
                    left: 16,
                    right: 16,
                    bottom: 16,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 20),
                      
                      // Title
                      const TranslatedText(
                        TranslationKeys.adminPanel,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          decoration: TextDecoration.none,
                        ),
                      ),
                      
                      const SizedBox(height: 24),
                      
                      // Admin features section
                      _buildSection(
                        title: 'Admin Features',
                        children: [
                          _buildFeatureCard(
                            icon: Icons.people,
                            title: translationService.translate(TranslationKeys.userManagement),
                            description: 'Manage users, view profiles, and handle user-related actions',
                            onTap: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (context) => const UserManagementScreen(),
                                ),
                              );
                            },
                          ),
                          const SizedBox(height: 12),
                          _buildFeatureCard(
                            icon: Icons.shield,
                            title: translationService.translate(TranslationKeys.moderationTools),
                            description: 'Review reports, moderate content, and manage community guidelines',
                            onTap: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (context) => const ModerationToolsScreen(),
                                ),
                              );
                            },
                          ),
                           const SizedBox(height: 12),
                          _buildFeatureCard(
                            icon: Icons.notifications,
                            title: 'Notification Testing',
                            description: 'Test all types of notifications, including Firebase notifications',
                            onTap: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (context) => const NotificationTestScreen(),
                                ),
                              );
                            },
                          ),
                          const SizedBox(height: 12),
                          _buildFeatureCard(
                            icon: Icons.settings,
                            title: translationService.translate(TranslationKeys.systemSettings),
                            description: 'Configure system-wide settings and preferences',
                            onTap: () {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(translationService.translate(TranslationKeys.comingSoon)),
                                  duration: const Duration(seconds: 2),
                                ),
                              );
                            },
                          ),
                          const SizedBox(height: 12),
                          _buildFeatureCard(
                            icon: Icons.analytics,
                            title: translationService.translate(TranslationKeys.analyticsAndReports),
                            description: 'View platform statistics, user activity, and system reports',
                            onTap: () {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(translationService.translate(TranslationKeys.comingSoon)),
                                  duration: const Duration(seconds: 2),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSection({
    required String title,
    required List<Widget> children,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
            decoration: TextDecoration.none,
          ),
        ),
        const SizedBox(height: 16),
        ...children,
      ],
    );
  }

  Widget _buildFeatureCard({
    required IconData icon,
    required String title,
    required String description,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.10),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: Colors.white.withOpacity(0.2),
              width: 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  icon,
                  color: Colors.white,
                  size: 24,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        decoration: TextDecoration.none,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      description,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.7),
                        fontSize: 14,
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right,
                color: Colors.white70,
                size: 24,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
