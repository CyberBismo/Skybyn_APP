# Skybyn Flutter Translation System

This document explains how to use the multi-language translation system in the Skybyn Flutter app.

## Overview

The translation system supports **12 languages**:
- English (en)
- Norwegian (no)
- Danish (dk)
- Swedish (se)
- German (de)
- French (fr)
- Polish (pl)
- Spanish (es)
- Italian (it)
- Portuguese (pt)
- Dutch (nl)
- Finnish (fi)

## Features

- **Automatic Language Detection**: Detects user's language based on device locale
- **Manual Language Selection**: Users can manually select their preferred language
- **Persistent Storage**: Language preference is saved and restored between app sessions
- **Fallback System**: Falls back to English if translation is not available
- **Real-time Updates**: Language changes are applied immediately

## Usage

### 1. Basic Text Translation

Use the `TranslatedText` widget for displaying translated text:

```dart
import '../widgets/translated_text.dart';
import '../utils/translation_keys.dart';

// Simple text translation
TranslatedText(
  TranslationKeys.welcome,
  style: TextStyle(fontSize: 18),
)

// With fallback text
TranslatedText(
  TranslationKeys.welcome,
  fallback: 'Welcome!',
  style: TextStyle(fontSize: 18),
)
```

### 2. String Extension

Use the `.tr` extension for quick translations:

```dart
import '../widgets/translated_text.dart';

// Using string extension
Text('welcome'.tr)

// Using translation keys
Text(TranslationKeys.welcome.tr)
```

### 3. Button Translation

Use the helper methods for translated buttons:

```dart
// Translated button
TranslatedWidgets.button(
  TranslationKeys.login,
  onPressed: () => _handleLogin(),
)

// Translated text button
TranslatedWidgets.textButton(
  TranslationKeys.cancel,
  onPressed: () => _handleCancel(),
)
```

### 4. Language Selection

Add a language selector to your settings:

```dart
import '../widgets/language_selector.dart';

// Full language selector
LanguageSelector(
  onLanguageChanged: (String languageCode) {
    // Language is automatically saved
    // Show confirmation message
  },
)

// Compact language selector for app bars
CompactLanguageSelector(
  onLanguageChanged: (String languageCode) {
    // Handle language change
  },
)
```

### 5. Programmatic Language Control

```dart
import '../services/translation_service.dart';

final translationService = TranslationService();

// Get current language
String currentLang = translationService.currentLanguage;

// Set language
await translationService.setLanguage('es');

// Get language name
String languageName = translationService.getLanguageName('es');

// Check if translations are loaded
bool isReady = translationService.isInitialized;
```

## Translation Keys

All translation keys are defined in `utils/translation_keys.dart`. Use these constants instead of hardcoded strings:

```dart
// Good
TranslatedText(TranslationKeys.login)

// Bad
TranslatedText('login')
```

## Adding New Translations

1. Add the new key to `utils/translation_keys.dart`:
```dart
class TranslationKeys {
  static const String newFeature = 'new_feature';
  // ... other keys
}
```

2. Add translations to the API endpoint `api/translations.php` for all supported languages.

3. Use the new key in your UI:
```dart
TranslatedText(TranslationKeys.newFeature)
```

## Language Detection

The system automatically detects the user's language based on:

1. **Device Locale**: Primary language from device settings
2. **Country Code**: Maps country codes to supported languages
3. **Saved Preference**: Previously selected language from SharedPreferences
4. **Fallback**: Defaults to English if detection fails

## API Integration

The translation system fetches translations from:
```
GET /api/translations.php?get=1
```

The API returns a JSON object with all translations:
```json
{
  "en": {
    "welcome": "Welcome",
    "login": "Login",
    ...
  },
  "es": {
    "welcome": "Bienvenido",
    "login": "Iniciar sesión",
    ...
  }
}
```

## Error Handling

The system includes robust error handling:

- **Network Errors**: Falls back to cached translations or English
- **Invalid Language Codes**: Defaults to English
- **Missing Translations**: Falls back to English version
- **API Failures**: Uses fallback translations

## Performance

- **Lazy Loading**: Translations are loaded only when needed
- **Caching**: Translations are cached in memory
- **Efficient Updates**: Only changed translations are updated
- **Minimal Overhead**: Translation lookup is O(1) operation

## Best Practices

1. **Always use TranslationKeys constants** instead of hardcoded strings
2. **Provide fallback text** for critical UI elements
3. **Test with different languages** to ensure UI layout works
4. **Use appropriate text styles** for different languages (some languages need more space)
5. **Consider cultural differences** in UI design and text length

## Example Implementation

Here's a complete example of a translated login screen:

```dart
import 'package:flutter/material.dart';
import '../widgets/translated_text.dart';
import '../utils/translation_keys.dart';

class LoginScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: TranslatedText(TranslationKeys.login),
      ),
      body: Column(
        children: [
          TranslatedText(
            TranslationKeys.welcome,
            style: TextStyle(fontSize: 24),
          ),
          TextField(
            decoration: InputDecoration(
              hintText: TranslationKeys.username.tr,
            ),
          ),
          ElevatedButton(
            onPressed: () {},
            child: TranslatedText(TranslationKeys.login),
          ),
        ],
      ),
    );
  }
}
```

This system provides a complete, production-ready translation solution for the Skybyn Flutter app.
