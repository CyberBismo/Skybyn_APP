import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../config/constants.dart';

class TranslationService {
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
    'BF': 'fr', 'NE': 'fr', 'TD': 'fr', 'MG': 'fr', 'CM': 'fr', 'CD': 'fr', 'CG': 'fr',
    'CF': 'fr', 'GA': 'fr', 'DJ': 'fr', 'KM': 'fr', 'RE': 'fr', 'YT': 'fr',
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
      print('Error loading saved language: $e');
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
      print('Error auto-detecting language: $e');
      _currentLanguage = 'en';
    }
  }

  // Load translations from API
  Future<void> _loadTranslations() async {
    try {
      final response = await http.get(
        Uri.parse('${ApiConstants.language}?lang=en'),
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = json.decode(response.body);
        _translations = Map<String, Map<String, String>>.from(
          data.map((key, value) => MapEntry(
                key,
                Map<String, String>.from(value as Map<String, dynamic>),
              )),
        );
      } else {
        print('Failed to load translations: ${response.statusCode}');
        await _loadFallbackTranslations();
      }
    } catch (e) {
      print('Error loading translations: $e');
      await _loadFallbackTranslations();
    }
  }

  // Load fallback translations (English only)
  Future<void> _loadFallbackTranslations() async {
    _translations = {
      'en': {
        'intro': 'Welcome to ',
        'btn_login': 'Login',
        'btn_register': 'Register',
        'username': 'Username',
        'password': 'Password',
        'home': 'Home',
        'profile': 'Profile',
        'settings': 'Settings',
        'notifications': 'Notifications',
        'chat': 'Chat',
        'groups': 'Groups',
        'edit': 'Edit',
        'delete': 'Delete',
        'cancel': 'Cancel',
        'save': 'Save',
        'done': 'Done',
        'error': 'Error',
        'success': 'Success',
        'loading': 'Loading...',
        'no_data': 'No data available',
        'try_again': 'Try again',
        'language': 'Language',
        'select_language': 'Select Language',
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
    }
  }

  // Save language to SharedPreferences
  Future<void> _saveLanguage(String languageCode) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('language', languageCode);
    } catch (e) {
      print('Error saving language: $e');
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
