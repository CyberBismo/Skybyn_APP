import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';
import '../config/constants.dart';
import 'auth_service.dart';

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

    // Load fallback translations first so they're always available
    await _loadFallbackTranslations();
    notifyListeners(); // Notify listeners immediately with fallback translations

    // Load saved language preference
    await _loadSavedLanguage();

    // Load translations from cache or API
    await _loadTranslations();

    // Verify current language is available, fallback to English if not
    await _verifyAndSetLanguage();

    _isInitialized = true;
    notifyListeners(); // Notify listeners that initialization is complete
  }

  // Load saved language from SharedPreferences or API
  Future<void> _loadSavedLanguage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedLanguage = prefs.getString('language');

      if (savedLanguage != null && supportedLanguages.contains(savedLanguage)) {
        _currentLanguage = savedLanguage;
        // Try to fetch from API in background to sync
        _syncLanguageFromAPI();
      } else {
        // Try to fetch from API first
        final apiLanguage = await _fetchLanguageFromAPI();
        if (apiLanguage != null && supportedLanguages.contains(apiLanguage)) {
          _currentLanguage = apiLanguage;
          await _saveLanguage(_currentLanguage);
        } else {
          // Auto-detect language based on device locale
          await _autoDetectLanguage();
        }
      }
    } catch (e) {
      _currentLanguage = 'en'; // Fallback to English
    }
  }

  /// Check if an exception is a transient network error that should be retried
  bool _isTransientError(dynamic error) {
    if (error is SocketException) return true;
    if (error is HandshakeException) return true;
    if (error is TimeoutException) return true;
    if (error is HttpException) {
      final message = error.message.toLowerCase();
      return message.contains('connection') || 
             message.contains('timeout') ||
             message.contains('reset');
    }
    return false;
  }

  /// Retry an HTTP request with exponential backoff
  Future<http.Response> _retryHttpRequest(
    Future<http.Response> Function() request, {
    int maxRetries = 2,
    Duration initialDelay = const Duration(milliseconds: 500),
  }) async {
    int attempt = 0;
    Duration delay = initialDelay;
    
    while (attempt < maxRetries) {
      try {
        final response = await request();
        if (response.statusCode < 500) {
          return response;
        }
        if (response.statusCode >= 500) {
          throw HttpException('Server error: ${response.statusCode}');
        }
        return response;
      } catch (e) {
        attempt++;
        if (!_isTransientError(e) || attempt >= maxRetries) {
          rethrow;
        }
        await Future.delayed(delay);
        delay = Duration(milliseconds: (delay.inMilliseconds * 2).clamp(500, 4000));
      }
    }
    throw Exception('Retry logic error');
  }

  // Fetch language preference from API (user profile)
  Future<String?> _fetchLanguageFromAPI() async {
    try {
      final authService = AuthService();
      final userId = await authService.getStoredUserId();
      
      if (userId == null) {
        return null;
      }

      final response = await _retryHttpRequest(
        () => http.post(
          Uri.parse(ApiConstants.profile),
          body: {'userID': userId},
          headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        ).timeout(const Duration(seconds: 5)),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['responseCode'] == '1' && data['language'] != null) {
          final language = data['language'].toString();
          if (supportedLanguages.contains(language)) {
            return language;
          }
        }
      }
    } catch (e) {
      if (e is HandshakeException) {
        // Silently fail for SSL issues
      } else {
      }
    }
    return null;
  }

  // Fetch language from API in background (non-blocking)
  void _syncLanguageFromAPI() {
    Future.delayed(const Duration(milliseconds: 100), () async {
      try {
        final apiLanguage = await _fetchLanguageFromAPI();
        if (apiLanguage != null && 
            supportedLanguages.contains(apiLanguage) && 
            apiLanguage != _currentLanguage) {
          _currentLanguage = apiLanguage;
          await _saveLanguage(_currentLanguage);
          notifyListeners();
        }
      } catch (e) {
        // Silently fail - we already have a language
      }
    });
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
      _currentLanguage = 'en';
    }
  }

  // Verify current language is available in translations, fallback to English if not
  Future<void> _verifyAndSetLanguage() async {
    // Check if current language exists in loaded translations
    if (!_translations.containsKey(_currentLanguage)) {
      _currentLanguage = 'en';
      await _saveLanguage(_currentLanguage);
    }

    // Double check English exists (it should always be there)
    if (!_translations.containsKey('en')) {
      await _loadFallbackTranslations();
    }
  }

  // Load translations from API or cache
  Future<void> _loadTranslations() async {
    // Try to load from cache first
    final cachedTranslations = await _loadTranslationsFromCache();
    if (cachedTranslations.isNotEmpty) {
      _translations = cachedTranslations;
      notifyListeners(); // Notify listeners that cached translations are loaded
      
      // Refresh translations in background
      _refreshTranslationsInBackground();
      return;
    }

    // If no cache, fetch from API
    await _fetchTranslationsFromAPI();
  }

  Future<void> _fetchTranslationsFromAPI() async {
    try {
      final response = await _retryHttpRequest(
        () => http.get(
          Uri.parse(ApiConstants.language),
          headers: {'Content-Type': 'application/json'},
        ).timeout(const Duration(seconds: 10)),
        maxRetries: 2,
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
                }
              }
            }

            // If no translations were loaded, use fallback
            if (_translations.isEmpty) {
              await _loadFallbackTranslations();
            } else {
              // Save to cache
              await _saveTranslationsToCache(_translations);
            }
            notifyListeners(); // Notify listeners that translations have been loaded
          } else {
            await _loadFallbackTranslations();
            notifyListeners(); // Notify listeners that fallback translations are loaded
          }
        } catch (e) {
          await _loadFallbackTranslations();
          notifyListeners(); // Notify listeners that fallback translations are loaded
        }
      } else {
        await _loadFallbackTranslations();
        notifyListeners(); // Notify listeners that fallback translations are loaded
      }
    } catch (e) {
      // Silently fall back to cached/fallback translations
      if (e is HandshakeException) {
      } else {
      }
      await _loadFallbackTranslations();
      notifyListeners(); // Notify listeners that fallback translations are loaded
    }
  }

  Future<void> _refreshTranslationsInBackground() async {
    // Refresh in background without blocking
    Future.delayed(const Duration(milliseconds: 100), () async {
      try {
        await _fetchTranslationsFromAPI();
        notifyListeners(); // Notify listeners that translations have been updated
      } catch (e) {
        // Silently fail - we already have cached data
      }
    });
  }

  static const String _cacheKey = 'cached_translations';
  static const String _cacheTimestampKey = 'cached_translations_timestamp';

  Future<void> _saveTranslationsToCache(Map<String, Map<String, String>> translations) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final translationsJson = <String, dynamic>{};
      for (final entry in translations.entries) {
        translationsJson[entry.key] = entry.value;
      }
      await prefs.setString(_cacheKey, jsonEncode(translationsJson));
      await prefs.setInt(_cacheTimestampKey, DateTime.now().millisecondsSinceEpoch);
    } catch (e) {
    }
  }

  Future<Map<String, Map<String, String>>> _loadTranslationsFromCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      final translationsJson = prefs.getString(_cacheKey);
      if (translationsJson == null) return {};

      final Map<String, dynamic> decoded = jsonDecode(translationsJson);
      final Map<String, Map<String, String>> result = {};
      
      for (final entry in decoded.entries) {
        if (entry.value is Map) {
          final innerMap = Map<String, dynamic>.from(entry.value as Map);
          result[entry.key] = Map<String, String>.from(innerMap.map((k, v) => MapEntry(k.toString(), v.toString())));
        }
      }
      
      return result;
    } catch (e) {
      return {};
    }
  }

  /// Clear translation cache
  Future<void> clearCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_cacheKey);
      await prefs.remove(_cacheTimestampKey);
    } catch (e) {
    }
  }

  // Load fallback translations (English only)
  Future<void> _loadFallbackTranslations() async {
    _translations = {
        'en': {
        "intro": "Welcome to ",
        "intro_read_more": "Click to read more",
        "intro_short": "Be safe online",
        "intro_long": "Skybyn does not share or sell your information to any parties. Your information is encrypted and stored safely for only you to administrate.",
        "btn_login": "Login",
        "btn_register": "Register",
        "btn_forgot": "Forgot password?",
        "btn_login_with_username": "Login with username",
        "username": "Username",
        "qr_login_text": "Scan the QR code using the Skybyn app to login.",
        "email": "Email",
        "password": "Password",
        "remember_me": "Remember me",
        "qr_login": "Login using app",
        "forgot_header": "Forgot your password?",
        "enter_username": "Enter your username",
        "request_pw_reset": "Request password reset",
        "go_back": "Go back",
        "language": "Language",
        "language_name": "English",
        "your_information": "Your information:",
        "terms_and_conditions": "Terms and Conditions",
        "new_post": "New post",
        "notifications": "Notifications",
        "read_all": "Read all",
        "delete_all": "Delete all",
        "beta_feedback": "BETA Feedback",
        "help_improve_skybyn": "Help us improve Skybyn!",
        "feedback_description": "Share your thoughts, report bugs, or suggest new features. Your feedback helps us make Skybyn better for everyone.",
        "enter_feedback_placeholder": "Enter your feedback here...",
        "please_enter_feedback": "Please enter your feedback",
        "user_not_authenticated": "User not authenticated",
        "failed_to_submit_feedback": "Failed to submit feedback",
        "error_submitting_feedback": "Error submitting feedback",
        "feedback_submitted_success": "Feedback submitted successfully! Thank you for your input.",
        "submit_feedback": "Submit Feedback",
        "what_to_include_feedback": "What to include in your feedback:",
        "bug_reports_info": "Bug reports: Describe what happened and steps to reproduce",
        "feature_requests_info": "Feature requests: Explain what you'd like to see",
        "general_feedback_info": "General feedback: Share your thoughts and suggestions",
        "unable_to_open_discord": "Unable to open Discord. Please try again.",
        "discord": "Discord",
        "discord_server": "Discord Server",
        "go_to_server": "Go to server",
        "home": "Home",
        "profile": "Profile",
        "settings": "Settings",
        "shortcuts": "Shortcuts",
        "sign_up": "Sign up",
        "enter_dob_to_start": "Enter your date of birth to get started",
        "your_full_name": "Your full name",
        "first_name": "First name",
        "middle_name": "Middle name",
        "last_name": "Last name",
        "chat": "Chat",
        "actions": "Actions",
        "unfriend": "Unfriend",
        "block": "Block",
        "cancel": "Cancel",
        "accept": "Accept",
        "ignore": "Ignore",
        "unblock": "Unblock",
        "add_friend": "Add Friend",
        "report": "Report",
        "groups": "Groups",
        "edit": "Edit",
        "delete": "Delete",
        "unknown_user": "Unknown User",
        "general": "General",
        "security": "Security",
        "ip_history": "IP History",
        "visibility": "Visibility",
        "account": "Account",
        "name": "Name",
        "pin_code": "PIN code",
        "no_pin_set": "No PIN set",
        "change_avatar": "Change avatar",
        "code_expired": "This code has expired",
        "enter_reset_code": "Enter your reset code",
        "set_new_password": "Set a new password",
        "enter_code_here": "Enter it here..",
        "new_password": "New password",
        "confirm_new_password": "Confirm new password",
        "done": "Done",
        "back": "Back",
        "select_language": "Select Language",
        "create_post": "Create Post",
        "edit_post": "Edit Post",
        "nickname": "Nickname",
        "save_changes": "Save Changes",
        "confirm_password": "Confirm Password",
        "change_password": "Change Password",
        "field_required": "This field is required",
        "password_too_short": "Password must be at least 8 characters",
        "passwords_do_not_match": "Passwords do not match",
        "invalid_email": "Please enter a valid email address",
        "connection_error": "Connection error. Please check your internet and try again.",
        "error": "Error",
        "success": "Success",
        "loading": "Loading...",
        "save": "Save",
        "apply": "Apply",
        "ok": "OK",
        "yes": "Yes",
        "no": "No",
        "next": "Next",
        "previous": "Previous",
        "open": "Open",
        "refresh": "Refresh",
        "filter": "Filter",
        "sort": "Sort",
        "search": "Search",
        "search_results": "Search results",
        "warning": "Warning",
        "info": "Info",
        "confirm": "Confirm",
        "retry": "Retry",
        "try_again": "Try again",
        "no_data": "No data available",
        "no_results_found": "No results found",
        "no_internet": "No internet connection",
        "server_error": "Server error",
        "unknown_error": "Unknown error",
        "create_account": "Create Account",
        "already_have_account": "Already have an account? ",
        "dont_have_account": "Don't have an account? ",
        "sign_out": "Sign out",
        "date_of_birth": "Date of Birth",
        "select_date_of_birth": "Select Date of Birth",
        "select_date_birth_desc": "Please select your date of birth. You must be at least 15 years old.",
        "full_name": "Full Name",
        "full_name_desc": "Please enter your full name as it appears on official documents.",
        "middle_name_text": "Middle Name (Optional)",
        "enter_first_name": "Enter your first name",
        "enter_middle_name": "Enter your middle name (optional)",
        "enter_last_name": "Enter your last name",
        "email_address": "Email Address",
        "email_desc": "Please enter your email address. We'll send a verification code to confirm it's yours.",
        "enter_email": "Enter your email address",
        "email_sent": "Email Sent",
        "verification_code_sent_to": "Verification code sent to ",
        "email_verification": "Email Verification",
        "enter_code_sent_to": "Enter the verification code sent to ",
        "verification_code": "Verification Code",
        "enter_verification_code": "Enter verification code",
        "resend_code": "Resend Code",
        "username_label": "Username",
        "username_desc": "Choose a unique username for your account.",
        "choose_username": "Choose a username",
        "password_label": "Password",
        "password_desc": "Create a strong password for your account security.",
        "create_password": "Create a password",
        "reenter_password": "Re-enter your password",
        "continue": "Continue",
        "go_back_text": "Go Back",
        "based_on_selection": "Based on your selection, you are",
        "years_old": "years old",
        "at_least_8_chars": "At least 8 characters.",
        "alpha_char_used": "Alphabetic character used.",
        "numeric_char_used": "Numeric character used.",
        "special_char_used": "Special character used.",
        "passwords_match": "Passwords match.",
        "password_requirements": "Password Requirements",
        "no_posts_display": "No posts to display",
        "pull_to_refresh": "Pull down to refresh",
        "refreshed_found_posts": "Refreshed! Found {count} posts",
        "refreshed_no_posts": "Refreshed! No new posts found",
        "please_login_to_refresh": "Please log in to refresh posts",
        "failed_to_refresh": "Failed to refresh",
        "theme": "Theme",
        "update_available": "Update Available",
        "auto_updates_only_android": "Auto-updates are only available on Android",
        "check_for_updates": "Check for updates",
        "checking_for_updates": "Checking for updates...",
        "no_updates_available": "No updates available",
        "error_checking_updates": "Error checking for updates",
        "install_permission_required": "Install Permission Required",
        "install_permission_denied_message": "This permission has been permanently denied. Please enable \"Install unknown apps\" for Skybyn in your device settings.",
        "permission_not_granted": "Permission not granted",
        "download_url_not_available": "Download URL not available. Cannot install update.",
        "update_failed": "Update Failed",
        "failed_to_install_update": "Failed to install update",
        "permission_denied_cannot_check_updates": "Permission denied. Cannot check for updates.",
        "update_dialog_already_open": "Update dialog is already open.",
        "select_date": "Select Date",
        "new_version_available": "A new version of Skybyn is available!",
        "installing_update": "Installing...",
        "test_snackbar": "Test SnackBar",
        "test_notification": "Test Notification",
        "test_refresh": "Test Refresh",
        "broadcast": "Broadcast",
        "must_be_15_years_old": "You must be at least 15 years old",
        "registration_successful": "Registration successful! Please check your email to verify your account.",
        "registration_failed": "Registration failed. Please try again.",
        "login_successful": "Login successful",
        "welcome_to_skybyn": "Welcome to Skybyn",
        "login_failed_check_credentials": "Login failed. Please check your credentials and try again.",
        "scan_qr_code": "Scan QR Code",
        "camera_error": "Camera Error",
        "camera_init_failed": "Camera initialization failed",
        "qr_code_invalid_length": "QR code must be exactly 10 characters long",
        "error_communicating_server": "Error communicating with server",
        "scanning": "Scanning..",
        "skybyn_qr_detected": "Skybyn QR detected",
        "valid": "VALID",
        "scan_again": "Scan Again",
        "what_on_mind": "What is on your mind?",
        "update_avatar": "Update Avatar",
        "update_wallpaper": "Update Wallpaper",
        "take_photo": "Take Photo",
        "choose_from_gallery": "Choose from Gallery",
        "crop_image": "Crop Image",
        "password_current": "Password (Current)",
        "pin_code_current": "PIN code (Current)",
        "pin_code_new": "PIN code (New)",
        "confirm_pin_code": "Confirm PIN code",
        "save_pin_code": "Save PIN code",
        "security_questions": "Security Questions",
        "security_question_1": "Security Question 1",
        "security_question_2": "Security Question 2",
        "answer_1": "Answer 1",
        "answer_2": "Answer 2",
        "save_security_questions": "Save Security Questions",
        "about": "About",
        "about_description": "Skybyn is a social networking platform that connects people from around the world. Share your moments, connect with friends, and discover new communities.",
        "app_version": "App version",
        "preferences": "Preferences",
        "enable_notifications": "Enable Notifications",
        "private_profile": "Private Profile",
        "biometric_lock": "Biometric Lock",
        "notification_sound": "Notification Sound",
        "sound_effect": "Sound Effect",
        "custom_sound": "Custom Sound",
        "no_custom_sound_selected": "No custom sound selected",
        "remove_custom_sound": "Remove Custom Sound",
        "select_sound_effect": "Select Sound Effect",
        "tap_to_change": "Tap to change",
        "custom_sound_set": "Custom sound set",
        "error_selecting_sound_file": "Error selecting sound file",
        "default_sound": "Default",
        "appearance": "Appearance",
        "theme_mode": "Theme Mode",
        "choose_theme_mode": "Choose Theme Mode",
        "system_recommended": "System (Recommended)",
        "automatically_follow_device_theme": "Automatically follow device theme",
        "light": "Light",
        "always_use_light_theme": "Always use light theme",
        "dark": "Dark",
        "always_use_dark_theme": "Always use dark theme",
        "post": "Post",
        "server_error_occurred": "Server error occurred",
        "invalid_verification_code": "Invalid verification code. Please try again.",
        "verification_code_too_short": "Verification code must be at least 4 characters",
        "pin_update_success": "PIN updated successfully",
        "pin_update_error": "Error updating PIN",
        "profile_update_success": "Profile updated successfully",
        "profile_update_error": "Error updating profile",
        "error_checking_permissions": "Error checking permissions",
        "open_settings": "Open Settings",
        "security_questions_update_success": "Security questions updated successfully",
        "security_questions_update_error": "Error updating security questions",
        "pin_confirmation_mismatch": "New PIN and confirmation do not match",
        "pins_do_not_match": "PINs do not match",
        "no_posts_yet": "No posts yet",
        "post_created_but_could_not_load_details": "Post created but could not load details",
        "share_app": "Share App",
        "delete_post": "Delete Post",
        "confirm_delete_post_message": "Are you sure you want to delete this post?",
        "report_post": "Report Post",
        "confirm_report_post_message": "Are you sure you want to report this post?",
        "post_reported_successfully": "Post reported successfully",
        "post_link_copied_to_clipboard": "Post link copied to clipboard!",
        "comment_posted_but_could_not_load_details": "Comment posted but could not load details",
        "failed_to_post_comment": "Failed to post comment",
        "failed_to_delete_comment": "Failed to delete comment",
        "failed_to_delete_post": "Failed to delete post",
        "expand": "Expand",
        "all_comments": "All Comments",
        "add_comment": "Add a comment...",
        "add_comment_placeholder": "Add a comment...",
        "minutes_ago": "minutes ago",
        "hours_ago": "hours ago",
        "days_ago": "days ago",
        "call_error": "Call error",
        "enter_valid_email": "Please enter a valid e-mail address",
        "enter_here": "Enter here",
        "create_new_code": "Create new code",
        "enter_text": "Enter text",
        "page_name_placeholder": "Name of page",
        "page_desc_placeholder": "Who is this page for",
        "set_password": "Set Password",
        "set_pin_code": "Set PIN code",
        "market_name": "Market name",
        "market_description": "Description",
        "enter_login_code": "Enter login code",
        "enter_confirmation_code": "Enter the confirmation code",
        "share": "Share",
        "view_profile": "View profile",
        "close": "Close",
        "new_year_in": "New Year In",
        "happy_new_year": "Happy New Year",
        "my_pet": "My Pet",
        "my_car": "My Car",
        "logout": "Logout",
        "qr_scanner": "QR Scanner",
        "coming_soon": "Coming Soon",
        "search_friends": "Search friends...",
        "no_friends_found": "No friends found",
        "find_friends_in_area": "Find friends in the area",
        "find_friends_description": "Discover and connect with users nearby using your location",
        "find_friends_button": "Find Friends",
        "nearby_users": "Nearby Users",
        "no_nearby_users": "No users found nearby.",
        "enter_username_or_code": "Enter username or referral code",
        "add_friend_by_username": "Add Friend by Username",
        "user_not_found": "User not found",
        "failed_to_add_friend": "Failed to add friend. User may have a private profile.",
        "error_occurred": "An error occurred. Please try again.",
        "send_friend_request": "Send Friend Request",
        "friend_request_sent": "Friend request sent successfully",
        "friends_only": "Friends Only",
        "public": "Public",
        "pages": "Pages",
        "music": "Music",
        "games": "Games",
        "events": "Events",
        "market": "Market",
        "markets": "Markets",
        "browse_groups": "Browse Groups",
        "browse_pages": "Browse Pages",
        "browse_music": "Browse Music",
        "browse_games": "Browse Games",
        "browse_events": "Browse Events",
        "browse_market": "Browse Market",
        "search_placeholder": "Search...",
        "users": "Users",
        "posts": "Posts",
        "friends": "Friends",
        "friend_code": "Friend code",
        "generate_code": "Generate code",
        "how_to_use": "How to use?",
        "friend_code_help": "Share this code to instantly find you. When they sign up, you will become friends and earn 10 points.",
        "points": "points",
        "search_chats": "Search chats...",
        "type_your_message": "Type your message...",
        "welcome_to": "Welcome to",
        "show_more": "Show more",
        "show_more_text": "Skybyn does not share or sell your information to any parties. Your information is encrypted and stored safely for only you to administrate.",
        "write_a_comment": "Write a comment",
        "profile_private": "This profile is private",
        "profile_not_exist": "This profile does not exist",
        "search_in_messages": "Search in messages",
        "pin_required": "PIN required",
        "password_required": "Password required",
        "enter": "ENTER",
        "message_placeholder": "Message..",
        "join_group": "Join Group",
        "private": "Private",
        "locked": "Locked",
        "create_new_group": "Create New Group",
        "what_are_groups_for": "What are groups for",
        "groups_benefit_meeting_ground": "Meeting ground for people",
        "groups_benefit_share_many": "Share with many at once",
        "groups_benefit_plan_party": "Plan a party",
        "groups_benefit_discussions": "Make discussions easier",
        "groups_benefit_own_rules": "Make your own rules",
        "group_name_placeholder": "Name of group",
        "group_desc_placeholder": "Who is this group for",
        "please_select_image": "Please select an image file.",
        "no_new_notifications": "No new notifications",
        "noti_from_system": "System update",
        "noti_sent_friend_request": "wants to be your friend",
        "noti_friend_accepted": "You're now friends with",
        "noti_commented": "New comment from",
        "noti_you_referred": "You referred a new user",
        "no_messages": "No messages yet",
        "email_required": "Email is required",
        "email_invalid_format": "Please enter a valid email address",
        "verification_code_required": "Please enter the verification code",
        "password_must_contain_number": "Password must contain at least one number",
        "confirm_password_required": "Please confirm your password",
        "email_already_verified": "Email already verified",
        "verification_code_sent_successfully": "Verification code sent successfully",
        "profile_privacy": "Profile Privacy",
        "open_profile": "Open Profile",
        "set_each_setting_manually": "Set each setting manually",
        "microphone_permission_required": "Microphone Permission Required",
        "microphone_permission_message": "Skybyn needs microphone access to make voice and video calls. Please enable it in settings.",
        "camera_permission_required": "Camera Permission Required",
        "camera_permission_message": "Skybyn needs camera access to make video calls. Please enable it in settings.",
        "current_version": "Current",
        "latest_version": "Latest",
        "whats_new": "What's new",
        "later": "Later",
        "please_log_in_to_find_friends": "Please log in to find friends",
        "unable_to_get_location": "Unable to get your location. Please enable location services.",
        "found_users_nearby": "Found {count} user{plural} nearby",
        "error_finding_friends": "Error finding friends",
        "no_pin": "No PIN",
        "pin_must_be_digits": "PIN must be {digits} digits",
        "security_question_required": "Security question {number} and answer are required",
        "error_clearing_cache": "Error clearing cache",
        "update_check_disabled_debug": "Update check disabled in debug mode",
        "update_check_in_progress": "Update check already in progress",
        "you_are_using_latest_version": "You are using the latest version",
        "permission_required_title": "{permission} Required",
        "permission_permanently_denied_message": "This permission has been permanently denied. Please enable it in your device settings to use this feature.",
        "permission_granted": "Permission granted!",
        "error_requesting_permission": "Error requesting permission",
        "feature_coming_soon": "{feature} feature coming soon",
        "just_now": "Just now",
        "system": "System",
        "unknown": "Unknown",
        "month_jan": "Jan",
        "month_feb": "Feb",
        "month_mar": "Mar",
        "month_apr": "Apr",
        "month_may": "May",
        "month_jun": "Jun",
        "month_jul": "Jul",
        "month_aug": "Aug",
        "month_sep": "Sep",
        "month_oct": "Oct",
        "month_nov": "Nov",
        "month_dec": "Dec",
        "close_shortcuts_panel": "Close shortcuts panel",
        "close_friends_list": "Close friends list",
        "failed_to_send_message": "Failed to send message",
        "failed_to_create_post": "Failed to create post",
        "failed_to_update_post": "Failed to update post",
        "about_skybyn": "Skybyn is a social networking platform that connects people from around the world. Share your moments, connect with friends, and discover new communities.",
        "display_name": "Display Name",
        "change_cover": "Change Cover",
        "discard_changes": "Discard Changes",
        "profile_updated": "Profile updated",
        "profile_update_failed": "Profile update failed",
        "title": "Title",
        "bio": "Bio",
        "clear_translations_cache": "Clear cached translation data",
        "clear_posts_cache": "Clear cached posts and timeline data",
        "clear_friends_cache": "Clear cached friends list data",
        "cache_cleared": "Cache cleared",
        "cache_cleared_successfully": "Cache cleared successfully",
        "confirm_clear_cache": "Are you sure you want to clear this cache?",
        "confirm_clear_all_cache": "Are you sure you want to clear all cache?",
        "reset_password": "Reset Password",
        "invalid_credentials": "Invalid credentials",
        "account_created": "Account created",
        "login_failed": "Login failed",
        "username_taken": "Username is already taken",
        "email_already_exists": "Email already exists",
        "edit_profile": "Edit Profile",
        "location": "Location",
        "location_sharing": "Location Sharing",
        "share_location": "Share Location",
        "location_share_mode": "Location Share Mode",
        "location_sharing_disabled": "Location sharing disabled",
        "share_last_active_location": "Share last active location",
        "share_live_location": "Share live location",
        "location_sharing_mode": "Location Sharing Mode",
        "dont_share_location": "Don't share location",
        "share_last_known_location": "Share last known location",
        "share_live_location_updates": "Share live location updates",
        "location_private_mode": "Private Mode",
        "hide_location_from_friends": "Hide your location from friends on the map",
        "no_locations_available": "No locations available",
        "live_location": "Live location",
        "last_active_location": "Last active location",
        "last_active": "Last Active",
        "you": "You",
        "off": "Off",
        "map": "Map",
        "website": "Website",
        "phone": "Phone",
        "birthday": "Birthday",
        "gender": "Gender",
        "post_created": "Post created",
        "post_updated": "Post updated",
        "post_deleted": "Post deleted",
        "post_failed": "Post failed",
        "post_update_failed": "Post update failed",
        "post_delete_failed": "Post delete failed",
        "confirm_delete_post": "Delete Post",
        "post_deleted_successfully": "Post deleted successfully",
        "share_post": "Share Post",
        "like_post": "Like Post",
        "unlike_post": "Unlike Post",
        "comment_post": "Comment on Post",
        "view_comments": "View Comments",
        "hide_comments": "Hide Comments",
        "post_content": "Post Content",
        "add_photo": "Add Photo",
        "add_video": "Add Video",
        "add_location": "Add Location",
        "edit_comment": "Edit Comment",
        "delete_comment": "Delete Comment",
        "reply_to_comment": "Reply to Comment",
        "comment_added": "Comment added",
        "comment_updated": "Comment updated",
        "comment_deleted": "Comment deleted",
        "comment_failed": "Comment failed",
        "comment_update_failed": "Comment update failed",
        "comment_delete_failed": "Comment delete failed",
        "confirm_delete_comment": "Delete Comment",
        "write_comment": "Write a comment",
        "comment_placeholder": "Write a comment...",
        "friend_request": "Friend Request",
        "friend_requests": "Friend Requests",
        "pending_requests": "Pending Requests",
        "sent_requests": "Sent Requests",
        "mutual_friends": "Mutual Friends",
        "friend_added": "Friend added",
        "friend_removed": "Friend removed",
        "friend_request_accepted": "Friend request accepted",
        "friend_request_declined": "Friend request declined",
        "user_blocked": "User blocked",
        "user_unblocked": "User unblocked",
        "user_reported": "User reported",
        "clear_chat_history": "Clear Chat History",
        "clear_chat_history_title": "Clear Chat History",
        "clear_chat_history_message": "Are you sure you want to clear all messages in this chat? This action cannot be undone.",
        "clear_chat_history_button": "Clear",
        "chat_history_cleared": "Chat history cleared",
        "error_clearing_chat": "Error clearing chat",
        "block_user_confirmation": "Are you sure you want to block {name}? You will not receive messages from this user.",
        "block_user_button": "Block",
        "error_blocking_user": "Error blocking user",
        "unfriend_title": "Unfriend",
        "unfriend_confirmation": "Are you sure you want to unfriend {name}?",
        "unfriend_button": "Unfriend",
        "user_unfriended": "User unfriended",
        "error_unfriending_user": "Error unfriending user",
        "decline": "Decline",
        "privacy": "Privacy",
        "help": "Help",
        "support": "Support",
        "terms_of_service": "Terms of Service",
        "privacy_policy": "Privacy Policy",
        "last_updated": "Last Updated",
        "developer": "Developer",
        "contact_us": "Contact Us",
        "feedback": "Feedback",
        "rate_app": "Rate App",
        "logout_all_devices": "Logout All Devices",
        "delete_account": "Delete Account",
        "confirm_delete_account": "Confirm Delete Account",
        "account_deleted": "Account deleted",
        "update_required": "Update Required",
        "update_optional": "Update Optional",
        "update_now": "Update Now",
        "update_downloading": "Downloading update",
        "update_installing": "Installing update",
        "update_completed": "Update completed",
        "update_cancelled": "Update cancelled",
        "update_size": "Update Size",
        "download_progress": "Download Progress",
        "install_progress": "Install Progress",
        "field_too_short": "Field is too short",
        "field_too_long": "Field is too long",
        "invalid_format": "Invalid format",
        "password_too_weak": "Password is too weak",
        "username_too_short": "Username is too short",
        "username_too_long": "Username is too long",
        "username_invalid": "Invalid username",
        "email_invalid": "Invalid email",
        "phone_invalid": "Invalid phone number",
        "url_invalid": "Invalid URL",
        "date_invalid": "Invalid date",
        "time_invalid": "Invalid time",
        "number_invalid": "Invalid number",
        "value_too_small": "Value is too small",
        "value_too_large": "Value is too large",
        "away": "Away",
        "busy": "Busy",
        "invisible": "Invisible",
        "available": "Available",
        "unavailable": "Unavailable",
        "typing": "Typing",
        "last_seen": "Last seen",
        "active_now": "Active now",
        "hidden": "Hidden",
        "no_one": "No one",
        "only_me": "Only me",
        },
        'no': {
          "language_name": "Norsk",
          "home": "Hjem",
          "profile": "Profil",
          "settings": "Innstillinger",
        },
        'dk': {
          "language_name": "Dansk",
          "home": "Hjem",
          "profile": "Profil",
          "settings": "Indstillinger",
        }
    };
  }

  // Get translation for a key
  String translate(String key) {
    // Always try to get translation, even if not initialized
    // This ensures we have fallback translations available immediately
    
    // First try current language
    final languageTranslations = _translations[_currentLanguage];
    if (languageTranslations != null && languageTranslations.containsKey(key)) {
      return languageTranslations[key]!;
    }

    // Fallback to English
    final englishTranslations = _translations['en'];
    if (englishTranslations != null && englishTranslations.containsKey(key)) {
      return englishTranslations[key]!;
    }

    // If not initialized yet, try to get from fallback translations
    if (!_isInitialized) {
      // Fallback translations should always be loaded first, but if not, return a human-readable key
      return _humanizeKey(key);
    }

    // Last resort: return humanized key instead of raw key
    return _humanizeKey(key);
  }

  // Convert translation key to human-readable text as last resort
  String _humanizeKey(String key) {
    // Replace underscores with spaces and capitalize first letter of each word
    return key
        .split('_')
        .map((word) => word.isEmpty 
            ? '' 
            : word[0].toUpperCase() + word.substring(1).toLowerCase())
        .join(' ');
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
      
      // Sync to API in background
      _saveLanguageToAPI(languageCode);
      
      notifyListeners(); // Notify listeners that the language has changed
    }
  }

  // Save language preference to API
  Future<void> _saveLanguageToAPI(String languageCode) async {
    try {
      final authService = AuthService();
      final userId = await authService.getStoredUserId();
      
      if (userId == null) {
        return;
      }

      final response = await http.post(
        Uri.parse(ApiConstants.profile),
        body: {
          'userID': userId,
          'language': languageCode,
        },
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      ).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['responseCode'] == '1') {
        } else {
        }
      } else {
      }
    } catch (e) {
      // Don't throw - language is already saved locally
    }
  }

  // Save language to SharedPreferences
  Future<void> _saveLanguage(String languageCode) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('language', languageCode);
    } catch (e) {
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

class TranslationKeys {
  // Common UI elements
  static const String home = 'home';
  static const String profile = 'profile';
  static const String settings = 'settings';
  static const String shortcuts = 'shortcuts';
  static const String discord = 'discord';
  static const String discordServer = 'discord_server';
  static const String goToServer = 'go_to_server';
  static const String notifications = 'notifications';
  static const String noNewNotifications = 'no_new_notifications';
  static const String notiFromSystem = 'noti_from_system';
  static const String notiSentFriendRequest = 'noti_sent_friend_request';
  static const String notiFriendAccepted = 'noti_friend_accepted';
  static const String notiCommented = 'noti_commented';
  static const String notiYouReferred = 'noti_you_referred';
  static const String readAll = 'read_all';
  static const String deleteAll = 'delete_all';
  static const String chat = 'chat';
  static const String groups = 'groups';
  static const String joinGroup = 'join_group';
  static const String createNewGroup = 'create_new_group';
  static const String whatAreGroupsFor = 'what_are_groups_for';
  static const String groupsBenefitMeetingGround = 'groups_benefit_meeting_ground';
  static const String groupsBenefitShareMany = 'groups_benefit_share_many';
  static const String groupsBenefitPlanParty = 'groups_benefit_plan_party';
  static const String groupsBenefitDiscussions = 'groups_benefit_discussions';
  static const String groupsBenefitOwnRules = 'groups_benefit_own_rules';
  static const String groupNamePlaceholder = 'group_name_placeholder';
  static const String groupDescPlaceholder = 'group_desc_placeholder';
  static const String pleaseSelectImage = 'please_select_image';
  static const String edit = 'edit';
  static const String delete = 'delete';
  static const String cancel = 'cancel';
  static const String save = 'save';
  static const String done = 'done';
  static const String nickname = 'nickname';
  static const String pinCode = 'pin_code';
  static const String pinCodeCurrent = 'pin_code_current';
  static const String pinCodeNew = 'pin_code_new';
  static const String confirmPinCode = 'confirm_pin_code';
  static const String savePinCode = 'save_pin_code';
  static const String newPassword = 'new_password';
  static const String confirmNewPassword = 'confirm_new_password';
  static const String ok = 'ok';
  static const String yes = 'yes';
  static const String no = 'no';
  static const String off = 'off';
  static const String you = 'you';
  static const String back = 'back';
  static const String next = 'next';
  static const String previous = 'previous';
  static const String close = 'close';
  static const String open = 'open';
  static const String search = 'search';
  static const String searchResults = 'search_results';
  static const String filter = 'filter';
  static const String sort = 'sort';
  static const String refresh = 'refresh';
  static const String loading = 'loading';
  static const String error = 'error';
  static const String success = 'success';
  static const String warning = 'warning';
  static const String info = 'info';
  static const String confirm = 'confirm';
  static const String retry = 'retry';
  static const String tryAgain = 'try_again';
  static const String noData = 'no_data';
  static const String noResultsFound = 'no_results_found';
  static const String noInternet = 'no_internet';
  static const String connectionError = 'connection_error';
  static const String serverError = 'server_error';
  static const String unknownError = 'unknown_error';
  static const String typeMessage = 'type_message';
  static const String typeYourMessage = 'type_your_message';
  static const String enter = 'enter';
  static const String messagePlaceholder = 'message_placeholder';
  static const String locked = 'locked';

  // Intro and Branding
  static const String intro = 'intro';
  static const String introReadMore = 'intro_read_more';
  static const String introShort = 'intro_short';
  static const String introLong = 'intro_long';

  // Authentication
  static const String login = 'btn_login';
  static const String register = 'btn_register';
  static const String logout = 'logout';
  static const String forgotPassword = 'btn_forgot';
  static const String resetPassword = 'reset_password';
  static const String changePassword = 'change_password';
  static const String requestPwReset = 'request_pw_reset';
  static const String username = 'username';
  static const String password = 'password';
  static const String email = 'email';
  static const String signIn = 'sign_in';
  static const String passwordCurrent = 'password_current';
  static const String passwordResetSent = 'password_reset_sent';
  static const String loginSuccessful = 'login_successful';
  static const String welcomeToSkybyn = 'welcome_to_skybyn';
  static const String loginFailedCheckCredentials = 'login_failed_check_credentials';
  static const String confirmPassword = 'confirm_password';
  static const String rememberMe = 'remember_me';
  static const String signUp = 'sign_up';
  static const String signOut = 'sign_out';
  static const String createAccount = 'create_account';
  static const String alreadyHaveAccount = 'already_have_account';
  static const String dontHaveAccount = 'dont_have_account';
  static const String enterUsername = 'enter_username';
  static const String enterPassword = 'enter_password';
  static const String enterEmail = 'enter_email';
  static const String invalidCredentials = 'invalid_credentials';
  static const String accountCreated = 'account_created';
  static const String loginFailed = 'login_failed';
  static const String registrationFailed = 'registration_failed';
  static const String registrationSuccessful = 'registration_successful';
  static const String passwordTooShort = 'password_too_short';
  static const String passwordsDoNotMatch = 'passwords_do_not_match';
  static const String invalidEmail = 'invalid_email';
  static const String usernameTaken = 'username_taken';
  static const String emailAlreadyExists = 'email_already_exists';
  static const String serverErrorOccurred = 'server_error_occurred';
  static const String invalidVerificationCode = 'invalid_verification_code';
  static const String verificationCodeTooShort = 'verification_code_too_short';
  static const String pinUpdateSuccess = 'pin_update_success';
  static const String pinUpdateError = 'pin_update_error';
  static const String profileUpdateSuccess = 'profile_update_success';
  static const String profileUpdateError = 'profile_update_error';
  static const String securityQuestionsUpdateSuccess = 'security_questions_update_success';
  static const String securityQuestionsUpdateError = 'security_questions_update_error';
  static const String pinConfirmationMismatch = 'pin_confirmation_mismatch';

  static const String verificationCodeSentTo = 'verification_code_sent_to';
  static const String enterCodeSentTo = 'enter_code_sent_to';
  static const String verificationCode = 'verification_code';
  static const String enterVerificationCode = 'enter_verification_code';
  static const String resendCode = 'resend_code';
  static const String emailVerification = 'email_verification';
  static const String emailSent = 'email_sent';
  static const String mustBe15YearsOld = 'must_be_15_years_old';


  // User Profile
  static const String firstName = 'first_name';
  static const String lastName = 'last_name';
  static const String middleName = 'middle_name';
  static const String fullName = 'your_full_name';
  static const String displayName = 'display_name';
  static const String title = 'title';
  static const String bio = 'bio';
  static const String dateOfBirth = 'date_of_birth';
  static const String selectDateBirthDesc = 'select_date_birth_desc';
  static const String basedOnSelection = 'based_on_selection';
  static const String yearsOld = 'years_old';
  static const String fullNameDesc = 'full_name_desc';
  static const String enterFirstName = 'enter_first_name';
  static const String middleNameOptional = 'middle_name_optional';
  static const String enterMiddleName = 'enter_middle_name';
  static const String enterLastName = 'enter_last_name';
  static const String emailAddress = 'email_address';
  static const String emailDesc = 'email_desc';
  static const String usernameDesc = 'username_desc';
  static const String passwordDesc = 'password_desc';
  static const String passwordRequirements = 'password_requirements';
  static const String atLeast8Chars = 'at_least_8_chars';
  static const String alphaCharUsed = 'alpha_char_used';
  static const String numericCharUsed = 'numeric_char_used';
  static const String specialCharUsed = 'special_char_used';
  static const String onlyEnglishCharsAllowed = 'only_english_chars_allowed';
  static const String passwordsMatch = 'passwords_match';
  static const String profilePrivacy = 'profile_privacy';
  static const String profilePrivacyDesc = 'profile_privacy_desc';
  static const String openProfile = 'open_profile';
  static const String appearInSearch = 'appear_in_search';
  static const String profileIsVisible = 'profile_is_visible';
  static const String anyoneCanMessage = 'anyone_can_message';
  static const String appearForNewUsers = 'appear_for_new_users';
  static const String notAppearInSearch = 'not_appear_in_search';
  static const String profileIsInvisible = 'profile_is_invisible';
  static const String onlyFriendsCanMessage = 'only_friends_can_message';
  static const String visibility = 'visibility';
  static const String setManually = 'set_manually';
  static const String continueButton = 'continue';
  static const String goBack = 'go_back';
  static const String ipHistory = 'ip_history';
  static const String pinsDoNotMatch = 'pins_do_not_match';
  static const String location = 'location';
  static const String locationSharing = 'location_sharing';
  static const String shareLocation = 'share_location';
  static const String locationShareMode = 'location_share_mode';
  static const String locationSharingDisabled = 'location_sharing_disabled';
  static const String shareLastActiveLocation = 'share_last_active_location';
  static const String shareLiveLocation = 'share_live_location';
  static const String lastActive = 'last_active';
  static const String locationSharingMode = 'location_sharing_mode';
  static const String dontShareLocation = 'dont_share_location';
  static const String shareLastKnownLocation = 'share_last_known_location';
  static const String shareLiveLocationUpdates = 'share_live_location_updates';
  static const String locationPrivateMode = 'location_private_mode';
  static const String hideLocationFromFriends = 'hide_location_from_friends';
  static const String noLocationsAvailable = 'no_locations_available';
  static const String liveLocation = 'live_location';
  static const String lastActiveLocation = 'last_active_location';
  static const String map = 'map';
  static const String website = 'website';
  static const String phone = 'phone';
  static const String birthday = 'birthday';
  static const String gender = 'gender';
  static const String editProfile = 'edit_profile';
  static const String changeAvatar = 'change_avatar';
  static const String changeCover = 'change_cover';
  static const String saveChanges = 'save_changes';
  static const String discardChanges = 'discard_changes';
  static const String profileUpdated = 'profile_updated';
  static const String profileUpdateFailed = 'profile_update_failed';
  
  // Status
  static const String active = 'active';
  static const String inactive = 'inactive';



  // Posts
  static const String newPost = 'new_post';
  static const String createPost = 'create_post';
  static const String editPost = 'edit_post';
  static const String deletePost = 'delete_post';
  static const String sharePost = 'share_post';
  static const String likePost = 'like_post';
  static const String unlikePost = 'unlike_post';
  static const String commentPost = 'comment_post';
  static const String viewComments = 'view_comments';
  static const String hideComments = 'hide_comments';
  static const String postContent = 'post_content';
  static const String whatOnMind = 'what_on_mind';
  static const String addPhoto = 'add_photo';
  static const String addVideo = 'add_video';
  static const String addLocation = 'add_location';
  static const String post = 'post';
  static const String noPostsYet = 'no_posts_yet';
  static const String postCreated = 'post_created';
  static const String postUpdated = 'post_updated';
  static const String postDeleted = 'post_deleted';
  static const String postFailed = 'post_failed';
  static const String postUpdateFailed = 'post_update_failed';
  static const String postDeleteFailed = 'post_delete_failed';
  static const String confirmDeletePost = 'confirm_delete_post';
  static const String postDeletedSuccessfully = 'post_deleted_successfully';
  static const String confirmDeletePostMessage = 'confirm_delete_post_message';
  static const String reportPost = 'report_post';
  static const String confirmReportPostMessage = 'confirm_report_post_message';
  static const String postReportedSuccessfully = 'post_reported_successfully';
  static const String postLinkCopiedToClipboard = 'post_link_copied_to_clipboard';
  static const String commentPostedButCouldNotLoadDetails = 'comment_posted_but_could_not_load_details';
  static const String failedToPostComment = 'failed_to_post_comment';
  static const String failedToDeleteComment = 'failed_to_delete_comment';
  static const String failedToDeletePost = 'failed_to_delete_post';
  static const String allComments = 'all_comments';
  static const String addCommentPlaceholder = 'add_comment';

  // Comments
  static const String addComment = 'add_comment';
  static const String editComment = 'edit_comment';
  static const String deleteComment = 'delete_comment';
  static const String replyToComment = 'reply_to_comment';
  static const String commentAdded = 'comment_added';
  static const String commentUpdated = 'comment_updated';
  static const String commentDeleted = 'comment_deleted';
  static const String commentFailed = 'comment_failed';
  static const String commentUpdateFailed = 'comment_update_failed';
  static const String commentDeleteFailed = 'comment_delete_failed';
  static const String confirmDeleteComment = 'confirm_delete_comment';
  static const String writeComment = 'write_comment';
  static const String commentPlaceholder = 'comment_placeholder';

  // Friends
  static const String friends = 'friends';
  static const String addFriend = 'add_friend';
  static const String removeFriend = 'unfriend';
  static const String acceptFriend = 'accept';
  static const String declineFriend = 'decline';
  static const String blockUser = 'block';
  static const String unblockUser = 'unblock';
  static const String reportUser = 'report';
  static const String friendRequest = 'friend_request';
  static const String friendRequests = 'friend_requests';
  static const String pendingRequests = 'pending_requests';
  static const String sentRequests = 'sent_requests';
  static const String mutualFriends = 'mutual_friends';
  static const String friendAdded = 'friend_added';
  static const String friendRemoved = 'friend_removed';
  static const String friendRequestSent = 'friend_request_sent';
  static const String friendRequestAccepted = 'friend_request_accepted';
  static const String friendRequestDeclined = 'friend_request_declined';
  static const String enterUsernameOrCode = 'enter_username_or_code';
  static const String addFriendByUsername = 'add_friend_by_username';
  static const String userNotFound = 'user_not_found';
  static const String failedToAddFriend = 'failed_to_add_friend';
  static const String errorOccurred = 'error_occurred';
  static const String sendFriendRequest = 'send_friend_request';
  static const String userBlocked = 'user_blocked';
  static const String userUnblocked = 'user_unblocked';
  static const String userReported = 'user_reported';
  
  // Chat Actions
  static const String clearChatHistory = 'clear_chat_history';
  static const String clearChatHistoryTitle = 'clear_chat_history_title';
  static const String clearChatHistoryMessage = 'clear_chat_history_message';
  static const String clearChatHistoryButton = 'clear_chat_history_button';
  static const String chatHistoryCleared = 'chat_history_cleared';
  static const String errorClearingChat = 'error_clearing_chat';
  static const String blockUserConfirmation = 'block_user_confirmation';
  static const String blockUserButton = 'block_user_button';
  static const String errorBlockingUser = 'error_blocking_user';
  static const String unfriendTitle = 'unfriend_title';
  static const String unfriendConfirmation = 'unfriend_confirmation';
  static const String unfriendButton = 'unfriend_button';
  static const String userUnfriended = 'user_unfriended';
  static const String errorUnfriendingUser = 'error_unfriending_user';

  // Settings
  static const String general = 'general';
  static const String privacy = 'privacy';
  static const String security = 'security';
  static const String language = 'language';
  static const String theme = 'theme';
  static const String account = 'account';
  static const String preferences = 'preferences';
  static const String appearance = 'appearance';
  static const String themeMode = 'theme_mode';
  static const String chooseThemeMode = 'choose_theme_mode';
  static const String systemRecommended = 'system_recommended';
  static const String automaticallyFollowDeviceTheme = 'automatically_follow_device_theme';
  static const String light = 'light';
  static const String alwaysUseLightTheme = 'always_use_light_theme';
  static const String dark = 'dark';
  static const String alwaysUseDarkTheme = 'always_use_dark_theme';
  static const String enableNotifications = 'enable_notifications';
  static const String privateProfile = 'private_profile';
  static const String biometricLock = 'biometric_lock';
  static const String notificationSound = 'notification_sound';
  static const String soundEffect = 'sound_effect';
  static const String customSound = 'custom_sound';
  static const String noCustomSoundSelected = 'no_custom_sound_selected';
  static const String removeCustomSound = 'remove_custom_sound';
  static const String selectSoundEffect = 'select_sound_effect';
  static const String tapToChange = 'tap_to_change';
  static const String customSoundSet = 'custom_sound_set';
  static const String errorSelectingSoundFile = 'error_selecting_sound_file';
  static const String defaultSound = 'default_sound';
  static const String updateAvatar = 'update_avatar';
  static const String updateWallpaper = 'update_wallpaper';
  static const String takePhoto = 'take_photo';
  static const String chooseFromGallery = 'choose_from_gallery';
  static const String securityQuestions = 'security_questions';
  static const String securityQuestion1 = 'security_question_1';
  static const String securityQuestion2 = 'security_question_2';
  static const String answer1 = 'answer_1';
  static const String answer2 = 'answer_2';
  static const String saveSecurityQuestions = 'save_security_questions';
  static const String about = 'about';
  static const String aboutDescription = 'about_description';
  static const String help = 'help';
  static const String support = 'support';
  static const String termsOfService = 'terms_of_service';
  static const String privacyPolicy = 'privacy_policy';
  static const String appVersion = 'app_version';
  static const String lastUpdated = 'last_updated';
  static const String developer = 'developer';
  static const String contactUs = 'contact_us';
  static const String feedback = 'feedback';
  static const String rateApp = 'rate_app';
  static const String betaFeedback = 'beta_feedback';
  static const String helpImproveSkybyn = 'help_improve_skybyn';
  static const String feedbackDescription = 'feedback_description';
  static const String enterFeedbackPlaceholder = 'enter_feedback_placeholder';
  static const String pleaseEnterFeedback = 'please_enter_feedback';
  static const String userNotAuthenticated = 'user_not_authenticated';
  static const String failedToSubmitFeedback = 'failed_to_submit_feedback';
  static const String errorSubmittingFeedback = 'error_submitting_feedback';
  static const String feedbackSubmittedSuccess = 'feedback_submitted_success';
  static const String submitFeedback = 'submit_feedback';
  static const String whatToIncludeFeedback = 'what_to_include_feedback';
  static const String bugReportsInfo = 'bug_reports_info';
  static const String featureRequestsInfo = 'feature_requests_info';
  static const String generalFeedbackInfo = 'general_feedback_info';
  static const String unableToOpenDiscord = 'unable_to_open_discord';
  static const String shareApp = 'share_app';
  static const String logoutAllDevices = 'logout_all_devices';
  static const String deleteAccount = 'delete_account';
  static const String confirmDeleteAccount = 'confirm_delete_account';
  static const String accountDeleted = 'account_deleted';
  static const String callError = 'call_error';
  static const String postCreatedButCouldNotLoadDetails = 'post_created_but_could_not_load_details';
  static const String qrScanner = 'qr_scanner';
  static const String createNewCode = 'create_new_code';
  static const String adminPanel = 'admin_panel';
  static const String userManagement = 'user_management';
  static const String moderationTools = 'moderation_tools';
  static const String systemSettings = 'system_settings';
  static const String analyticsAndReports = 'analytics_and_reports';
  static const String comingSoon = 'coming_soon';
  static const String report = 'report';
  static const String searchFriends = 'search_friends';
  static const String noFriendsFound = 'no_friends_found';
  static const String findFriendsInArea = 'find_friends_in_area';
  static const String findFriendsDescription = 'find_friends_description';
  static const String findFriendsButton = 'find_friends_button';
  static const String nearbyUsers = 'nearby_users';
  static const String noNearbyUsers = 'no_nearby_users';
  static const String pleaseLogInToFindFriends = 'please_log_in_to_find_friends';
  static const String unableToGetLocation = 'unable_to_get_location';
  static const String foundUsersNearby = 'found_users_nearby';
  static const String errorFindingFriends = 'error_finding_friends';
  static const String noMessages = 'no_messages';
  static const String installPermissionRequired = 'install_permission_required';
  static const String installPermissionDeniedMessage = 'install_permission_denied_message';
  static const String permissionNotGranted = 'permission_not_granted';
  static const String downloadUrlNotAvailable = 'download_url_not_available';
  static const String updateFailed = 'update_failed';
  static const String failedToInstallUpdate = 'failed_to_install_update';
  static const String permissionDeniedCannotCheckUpdates = 'permission_denied_cannot_check_updates';
  static const String updateDialogAlreadyOpen = 'update_dialog_already_open';
  static const String selectDate = 'select_date';
  static const String newVersionAvailable = 'new_version_available';
  static const String installingUpdate = 'installing_update';
  
  // Cache Management
  static const String cache = 'cache';
  static const String clearCache = 'clear_cache';
  static const String clearAllCache = 'clear_all_cache';
  static const String clearTranslationsCache = 'clear_translations_cache';
  static const String clearPostsCache = 'clear_posts_cache';
  static const String clearFriendsCache = 'clear_friends_cache';
  static const String cacheCleared = 'cache_cleared';
  static const String cacheClearedSuccessfully = 'cache_cleared_successfully';
  static const String confirmClearCache = 'confirm_clear_cache';
  static const String confirmClearAllCache = 'confirm_clear_all_cache';

  // Language Settings
  static const String selectLanguage = 'select_language';
  static const String cropImage = 'crop_image';
  static const String languageChanged = 'language_changed';
  static const String languageChangeFailed = 'language_change_failed';
  static const String autoDetectLanguage = 'auto_detect_language';
  static const String languageDetection = 'language_detection';

  // Navigation
  static const String timeline = 'timeline';
  static const String feed = 'feed';
  static const String discover = 'discover';
  static const String explore = 'explore';
  static const String trending = 'trending';
  static const String popular = 'popular';
  static const String recent = 'recent';
  static const String following = 'following';
  static const String followers = 'followers';
  static const String messages = 'messages';
  static const String inbox = 'inbox';
  static const String sent = 'sent';
  static const String drafts = 'drafts';
  static const String archived = 'archived';
  static const String favorites = 'favorites';
  static const String bookmarks = 'bookmarks';
  static const String history = 'history';
  
  // Browsing & Market
  static const String pages = 'pages';
  static const String music = 'music';
  static const String games = 'games';
  static const String events = 'events';
  static const String market = 'market';
  static const String markets = 'markets';
  static const String browseGroups = 'browse_groups';
  static const String browsePages = 'browse_pages';
  static const String browseMusic = 'browse_music';
  static const String browseGames = 'browse_games';
  static const String browseEvents = 'browse_events';
  static const String browseMarket = 'browse_market';
  static const String points = 'points';
  static const String searchChats = 'search_chats';
  static const String pageNamePlaceholder = 'page_name_placeholder';
  static const String pageDescPlaceholder = 'page_desc_placeholder';
  static const String marketName = 'market_name';
  static const String marketDescription = 'market_description';

  // Actions
  static const String actions = 'actions';
  static const String more = 'more';
  static const String less = 'less';
  static const String showMore = 'show_more';
  static const String showLess = 'show_less';
  static const String expand = 'expand';
  static const String collapse = 'collapse';
  static const String select = 'select';
  static const String selectAll = 'select_all';
  static const String deselectAll = 'deselect_all';
  static const String clear = 'clear';
  static const String reset = 'reset';
  static const String apply = 'apply';
  static const String submit = 'submit';
  static const String send = 'send';
  static const String receive = 'receive';
  static const String download = 'download';
  static const String upload = 'upload';
  static const String share = 'share';
  static const String copy = 'copy';
  static const String paste = 'paste';
  static const String cut = 'cut';
  static const String undo = 'undo';
  static const String redo = 'redo';

  // Time and Date
  static const String now = 'now';
  static const String today = 'today';
  static const String yesterday = 'yesterday';
  static const String tomorrow = 'tomorrow';
  static const String thisWeek = 'this_week';
  static const String lastWeek = 'last_week';
  static const String thisMonth = 'this_month';
  static const String lastMonth = 'last_month';
  static const String thisYear = 'this_year';
  static const String lastYear = 'last_year';
  static const String ago = 'ago';
  static const String inAWhile = 'in_a_while';
  static const String justNow = 'just_now';
  static const String minutesAgo = 'minutes_ago';
  static const String hoursAgo = 'hours_ago';
  static const String daysAgo = 'days_ago';
  static const String weeksAgo = 'weeks_ago';
  static const String monthsAgo = 'months_ago';
  static const String yearsAgo = 'years_ago';
  static const String monthJan = 'month_jan';
  static const String monthFeb = 'month_feb';
  static const String monthMar = 'month_mar';
  static const String monthApr = 'month_apr';
  static const String monthMay = 'month_may';
  static const String monthJun = 'month_jun';
  static const String monthJul = 'month_jul';
  static const String monthAug = 'month_aug';
  static const String monthSep = 'month_sep';
  static const String monthOct = 'month_oct';
  static const String monthNov = 'month_nov';
  static const String monthDec = 'month_dec';

  // Permissions
  static const String permissionRequired = 'permission_required';
  static const String permissionDenied = 'permission_denied';
  static const String permissionGranted = 'permission_granted';
  static const String cameraPermission = 'camera_permission';
  static const String microphonePermission = 'microphone_permission';
  static const String storagePermission = 'storage_permission';
  static const String locationPermission = 'location_permission';
  static const String notificationPermission = 'notification_permission';
  static const String contactsPermission = 'contacts_permission';
  static const String grantPermission = 'grant_permission';
  static const String goToSettings = 'go_to_settings';
  static const String errorCheckingPermissions = 'error_checking_permissions';
  static const String openSettings = 'open_settings';
  static const String microphonePermissionRequired = 'microphone_permission_required';
  static const String microphonePermissionMessage = 'microphone_permission_message';
  static const String cameraPermissionRequired = 'camera_permission_required';
  static const String cameraPermissionMessage = 'camera_permission_message';
  static const String permissionRequiredTitle = 'permission_required_title';
  static const String permissionPermanentlyDeniedMessage = 'permission_permanently_denied_message';

  // QR Code
  static const String qrCode = 'qr_code';
  static const String scanQrCode = 'scan_qr_code';
  static const String generateQrCode = 'generate_qr_code';
  static const String qrCodeScanned = 'qr_code_scanned';
  static const String qrCodeGenerated = 'qr_code_generated';
  static const String invalidQrCode = 'invalid_qr_code';
  static const String qrCodeExpired = 'qr_code_expired';
  static const String qrCodeNotFound = 'qr_code_not_found';
  static const String cameraError = 'camera_error';
  static const String cameraInitFailed = 'camera_init_failed';
  static const String qrCodeInvalidLength = 'qr_code_invalid_length';
  static const String errorCommunicatingServer = 'error_communicating_server';
  static const String scanning = 'scanning';
  static const String valid = 'valid';
  static const String scanAgain = 'scan_again';
  static const String skybynQrDetected = 'skybyn_qr_detected';

  // Updates
  static const String updateAvailable = 'update_available';
  static const String updateRequired = 'update_required';
  static const String updateOptional = 'update_optional';
  static const String updateNow = 'update_now';
  static const String updateLater = 'update_later';
  static const String updateDownloading = 'update_downloading';
  static const String updateInstalling = 'update_installing';
  static const String updateCompleted = 'update_completed';
  static const String updateCancelled = 'update_cancelled';
  static const String install = 'install';
  static const String checkingForUpdates = 'checking_for_updates';
  static const String checkForUpdates = 'check_for_updates';
  static const String noUpdatesAvailable = 'no_updates_available';
  static const String errorCheckingUpdates = 'error_checking_updates';
  static const String updateSize = 'update_size';
  static const String downloadProgress = 'download_progress';
  static const String installProgress = 'install_progress';
  static const String autoUpdatesOnlyAndroid = 'auto_updates_only_android';
  static const String currentVersion = 'current_version';
  static const String latestVersion = 'latest_version';
  static const String whatsNew = 'whats_new';
  static const String later = 'later';
  static const String youAreUsingLatestVersion = 'you_are_using_latest_version';
  static const String updateCheckDisabledDebug = 'update_check_disabled_debug';
  static const String updateCheckInProgress = 'update_check_in_progress';

  // Validation
  static const String fieldRequired = 'field_required';
  static const String fieldTooShort = 'field_too_short';
  static const String noPostsDisplay = 'no_posts_display';
  static const String pullToRefresh = 'pull_to_refresh';
  static const String refreshedFoundPosts = 'refreshed_found_posts';
  static const String refreshedNoPosts = 'refreshed_no_posts';
  static const String pleaseLoginToRefresh = 'please_login_to_refresh';
  static const String failedToRefresh = 'failed_to_refresh';
  static const String testSnackbar = 'test_snackbar';
  static const String testNotification = 'test_notification';
  static const String testRefresh = 'test_refresh';
  static const String fieldTooLong = 'field_too_long';
  static const String invalidFormat = 'invalid_format';
  static const String passwordTooWeak = 'password_too_weak';
  static const String usernameTooShort = 'username_too_short';
  static const String usernameTooLong = 'username_too_long';
  static const String usernameInvalid = 'username_invalid';
  static const String emailInvalid = 'email_invalid';
  static const String phoneInvalid = 'phone_invalid';
  static const String urlInvalid = 'url_invalid';
  static const String dateInvalid = 'date_invalid';
  static const String timeInvalid = 'time_invalid';
  static const String numberInvalid = 'number_invalid';
  static const String valueTooSmall = 'value_too_small';
  static const String valueTooLarge = 'value_too_large';
  static const String noPin = 'no_pin';
  static const String pinMustBeDigits = 'pin_must_be_digits';
  static const String securityQuestionRequired = 'security_question_required';
  static const String errorClearingCache = 'error_clearing_cache';

  // Status Messages
  static const String online = 'online';
  static const String offline = 'offline';
  static const String away = 'away';
  static const String busy = 'busy';
  static const String invisible = 'invisible';
  static const String available = 'available';
  static const String unavailable = 'unavailable';
  static const String typing = 'typing';
  static const String lastSeen = 'last_seen';
  static const String activeNow = 'active_now';
  static const String activeToday = 'active_today';
  static const String activeThisWeek = 'active_this_week';
  static const String activeThisMonth = 'active_this_month';
  static const String neverActive = 'never_active';
  static const String newYearIn = 'new_year_in';
  static const String happyNewYear = 'happy_new_year';
  static const String myPet = 'my_pet';
  static const String myCar = 'my_car';

  // Privacy
  static const String public = 'public';
  static const String private = 'private';
  static const String friendsOnly = 'friends_only';
  static const String custom = 'custom';
  static const String visible = 'visible';
  static const String hidden = 'hidden';
  static const String everyone = 'everyone';
  static const String noOne = 'no_one';
  static const String onlyMe = 'only_me';
  static const String specificPeople = 'specific_people';
  static const String allFriends = 'all_friends';
  static const String closeFriends = 'close_friends';
  static const String family = 'family';
  static const String colleagues = 'colleagues';
  static const String acquaintances = 'acquaintances';

  // Content Types
  static const String text = 'text';
  static const String image = 'image';
  static const String video = 'video';
  static const String audio = 'audio';
  static const String file = 'file';
  static const String poll = 'poll';
  static const String event = 'event';
  static const String story = 'story';
  static const String live = 'live';
  static const String broadcast = 'broadcast';
  static const String stream = 'stream';
  static const String recording = 'recording';
}
