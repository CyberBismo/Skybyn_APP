import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';
import '../config/constants.dart';

class TranslationService extends ChangeNotifier {
  static final TranslationService _instance = TranslationService._internal();
  factory TranslationService() => _instance;
  TranslationService._internal();

  Map<String, Map<String, String>> _translations = {};
  String _currentLanguage = 'en';
  bool _isInitialized = false;

  // Supported languages
  static const List<String> supportedLanguages = ['en', 'no', 'dk', 'se', 'de', 'fr', 'pl', 'es', 'it', 'pt', 'nl', 'fi'];

  // Language names for display
  static const Map<String, String> languageNames = {
    'en': 'English',
    'no': 'Norsk',
    'dk': 'Dansk',
    'se': 'Svenska',
    'de': 'Deutsch',
    'fr': 'Français',
    'pl': 'Polski',
    'es': 'Español',
    'it': 'Italiano',
    'pt': 'Português',
    'nl': 'Nederlands',
    'fi': 'Suomi',
  };

  // Country to language mapping
  static const Map<String, String> countryToLanguageMap = {
    // English
    'US': 'en', 'GB': 'en', 'AU': 'en', 'CA': 'en', 'NZ': 'en', 'IE': 'en', 'ZA': 'en',
    // Norwegian
    'NO': 'no', 'SJ': 'no', 'BV': 'no',
    // Danish
    'DK': 'dk', 'GL': 'dk', 'FO': 'dk',
    // Swedish
    'SE': 'se',
    // German
    'DE': 'de', 'AT': 'de', 'CH': 'de', 'LI': 'de', 'LU': 'de',
    // French
    'FR': 'fr', 'MC': 'fr', 'SN': 'fr', 'CI': 'fr', 'ML': 'fr',
    'BF': 'fr', 'NE': 'fr', 'TD': 'fr', 'MG': 'fr', 'CM': 'fr',
    'CD': 'fr', 'CG': 'fr', 'CF': 'fr', 'GA': 'fr', 'DJ': 'fr', 'KM': 'fr', 'RE': 'fr', 'YT': 'fr',
    'NC': 'fr', 'PF': 'fr', 'WF': 'fr', 'VU': 'fr', 'BI': 'fr', 'RW': 'fr', 'SC': 'fr',
    'MU': 'fr', 'HT': 'fr', 'GP': 'fr', 'MQ': 'fr', 'GF': 'fr', 'BL': 'fr', 'MF': 'fr', 'PM': 'fr',
    // Polish
    'PL': 'pl',
    // Spanish
    'ES': 'es', 'MX': 'es', 'AR': 'es', 'CO': 'es', 'PE': 'es', 'VE': 'es', 'CL': 'es',
    'EC': 'es', 'GT': 'es', 'CU': 'es', 'BO': 'es', 'DO': 'es', 'HN': 'es', 'PY': 'es',
    'SV': 'es', 'NI': 'es', 'CR': 'es', 'PA': 'es', 'UY': 'es', 'PR': 'es',
    // Italian
    'IT': 'it', 'SM': 'it', 'VA': 'it',
    // Portuguese
    'PT': 'pt', 'BR': 'pt', 'AO': 'pt', 'MZ': 'pt', 'GW': 'pt', 'CV': 'pt', 'ST': 'pt',
    'TL': 'pt', 'MO': 'pt',
    // Dutch
    'NL': 'nl', 'BE': 'nl', 'SR': 'nl', 'AW': 'nl', 'CW': 'nl', 'SX': 'nl', 'BQ': 'nl',
    // Finnish
    'FI': 'fi',
  };

  // Initialize the translation service
  Future<void> initialize() async {
    if (_isInitialized) return;

    // Load saved language preference
    await _loadSavedLanguage();

    // Load translations
    await _loadTranslations();

    // Verify current language is available, fallback to English if not
    await _verifyAndSetLanguage();

    _isInitialized = true;
  }

  // Load saved language from SharedPreferences
  Future<void> _loadSavedLanguage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedLanguage = prefs.getString('language');

      if (savedLanguage != null && supportedLanguages.contains(savedLanguage)) {
        _currentLanguage = savedLanguage;
      } else {
        // Auto-detect language based on device locale
        await _autoDetectLanguage();
      }
    } catch (e) {
      print('❌ Error loading saved language: $e');
      _currentLanguage = 'en'; // Fallback to English
    }
  }

  // Auto-detect language based on device locale
  Future<void> _autoDetectLanguage() async {
    try {
      // Get device locale
      final locale = Platform.localeName;
      final countryCode = locale.split('_').last.toUpperCase();

      // Map country code to language
      if (countryToLanguageMap.containsKey(countryCode)) {
        _currentLanguage = countryToLanguageMap[countryCode]!;
      } else {
        // Try to detect from language code
        final languageCode = locale.split('_').first.toLowerCase();
        if (supportedLanguages.contains(languageCode)) {
          _currentLanguage = languageCode;
        } else {
          _currentLanguage = 'en'; // Fallback to English
        }
      }

      // Save detected language
      await _saveLanguage(_currentLanguage);
    } catch (e) {
      print('❌ Error auto-detecting language: $e');
      _currentLanguage = 'en';
    }
  }

  // Verify current language is available in translations, fallback to English if not
  Future<void> _verifyAndSetLanguage() async {
    // Check if current language exists in loaded translations
    if (!_translations.containsKey(_currentLanguage)) {
      print('⚠️ Language $_currentLanguage not available, falling back to English');
      _currentLanguage = 'en';
      await _saveLanguage(_currentLanguage);
    }

    // Double check English exists (it should always be there)
    if (!_translations.containsKey('en')) {
      print('❌ English translations not available, using fallback');
      await _loadFallbackTranslations();
    }

    print('✅ Using language: $_currentLanguage');
  }

  // Load translations from API
  Future<void> _loadTranslations() async {
    try {
      final response = await http.get(
        Uri.parse(ApiConstants.language),
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        try {
          final responseData = json.decode(response.body);

          // Handle both Map<String, dynamic> and Map<dynamic, dynamic>
          if (responseData is Map) {
            // Convert the response to the expected format
            final Map<String, dynamic> stringMap = Map<String, dynamic>.from(responseData);

            _translations = <String, Map<String, String>>{};

            for (final entry in stringMap.entries) {
              if (entry.value is Map) {
                // Convert inner Map to Map<String, String>
                final innerMap = Map<String, dynamic>.from(entry.value as Map);
                _translations[entry.key] = Map<String, String>.from(innerMap.map((k, v) => MapEntry(k.toString(), v.toString())));
              } else {
                // If value is not a Map, it might be an error message
                if (entry.key == 'error' || entry.key == 'message') {
                  print('⚠️ Translation API returned: ${entry.key} = ${entry.value}');
                }
              }
            }

            // If no translations were loaded, use fallback
            if (_translations.isEmpty) {
              print('⚠️ No translations loaded from API, using fallback');
              await _loadFallbackTranslations();
            } else {
              print('✅ Loaded translations for ${_translations.keys.length} languages');
            }
          } else {
            print('❌ Translation API returned non-Map response: ${responseData.runtimeType}');
            await _loadFallbackTranslations();
          }
        } catch (e) {
          print('❌ Error parsing translations JSON: $e');
          await _loadFallbackTranslations();
        }
      } else {
        print('❌ Failed to load translations: ${response.statusCode}');
        await _loadFallbackTranslations();
      }
    } catch (e) {
      print('❌ Error loading translations: $e');
      await _loadFallbackTranslations();
    }
  }

  // Load fallback translations (English only)
  Future<void> _loadFallbackTranslations() async {
    _translations = {
      'en': {
        // Intro and branding
        'intro': 'Welcome to ',
        'intro_read_more': 'Read more',

        // Authentication
        'btn_login': 'Login',
        'btn_register': 'Register',
        'btn_forgot': 'Forgot Password?',
        'username': 'Username',
        'password': 'Password',
        'email': 'Email',
        'confirm_password': 'Confirm Password',
        'change_password': 'Change Password',
        'field_required': 'This field is required',
        'invalid_email': 'Please enter a valid email address',
        'password_too_short': 'Password must be at least 8 characters',
        'passwords_do_not_match': 'Passwords do not match',
        'connection_error': 'Connection error. Please check your internet and try again.',

        // Navigation
        'home': 'Home',
        'profile': 'Profile',
        'settings': 'Settings',
        'notifications': 'Notifications',
        'chat': 'Chat',
        'groups': 'Groups',

        // Common actions
        'edit': 'Edit',
        'delete': 'Delete',
        'cancel': 'Cancel',
        'save': 'Save',
        'done': 'Done',
        'ok': 'OK',
        'yes': 'Yes',
        'no': 'No',
        'back': 'Back',
        'create_post': 'Create Post',
        'edit_post': 'Edit Post',
        'nickname': 'Nickname',
        'save_changes': 'Save Changes',
        'apply': 'Apply',
        'next': 'Next',
        'close': 'Close',
        'search': 'Search',

        // Status
        'error': 'Error',
        'success': 'Success',
        'loading': 'Loading...',
        'no_data': 'No data available',
        'try_again': 'Try again',

        // Registration
        'create_account': 'Create Account',
        'already_have_account': 'Already have an account? ',
        'sign_in': 'Sign In',
        'date_of_birth': 'Date of Birth',
        'select_date_of_birth': 'Select Date of Birth',
        'select_date_birth_desc': 'Please select your date of birth. You must be at least 15 years old.',
        'full_name': 'Full Name',
        'full_name_desc': 'Please enter your full name as it appears on official documents.',
        'first_name': 'First Name',
        'last_name': 'Last Name',
        'middle_name': 'Middle Name (Optional)',
        'enter_first_name': 'Enter your first name',
        'enter_middle_name': 'Enter your middle name (optional)',
        'enter_last_name': 'Enter your last name',
        'email_address': 'Email Address',
        'email_desc': 'Please enter your email address. We\'ll send a verification code to confirm it\'s yours.',
        'enter_email': 'Enter your email address',
        'email_sent': 'Email Sent',
        'verification_code_sent_to': 'Verification code sent to ',
        'email_verification': 'Email Verification',
        'enter_code_sent_to': 'Enter the verification code sent to ',
        'verification_code': 'Verification Code',
        'enter_verification_code': 'Enter verification code',
        'resend_code': 'Resend Code',
        'username_label': 'Username',
        'username_desc': 'Choose a unique username for your account.',
        'choose_username': 'Choose a username',
        'password_label': 'Password',
        'password_desc': 'Create a strong password for your account security.',
        'create_password': 'Create a password',
        'reenter_password': 'Re-enter your password',
        'continue': 'Continue',
        'go_back': 'Go Back',
        'based_on_selection': 'Based on your selection, you are',
        'years_old': 'years old',
        'password_requirements': 'Password Requirements',
        'at_least_8_chars': 'At least 8 characters.',
        'alpha_char_used': 'Alphabetic character used.',
        'numeric_char_used': 'Numeric character used.',
        'special_char_used': 'Special character used.',
        'passwords_match': 'Passwords match.',

        // Posts
        'no_posts_display': 'No posts to display',
        'pull_to_refresh': 'Pull down to refresh',
        'refreshed_found_posts': 'Refreshed! Found {count} posts',
        'refreshed_no_posts': 'Refreshed! No new posts found',
        'please_login_to_refresh': 'Please log in to refresh posts',
        'failed_to_refresh': 'Failed to refresh',

        // Settings
        'language': 'Language',
        'select_language': 'Select Language',
        'theme': 'Theme',
        'general': 'General',

        // Update dialog
        'update_available': 'Update Available',
        'auto_updates_only_android': 'Auto-updates are only available on Android',
        'no_updates_available': 'No updates available',
        'error_checking_updates': 'Error checking for updates',

        // Test buttons (should be removed in production)
        'test_snackbar': 'Test SnackBar',
        'test_notification': 'Test Notification',
        'test_refresh': 'Test Refresh',

        // WebSocket/Broadcast
        'broadcast': 'Broadcast',

        // Generic messages
        'must_be_15_years_old': 'You must be at least 15 years old',
        'registration_successful': 'Registration successful! Please check your email to verify your account.',
        'registration_failed': 'Registration failed. Please try again.',
        'login_successful': 'Login successful',
        'welcome_to_skybyn': 'Welcome to Skybyn',
        'login_failed_check_credentials': 'Login failed. Please check your credentials and try again.',

        // QR Code
        'scan_qr_code': 'Scan QR Code',
        'camera_error': 'Camera Error',
        'camera_init_failed': 'Camera initialization failed',
        'qr_code_invalid_length': 'QR code must be exactly 10 characters long',
        'error_communicating_server': 'Error communicating with server',
        'scanning': 'Scanning..',
        'valid': 'VALID',
        'scan_again': 'Scan Again',

        // Posts
        'what_on_mind': 'What is on your mind?',
        'post': 'Post',
        'no_posts_yet': 'No posts yet',

        // Settings - Avatar & Wallpaper
        'update_avatar': 'Update Avatar',
        'update_wallpaper': 'Update Wallpaper',
        'take_photo': 'Take Photo',
        'choose_from_gallery': 'Choose from Gallery',

        // Settings - Password
        'password_current': 'Password (Current)',
        'password_reset_sent': 'Password reset instructions have been sent to your email',

        // Settings - PIN
        'pin_code': 'PIN code',
        'pin_code_current': 'PIN code (Current)',
        'pin_code_new': 'PIN code (New)',
        'confirm_pin_code': 'Confirm PIN code',
        'save_pin_code': 'Save PIN code',
        'pin_update_success': 'PIN updated successfully',
        'pin_update_error': 'Error updating PIN',
        'pin_confirmation_mismatch': 'New PIN and confirmation do not match',

        // Settings - Security Questions
        'security_questions': 'Security Questions',
        'security_question_1': 'Security Question 1',
        'security_question_2': 'Security Question 2',
        'answer_1': 'Answer 1',
        'answer_2': 'Answer 2',
        'save_security_questions': 'Save Security Questions',
        'security_questions_update_success': 'Security questions updated successfully',
        'security_questions_update_error': 'Error updating security questions',

        // Settings - Preferences
        'preferences': 'Preferences',
        'enable_notifications': 'Enable Notifications',
        'private_profile': 'Private Profile',
        'biometric_lock': 'Biometric Lock',

        // Settings - Appearance
        'appearance': 'Appearance',
        'theme_mode': 'Theme Mode',
        'choose_theme_mode': 'Choose Theme Mode',
        'system_recommended': 'System (Recommended)',
        'automatically_follow_device_theme': 'Automatically follow device theme',
        'light': 'Light',
        'always_use_light_theme': 'Always use light theme',
        'dark': 'Dark',
        'always_use_dark_theme': 'Always use dark theme',

        // Profile
        'profile_update_success': 'Profile updated successfully',
        'profile_update_error': 'Error updating profile',

        // Error messages
        'server_error_occurred': 'Server error occurred',
        'invalid_verification_code': 'Invalid verification code. Please try again.',
        'verification_code_too_short': 'Verification code must be at least 4 characters',
      }
    };
  }

  // Get translation for a key
  String translate(String key) {
    if (!_isInitialized) {
      return key; // Return key if not initialized
    }

    final languageTranslations = _translations[_currentLanguage];
    if (languageTranslations != null && languageTranslations.containsKey(key)) {
      return languageTranslations[key]!;
    }

    // Fallback to English
    final englishTranslations = _translations['en'];
    if (englishTranslations != null && englishTranslations.containsKey(key)) {
      return englishTranslations[key]!;
    }

    // Return key if no translation found
    return key;
  }

  // Get current language
  String get currentLanguage => _currentLanguage;

  // Get all supported languages
  List<String> get supportedLanguagesList => supportedLanguages;

  // Get language name for display
  String getLanguageName(String languageCode) {
    return languageNames[languageCode] ?? languageCode.toUpperCase();
  }

  // Set language
  Future<void> setLanguage(String languageCode) async {
    if (supportedLanguages.contains(languageCode)) {
      _currentLanguage = languageCode;
      await _saveLanguage(languageCode);
      notifyListeners(); // Notify listeners that the language has changed
    }
  }

  // Save language to SharedPreferences
  Future<void> _saveLanguage(String languageCode) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('language', languageCode);
    } catch (e) {
      print('❌ Error saving language: $e');
    }
  }

  // Check if translations are loaded
  bool get isInitialized => _isInitialized;

  // Reload translations from API
  Future<void> reloadTranslations() async {
    _isInitialized = false;
    await initialize();
  }
}

// Global instance
final TranslationService translationService = TranslationService();
