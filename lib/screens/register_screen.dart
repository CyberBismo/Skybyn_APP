import 'package:flutter/material.dart';
import 'dart:io';
import '../widgets/background_gradient.dart';
import '../services/auth_service.dart';
import '../widgets/wheel_date_picker.dart';
import '../services/translation_service.dart';
import 'home_screen.dart';


class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _firstNameController = TextEditingController();
  final _middleNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _verificationCodeController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  final _authService = AuthService();
  final _translationService = TranslationService();

  final _firstNameFocusNode = FocusNode();
  final _middleNameFocusNode = FocusNode();
  final _lastNameFocusNode = FocusNode();
  final _emailFocusNode = FocusNode();
  final _verificationCodeFocusNode = FocusNode();
  final _usernameFocusNode = FocusNode();
  final _passwordFocusNode = FocusNode();
  final _confirmPasswordFocusNode = FocusNode();

  DateTime? _selectedDate;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _isLoading = false;
  bool _verificationEmailSent = false;
  bool _emailAlreadyVerified = false;
  String? _expectedVerificationCode;
  String? _errorMessage;
  int _currentGroup = 0; // 0: date, 1: full name, 2: email, 3: email verification, 4: username, 5: password, 6: profile package
  
  // Profile package selection
  String? _selectedPackage; // 'op' = Open Profile, 'pp' = Private Profile, 'cp' = Custom
  bool _isPrivate = false; // For custom package
  bool _isVisible = true; // For custom package

  // Live password metrics
  double _passwordStrength = 0.0;
  bool _pwHasMinLen = false;
  bool _pwHasAlpha = false;
  bool _pwHasNum = false;
  bool _pwHasSpecial = false;
  bool _pwMatch = false;
  bool _pwHasInvalidChars = false;

  @override
  void initState() {
    super.initState();
    _firstNameController.addListener(_updateButtonState);
    _lastNameController.addListener(_updateButtonState);
    _emailController.addListener(_updateButtonState);
    _verificationCodeController.addListener(_updateButtonState);
    _usernameController.addListener(_updateButtonState);
    _passwordController.addListener(_updatePasswordMetrics);
    _confirmPasswordController.addListener(_updatePasswordMetrics);
    // Initialize metrics on first build
    _updatePasswordMetrics();
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _middleNameController.dispose();
    _lastNameController.dispose();
    _emailController.dispose();
    _verificationCodeController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();

    _firstNameFocusNode.dispose();
    _middleNameFocusNode.dispose();
    _lastNameFocusNode.dispose();
    _emailFocusNode.dispose();
    _verificationCodeFocusNode.dispose();
    _usernameFocusNode.dispose();
    _passwordFocusNode.dispose();
    _confirmPasswordFocusNode.dispose();
    super.dispose();
  }

  Future<void> _selectDate(BuildContext context) async {
    final DateTime now = DateTime.now();
    final DateTime initialDate = _selectedDate ?? DateTime(now.year - 20, now.month, now.day);
    final DateTime firstDate = DateTime(now.year - 100, now.month, now.day);
    final DateTime lastDate = DateTime(now.year - 15, now.month, now.day);

    final DateTime? picked = await showWheelDatePicker(
      context,
      initialDate: initialDate,
      firstDate: firstDate,
      lastDate: lastDate,
    );

    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
      });
    }
  }

  String? _validateRequired(String? value, String fieldName) {
    if (value == null || value.trim().isEmpty) {
      return _translationService.translate(TranslationKeys.fieldRequired);
    }
    return null;
  }

  String? _validateEmail(String? value) {
    if (value == null || value.trim().isEmpty) {
      return _translationService.translate(TranslationKeys.fieldRequired);
    }
    final emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
    if (!emailRegex.hasMatch(value)) {
      return _translationService.translate(TranslationKeys.invalidEmail);
    }
    return null;
  }

  String? _validateVerificationCode(String? value) {
    if (value == null || value.trim().isEmpty) {
      return _translationService.translate(TranslationKeys.enterVerificationCode);
    }
    final trimmedValue = value.trim();
    if (trimmedValue.length < 4) {
      return _translationService.translate(TranslationKeys.verificationCodeTooShort);
    }
    // Only validate against expected code if we have one (for dev/testing)
    // In production, the server will validate the code
    if (_expectedVerificationCode != null) {
      // Compare as strings, but also try converting to int for flexibility
      final expectedStr = _expectedVerificationCode.toString();
      
      // First try string comparison
      if (trimmedValue == expectedStr) {
        return null; // Codes match
      }
      
      // Try numeric comparison if both are numeric
      try {
        final enteredNum = int.parse(trimmedValue);
        final expectedNum = int.parse(expectedStr);
        if (enteredNum == expectedNum) {
          return null; // Codes match numerically
        }
      } catch (e) {
        // If parsing fails, codes don't match (already checked string comparison)
      }
      
      // Codes don't match
      return _translationService.translate(TranslationKeys.invalidVerificationCode);
    }
    // If no expected code is set, just check minimum length (server will validate)
    return null;
  }

  String? _validatePassword(String? value) {
    if (value == null || value.trim().isEmpty) {
      return _translationService.translate(TranslationKeys.fieldRequired);
    }
    if (value.length < 8) {
      return _translationService.translate(TranslationKeys.passwordTooShort);
    }
    // API requires at least one English letter (A-Z, a-z) and one number (0-9)
    // Allow only English characters and common English keyboard special characters
    // Common English keyboard special characters: ~!@#$%^&*()_+-=[]{}|;:'",.<>?/
    // Using a character class that includes all allowed characters
    // Note: Using regular string to properly escape quotes and dollar signs
    final allowedPattern = RegExp('^[A-Za-z0-9~!@#\\\$%^&*()_+\\-=\\[\\]{}|;:\\\'\\",.<>?/\\\\]+\$');
    if (!allowedPattern.hasMatch(value)) {
      return _translationService.translate(TranslationKeys.onlyEnglishCharsAllowed);
    }
    if (!RegExp(r'[A-Za-z]').hasMatch(value)) {
      return _translationService.translate(TranslationKeys.alphaCharUsed);
    }
    if (!RegExp(r'[0-9]').hasMatch(value)) {
      return _translationService.translate(TranslationKeys.numericCharUsed);
    }
    return null;
  }

  String? _validateConfirmPassword(String? value) {
    if (value == null || value.trim().isEmpty) {
      return _translationService.translate(TranslationKeys.confirmPassword);
    }
    if (value != _passwordController.text) {
      return _translationService.translate(TranslationKeys.passwordsDoNotMatch);
    }
    return null;
  }

  String? _validateDate() {
    if (_selectedDate == null) {
      return _translationService.translate(TranslationKeys.selectDateBirthDesc);
    }
    final age = DateTime.now().difference(_selectedDate!).inDays ~/ 365;
    if (age < 15) {
      return _translationService.translate(TranslationKeys.mustBe15YearsOld);
    }
    return null;
  }

  void _nextGroup() async {
    if (_currentGroup < 6) {
      // If on email step, send verification email
      if (_currentGroup == 2) {
        final success = await _sendVerificationEmail();
        if (!success) {
          return; // Don't proceed if email sending failed
        }
        // If email was already verified, _sendVerificationEmail() will have
        // set _currentGroup to 4, so we should return early here
        if (_currentGroup == 4) {
          return;
        }
      }

      // If on email verification step, verify the code
      if (_currentGroup == 3) {
        final success = await _verifyEmailCode();
        if (!success) {
          return; // Don't proceed if verification failed
        }
      }

      setState(() {
        _currentGroup++;
        _errorMessage = null;
      });
    }
  }

  Future<bool> _sendVerificationEmail() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final result = await _authService.sendEmailVerification(_emailController.text.trim());

      if (mounted) {
        if (result['success']) {
          // Check if email is already verified (same logic as web version)
          final bool alreadyVerified = (result['alreadyVerified'] == true) || (result['status']?.toString().toLowerCase() == 'verified');
          
          if (alreadyVerified) {
            // Email is already verified - skip verification step entirely
            setState(() {
              _currentGroup = 4; // Go directly to username step
              _emailAlreadyVerified = true;
              _verificationEmailSent = false; // Don't mark as sent since it's already verified
              _expectedVerificationCode = null; // No code needed
            });
            
            // Show message that email is already verified
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(_translationService.translate(result['message'] ?? 'Email already verified')),
                backgroundColor: Colors.green,
                duration: const Duration(seconds: 2),
              ),
            );
            return true; // Return early to prevent normal flow
          }

          // Email needs verification - set up verification flow
          setState(() {
            _verificationEmailSent = true;
            // For testing purposes, store the verification code
            // In production, this should not be stored client-side
            _expectedVerificationCode = result['verificationCode'];
          });

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(_translationService.translate(result['message'] ?? TranslationKeys.verificationCodeSentTo)),
              backgroundColor: Colors.green,
            ),
          );
          return true;
        } else {
          setState(() {
            _errorMessage = result['message'];
          });
          return false;
        }
      }
      return false;
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Server error occurred: ${e.toString()}';
        });
      }
      return false;
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<bool> _verifyEmailCode() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final result = await _authService.verifyEmailCode(
        _emailController.text.trim(),
        _verificationCodeController.text.trim(),
      );

      if (mounted) {
        if (result['success']) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(_translationService.translate(result['message'])),
              backgroundColor: Colors.green,
            ),
          );
          return true;
        } else {
          setState(() {
            _errorMessage = result['message'];
          });
          return false;
        }
      }
      return false;
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Server error occurred: ${e.toString()}';
        });
      }
      return false;
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _previousGroup() {
    if (_currentGroup > 0) {
      // If going back from email verification step to email step, reset verification state
      if (_currentGroup == 3) {
        setState(() {
          _verificationEmailSent = false;
          _expectedVerificationCode = null;
          _verificationCodeController.clear();
        });
      }

      // If going back from username step, check if email was already verified
      if (_currentGroup == 4) {
        if (_emailAlreadyVerified) {
          // Go back to email step (group 2) instead of verification step (group 3)
          setState(() {
            _currentGroup = 2;
            _emailAlreadyVerified = false;
            _verificationEmailSent = false;
            _expectedVerificationCode = null;
            _verificationCodeController.clear();
            _errorMessage = null;
          });
          return;
        } else {
          // Normal flow: go back to verification step
          setState(() {
            _verificationCodeController.clear();
          });
        }
      }

      setState(() {
        _currentGroup--;
        _errorMessage = null;
      });
    }
  }

  void _updateButtonState() {
    setState(() {
      // This will trigger a rebuild and update the button state
    });
  }

  void _updatePasswordMetrics() {
    final String pwd = _passwordController.text;
    final String confirm = _confirmPasswordController.text;
    final bool hasMinLen = pwd.length >= 8;
    // Check for English letters (A-Z, a-z)
    final bool hasAlpha = RegExp(r'[A-Za-z]').hasMatch(pwd);
    // Check for numbers (0-9)
    final bool hasNum = RegExp(r'[0-9]').hasMatch(pwd);
    // Check for special characters (common English keyboard symbols)
    // Common English keyboard special characters: ~!@#$%^&*()_+-=[]{}|;:'",.<>?/
    // Using regular strings to properly escape quotes and dollar signs
    final specialCharPattern = RegExp('[~!@#\\\$%^&*()_+\\-=\\[\\]{}|;:\\\'\\",.<>?/\\\\]');
    final bool hasSpecial = specialCharPattern.hasMatch(pwd);
    // Check for invalid characters (anything not English letters, numbers, or allowed special chars)
    final allowedPattern = RegExp('^[A-Za-z0-9~!@#\\\$%^&*()_+\\-=\\[\\]{}|;:\\\'\\",.<>?/\\\\]+\$');
    final bool hasInvalidChars = !allowedPattern.hasMatch(pwd);
    final int met = [hasMinLen, hasAlpha, hasNum, hasSpecial].where((b) => b).length;
    final double strength = hasInvalidChars ? 0.0 : (met / 4.0); // Set strength to 0 if invalid chars exist
    setState(() {
      _pwHasMinLen = hasMinLen;
      _pwHasAlpha = hasAlpha;
      _pwHasNum = hasNum;
      _pwHasSpecial = hasSpecial;
      _pwHasInvalidChars = hasInvalidChars;
      _pwMatch = confirm.isNotEmpty && pwd == confirm;
      _passwordStrength = strength;
    });
  }

  bool _canProceedToNextGroup() {
    switch (_currentGroup) {
      case 0: // Date
        return _validateDate() == null;
      case 1: // Full name
        return _firstNameController.text.trim().isNotEmpty && _lastNameController.text.trim().isNotEmpty;
      case 2: // Email
        return _validateEmail(_emailController.text) == null;
      case 3: // Email verification
        return _validateVerificationCode(_verificationCodeController.text) == null;
      case 4: // Username
        return _usernameController.text.trim().isNotEmpty;
      case 5: // Password
        return _validatePassword(_passwordController.text) == null && _validateConfirmPassword(_confirmPasswordController.text) == null;
      case 6: // Profile package
        return _selectedPackage != null;
      default:
        return false;
    }
  }

  Future<void> _handleRegister() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    if (_validateDate() != null) {
      setState(() {
        _errorMessage = _validateDate();
      });
      return;
    }

    if (_validatePassword(_passwordController.text) != null) {
      setState(() {
        _errorMessage = _validatePassword(_passwordController.text);
      });
      return;
    }

    if (_validateConfirmPassword(_confirmPasswordController.text) != null) {
      setState(() {
        _errorMessage = _validateConfirmPassword(_confirmPasswordController.text);
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // Determine private and visible values based on selected package
      bool isPrivate = false;
      bool isVisible = true;
      
      if (_selectedPackage == 'op') {
        // Open Profile: public and visible
        isPrivate = false;
        isVisible = true;
      } else if (_selectedPackage == 'pp') {
        // Private Profile: private and invisible
        isPrivate = true;
        isVisible = false;
      } else if (_selectedPackage == 'cp') {
        // Custom: use selected values
        isPrivate = _isPrivate;
        isVisible = _isVisible;
      }
      
      // Call the actual registration API
          // Get device language for registration
          String? deviceLanguage;
          try {
            final locale = Platform.localeName;
            final languageCode = locale.split('_').first.toLowerCase();
            final supportedLanguages = ['en', 'no', 'dk', 'se', 'de', 'fr', 'pl', 'es', 'it', 'pt', 'nl', 'fi'];
            if (supportedLanguages.contains(languageCode)) {
              deviceLanguage = languageCode;
            } else {
              // Try country code mapping
              final countryCode = locale.split('_').last.toUpperCase();
              final countryToLanguageMap = {
                'US': 'en', 'GB': 'en', 'AU': 'en', 'CA': 'en', 'NO': 'no', 'DK': 'dk', 'SE': 'se',
                'DE': 'de', 'FR': 'fr', 'PL': 'pl', 'ES': 'es', 'IT': 'it', 'PT': 'pt', 'NL': 'nl', 'FI': 'fi',
              };
              deviceLanguage = countryToLanguageMap[countryCode] ?? 'en';
            }
          } catch (e) {
            deviceLanguage = 'en'; // Fallback to English
          }

          final result = await _authService.registerUser(
            email: _emailController.text.trim(),
            username: _usernameController.text.trim(),
            password: _passwordController.text,
            firstName: _firstNameController.text.trim(),
            middleName: _middleNameController.text.trim().isEmpty ? null : _middleNameController.text.trim(),
            lastName: _lastNameController.text.trim(),
            dateOfBirth: _selectedDate!,
            isPrivate: isPrivate,
            isVisible: isVisible,
            language: deviceLanguage,
          );

      if (mounted) {
        if (result['success'] == true) {
          // Show success message
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(_translationService.translate(result['message'] ?? TranslationKeys.registrationSuccessful)),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 3),
            ),
          );
          
          // Navigate to home screen (user is now logged in)
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (context) => const HomeScreen()),
          );
        } else {
          // Show error message
          setState(() {
            _errorMessage = _translationService.translate(result['message'] ?? TranslationKeys.registrationFailed);
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = '${_translationService.translate(TranslationKeys.registrationFailed)}: ${e.toString()}';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Widget _buildCurrentGroup() {
    switch (_currentGroup) {
      case 0:
        return _buildDateGroup();
      case 1:
        return _buildFullNameGroup();
      case 2:
        return _buildEmailGroup();
      case 3:
        return _buildEmailVerificationGroup();
      case 4:
        return _buildUsernameGroup();
      case 5:
        return _buildPasswordGroup();
      case 6:
        return _buildProfilePackageGroup();
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildDateGroup() {

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : Colors.black87;
    final secondaryTextColor = isDark ? Colors.white70 : Colors.black54;
    final containerColor = isDark ? Colors.white.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.05);
    final borderColor = isDark ? Colors.white.withValues(alpha: 0.3) : Colors.black.withValues(alpha: 0.2);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _translationService.translate(TranslationKeys.dateOfBirth),
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: textColor,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          _translationService.translate(TranslationKeys.selectDateBirthDesc),
          style: TextStyle(
            fontSize: 14,
            color: secondaryTextColor,
          ),
        ),
        const SizedBox(height: 20),

        // Date selection button
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: () => _selectDate(context),
            style: ElevatedButton.styleFrom(
              backgroundColor: containerColor,
              foregroundColor: textColor,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
                side: BorderSide(
                  color: borderColor,
                  width: 1.5,
                ),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  _selectedDate != null ? Icons.check_circle : Icons.calendar_today,
                  color: textColor,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  _selectedDate != null ? '${_selectedDate!.day}/${_selectedDate!.month}/${_selectedDate!.year}' : _translationService.translate(TranslationKeys.selectDate),
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: textColor,
                  ),
                ),
              ],
            ),
          ),
        ),

        if (_selectedDate != null) ...[
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: borderColor,
                width: 1.5,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.check_circle,
                  color: textColor,
                  size: 24,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _translationService.translate(TranslationKeys.basedOnSelection),
                        style: TextStyle(
                          color: textColor,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${DateTime.now().difference(_selectedDate!).inDays ~/ 365} ${_translationService.translate(TranslationKeys.yearsOld)}',
                        style: TextStyle(
                          color: secondaryTextColor,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildFullNameGroup() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : Colors.black87;
    final secondaryTextColor = isDark ? Colors.white70 : Colors.black54;
    final containerColor = isDark ? Colors.white.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.05);
    final hintColor = isDark ? Colors.white.withValues(alpha: 0.7) : Colors.black.withValues(alpha: 0.6);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _translationService.translate(TranslationKeys.fullName),
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: textColor,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          _translationService.translate(TranslationKeys.fullNameDesc),
          style: TextStyle(
            fontSize: 14,
            color: secondaryTextColor,
          ),
        ),
        const SizedBox(height: 20),

        // First Name
        Text(
          _translationService.translate(TranslationKeys.firstName),
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: textColor,
          ),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: _firstNameController,
          focusNode: _firstNameFocusNode,
          validator: (value) => _validateRequired(value, 'First name'),
          decoration: InputDecoration(
            filled: true,
            fillColor: containerColor,
            hintText: _translationService.translate(TranslationKeys.enterFirstName),
            hintStyle: TextStyle(
              color: hintColor,
              fontSize: 16,
            ),
            prefixIcon: Icon(Icons.person, color: textColor),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide.none,
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          ),
          style: TextStyle(
            color: textColor,
            fontSize: 16,
          ),
          textInputAction: TextInputAction.next,
          onFieldSubmitted: (_) => _middleNameFocusNode.requestFocus(),
        ),
        const SizedBox(height: 20),

        // Middle Name (Optional)
        Text(
          _translationService.translate(TranslationKeys.middleNameOptional),
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: textColor,
          ),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: _middleNameController,
          focusNode: _middleNameFocusNode,
          decoration: InputDecoration(
            filled: true,
            fillColor: containerColor,
            hintText: _translationService.translate(TranslationKeys.enterMiddleName),
            hintStyle: TextStyle(
              color: hintColor,
              fontSize: 16,
            ),
            prefixIcon: Icon(Icons.person, color: textColor),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide.none,
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          ),
          style: TextStyle(
            color: textColor,
            fontSize: 16,
          ),
          textInputAction: TextInputAction.next,
          onFieldSubmitted: (_) => _lastNameFocusNode.requestFocus(),
        ),
        const SizedBox(height: 20),

        // Last Name
        Text(
          _translationService.translate(TranslationKeys.lastName),
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: textColor,
          ),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: _lastNameController,
          focusNode: _lastNameFocusNode,
          validator: (value) => _validateRequired(value, 'Last name'),
          decoration: InputDecoration(
            filled: true,
            fillColor: containerColor,
            hintText: _translationService.translate(TranslationKeys.enterLastName),
            hintStyle: TextStyle(
              color: hintColor,
              fontSize: 16,
            ),
            prefixIcon: Icon(Icons.person, color: textColor),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide.none,
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          ),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
          ),
          textInputAction: TextInputAction.done,
          onFieldSubmitted: (_) => _nextGroup(),
        ),
      ],
    );
  }

  Widget _buildEmailGroup() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : Colors.black87;
    final secondaryTextColor = isDark ? Colors.white70 : Colors.black54;
    final containerColor = isDark ? Colors.white.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.05);
    final hintColor = isDark ? Colors.white.withValues(alpha: 0.7) : Colors.black.withValues(alpha: 0.6);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _translationService.translate(TranslationKeys.emailAddress),
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: textColor,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          _translationService.translate(TranslationKeys.emailDesc),
          style: TextStyle(
            fontSize: 14,
            color: secondaryTextColor,
          ),
        ),
        const SizedBox(height: 20),

        // Email input
        Text(
          _translationService.translate(TranslationKeys.email),
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: textColor,
          ),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: _emailController,
          focusNode: _emailFocusNode,
          keyboardType: TextInputType.emailAddress,
          validator: _validateEmail,
          decoration: InputDecoration(
            filled: true,
            fillColor: containerColor,
            hintText: _translationService.translate(TranslationKeys.enterEmail),
            hintStyle: TextStyle(
              color: hintColor,
              fontSize: 16,
            ),
            prefixIcon: Icon(Icons.email, color: textColor),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide.none,
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          ),
          style: TextStyle(
            color: textColor,
            fontSize: 16,
          ),
          textInputAction: TextInputAction.done,
          onFieldSubmitted: (_) => _nextGroup(),
          onChanged: (value) {
            // Reset verification state if email changes
            if (_verificationEmailSent || _emailAlreadyVerified) {
              setState(() {
                _verificationEmailSent = false;
                _emailAlreadyVerified = false;
                _expectedVerificationCode = null;
                _verificationCodeController.clear();
              });
            }
          },
        ),

        // Success message when email is sent
        if (_verificationEmailSent) ...[
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.blue.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: Colors.blue.withValues(alpha: 0.3),
                width: 1.5,
              ),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.email,
                  color: Colors.blue,
                  size: 24,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _translationService.translate(TranslationKeys.emailSent),
                        style: TextStyle(
                          color: Colors.blue,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${_translationService.translate(TranslationKeys.verificationCodeSentTo)}${_emailController.text}',
                        style: TextStyle(
                          color: Colors.blue.withValues(alpha: 0.8),
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildEmailVerificationGroup() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : Colors.black87;
    final secondaryTextColor = isDark ? Colors.white70 : Colors.black54;
    final containerColor = isDark ? Colors.white.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.05);
    final hintColor = isDark ? Colors.white.withValues(alpha: 0.7) : Colors.black.withValues(alpha: 0.6);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _translationService.translate(TranslationKeys.emailVerification),
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: textColor,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '${_translationService.translate(TranslationKeys.enterCodeSentTo)}${_emailController.text}',
          style: TextStyle(
            fontSize: 14,
            color: secondaryTextColor,
          ),
        ),
        const SizedBox(height: 20),
        const SizedBox(height: 20),

        // Verification code input
        Text(
          _translationService.translate(TranslationKeys.verificationCode),
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: textColor,
          ),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: _verificationCodeController,
          focusNode: _verificationCodeFocusNode,
          keyboardType: TextInputType.number,
          validator: _validateVerificationCode,
          decoration: InputDecoration(
            filled: true,
            fillColor: containerColor,
            hintText: _translationService.translate(TranslationKeys.enterVerificationCode),
            hintStyle: TextStyle(
              color: hintColor,
              fontSize: 16,
            ),
          ),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
          ),
          textInputAction: TextInputAction.done,
          onFieldSubmitted: (_) => _nextGroup(),
        ),

        const SizedBox(height: 20),

        // Resend code button
        Center(
          child: TextButton(
            onPressed: _isLoading
                ? null
                : () async {
                    final success = await _sendVerificationEmail();
                    if (success) {
                      setState(() {
                        _verificationCodeController.clear();
                      });
                    }
                  },
            child: Text(
              _translationService.translate(TranslationKeys.resendCode),
              style: TextStyle(
                color: textColor,
                fontSize: 14,
                fontWeight: FontWeight.w600,
                decoration: TextDecoration.underline,
                decorationColor: textColor,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildUsernameGroup() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : Colors.black87;
    final secondaryTextColor = isDark ? Colors.white70 : Colors.black54;
    final containerColor = isDark ? Colors.white.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.05);
    final hintColor = isDark ? Colors.white.withValues(alpha: 0.7) : Colors.black.withValues(alpha: 0.6);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _translationService.translate(TranslationKeys.username),
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: textColor,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          _translationService.translate(TranslationKeys.usernameDesc),
          style: TextStyle(
            fontSize: 14,
            color: secondaryTextColor,
          ),
        ),
        const SizedBox(height: 20),
        TextFormField(
          controller: _usernameController,
          focusNode: _usernameFocusNode,
          validator: (value) => _validateRequired(value, 'Username'),
          decoration: InputDecoration(
            filled: true,
            fillColor: containerColor,
            hintText: _translationService.translate(TranslationKeys.enterUsername),
            hintStyle: TextStyle(
              color: hintColor,
              fontSize: 16,
            ),
            prefixIcon: Icon(Icons.account_circle, color: textColor),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide.none,
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          ),
          style: TextStyle(
            color: textColor,
            fontSize: 16,
          ),
          textInputAction: TextInputAction.done,
          onFieldSubmitted: (_) => _nextGroup(),
        ),
      ],
    );
  }

  Widget _buildPasswordGroup() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : Colors.black87;
    final secondaryTextColor = isDark ? Colors.white70 : Colors.black54;
    final containerColor = isDark ? Colors.white.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.05);
    final hintColor = isDark ? Colors.white.withValues(alpha: 0.7) : Colors.black.withValues(alpha: 0.6);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _translationService.translate(TranslationKeys.password),
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: textColor,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          _translationService.translate(TranslationKeys.passwordDesc),
          style: TextStyle(
            fontSize: 14,
            color: secondaryTextColor,
          ),
        ),
        const SizedBox(height: 20),

        // Password
        Text(
          _translationService.translate(TranslationKeys.password),
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: textColor,
          ),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: _passwordController,
          focusNode: _passwordFocusNode,
          obscureText: _obscurePassword,
          validator: _validatePassword,
          decoration: InputDecoration(
            filled: true,
            fillColor: containerColor,
            hintText: _translationService.translate(TranslationKeys.enterPassword),
            hintStyle: TextStyle(
              color: hintColor,
              fontSize: 16,
            ),
            prefixIcon: Icon(Icons.lock_outline, color: textColor),
            suffixIcon: IconButton(
              icon: Icon(
                _obscurePassword ? Icons.visibility : Icons.visibility_off,
                color: hintColor,
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
            color: textColor,
            fontSize: 16,
          ),
          textInputAction: TextInputAction.next,
          onFieldSubmitted: (_) => _confirmPasswordFocusNode.requestFocus(),
          onChanged: (_) => _updatePasswordMetrics(),
        ),
        const SizedBox(height: 20),

        // Confirm Password
        Text(
          _translationService.translate(TranslationKeys.confirmPassword),
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: textColor,
          ),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: _confirmPasswordController,
          focusNode: _confirmPasswordFocusNode,
          obscureText: _obscureConfirmPassword,
          validator: _validateConfirmPassword,
          decoration: InputDecoration(
            filled: true,
            fillColor: containerColor,
            hintText: _translationService.translate(TranslationKeys.confirmPassword),
            hintStyle: TextStyle(
              color: hintColor,
              fontSize: 16,
            ),
            prefixIcon: Icon(Icons.lock_outline, color: textColor),
            suffixIcon: IconButton(
              icon: Icon(
                _obscureConfirmPassword ? Icons.visibility : Icons.visibility_off,
                color: hintColor,
              ),
              onPressed: () {
                setState(() {
                  _obscureConfirmPassword = !_obscureConfirmPassword;
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
            color: textColor,
            fontSize: 16,
          ),
          textInputAction: TextInputAction.done,
          onFieldSubmitted: (_) => _nextGroup(),
          onChanged: (_) => _updatePasswordMetrics(),
        ),
        const SizedBox(height: 20),
        // Password strength bar
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: _passwordStrength.clamp(0.0, 1.0),
            minHeight: 12,
            backgroundColor: isDark ? Colors.white.withValues(alpha: 0.2) : Colors.black.withValues(alpha: 0.1),
            valueColor: AlwaysStoppedAnimation<Color>(
              _passwordStrength < 0.5 ? Colors.red : (_passwordStrength < 0.75 ? Colors.orange : Colors.green),
            ),
          ),
        ),
        const SizedBox(height: 12),
        _buildRequirementRow(_translationService.translate(TranslationKeys.atLeast8Chars), _pwHasMinLen),
        _buildRequirementRow(_translationService.translate(TranslationKeys.alphaCharUsed), _pwHasAlpha),
        _buildRequirementRow(_translationService.translate(TranslationKeys.numericCharUsed), _pwHasNum),
        _buildRequirementRow(_translationService.translate(TranslationKeys.specialCharUsed), _pwHasSpecial),
        _buildRequirementRow(_translationService.translate(TranslationKeys.onlyEnglishCharsAllowed), !_pwHasInvalidChars),
        _buildRequirementRow(_translationService.translate(TranslationKeys.passwordsMatch), _pwMatch),
      ],
    );
  }

  Widget _buildRequirementRow(String text, bool met) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        children: [
          Icon(
            met ? Icons.check_circle : Icons.cancel,
            color: met ? Colors.green : Colors.red,
            size: 18,
          ),
          const SizedBox(width: 8),
          Text(
            text,
            style: TextStyle(
              color: (Theme.of(context).brightness == Brightness.dark ? Colors.white : Colors.black87),
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProfilePackageGroup() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : Colors.black87;
    final secondaryTextColor = isDark ? Colors.white70 : Colors.black54;
    final containerColor = isDark ? Colors.white.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.05);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _translationService.translate(TranslationKeys.profilePrivacy),
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: textColor,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          _translationService.translate(TranslationKeys.profilePrivacyDesc),
          style: TextStyle(
            fontSize: 14,
            color: secondaryTextColor,
          ),
        ),
        const SizedBox(height: 20),

        // Open Profile Option
        GestureDetector(
          onTap: () {
            setState(() {
              _selectedPackage = 'op';
            });
          },
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _selectedPackage == 'op' 
                  ? Colors.blue.withValues(alpha: 0.3)
                  : containerColor,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: _selectedPackage == 'op' 
                    ? Colors.blue
                    : (isDark ? Colors.white.withValues(alpha: 0.3) : Colors.black.withValues(alpha: 0.2)),
                width: _selectedPackage == 'op' ? 2 : 1.5,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Radio<String>(
                      value: 'op',
                      groupValue: _selectedPackage,
                      onChanged: (value) {
                        setState(() {
                          _selectedPackage = value;
                        });
                      },
                      activeColor: (isDark ? Colors.white : Colors.blue),
                    ),
                    Text(
                      _translationService.translate(TranslationKeys.openProfile),
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: textColor,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  '• ${_translationService.translate(TranslationKeys.appearInSearch)}',
                  style: TextStyle(color: secondaryTextColor, fontSize: 14),
                ),
                Text(
                  '• ${_translationService.translate(TranslationKeys.profileIsVisible)}',
                  style: TextStyle(color: secondaryTextColor, fontSize: 14),
                ),
                Text(
                  '• ${_translationService.translate(TranslationKeys.anyoneCanMessage)}',
                  style: TextStyle(color: secondaryTextColor, fontSize: 14),
                ),
                Text(
                  '• ${_translationService.translate(TranslationKeys.appearForNewUsers)}',
                  style: TextStyle(color: secondaryTextColor, fontSize: 14),
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 16),

        // Private Profile Option
        GestureDetector(
          onTap: () {
            setState(() {
              _selectedPackage = 'pp';
            });
          },
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _selectedPackage == 'pp' 
                  ? Colors.blue.withValues(alpha: 0.3)
                  : containerColor,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: _selectedPackage == 'pp' 
                    ? Colors.blue
                    : (isDark ? Colors.white.withValues(alpha: 0.3) : Colors.black.withValues(alpha: 0.2)),
                width: _selectedPackage == 'pp' ? 2 : 1.5,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Radio<String>(
                      value: 'pp',
                      groupValue: _selectedPackage,
                      onChanged: (value) {
                        setState(() {
                          _selectedPackage = value;
                        });
                      },
                      activeColor: (isDark ? Colors.white : Colors.blue),
                    ),
                    Text(
                      _translationService.translate(TranslationKeys.privateProfile),
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: textColor,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  '• ${_translationService.translate(TranslationKeys.notAppearInSearch)}',
                  style: TextStyle(color: secondaryTextColor, fontSize: 14),
                ),
                Text(
                  '• ${_translationService.translate(TranslationKeys.profileIsInvisible)}',
                  style: TextStyle(color: secondaryTextColor, fontSize: 14),
                ),
                Text(
                  '• ${_translationService.translate(TranslationKeys.onlyFriendsCanMessage)}',
                  style: TextStyle(color: secondaryTextColor, fontSize: 14),
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 16),

        // Custom Profile Option
        GestureDetector(
          onTap: () {
            setState(() {
              _selectedPackage = 'cp';
            });
          },
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _selectedPackage == 'cp' 
                  ? Colors.blue.withValues(alpha: 0.3)
                  : containerColor,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: _selectedPackage == 'cp' 
                    ? Colors.blue
                    : (isDark ? Colors.white.withValues(alpha: 0.3) : Colors.black.withValues(alpha: 0.2)),
                width: _selectedPackage == 'cp' ? 2 : 1.5,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Radio<String>(
                      value: 'cp',
                      groupValue: _selectedPackage,
                      onChanged: (value) {
                        setState(() {
                          _selectedPackage = value;
                        });
                      },
                      activeColor: (isDark ? Colors.white : Colors.blue),
                    ),
                    Text(
                      _translationService.translate(TranslationKeys.custom),
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: textColor,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (_selectedPackage == 'cp') ...[
                  // Privacy setting
                  Container(
                    padding: const EdgeInsets.all(12),
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.03),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _translationService.translate(TranslationKeys.privacy),
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: textColor,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Radio<bool>(
                              value: true,
                              groupValue: _isPrivate,
                              onChanged: (value) {
                                setState(() {
                                  _isPrivate = value ?? false;
                                });
                              },
                              activeColor: (isDark ? Colors.white : Colors.blue),
                            ),
                             Text(
                               _translationService.translate(TranslationKeys.private),
                               style: TextStyle(color: textColor, fontSize: 14),
                             ),
                            const SizedBox(width: 20),
                            Radio<bool>(
                              value: false,
                              groupValue: _isPrivate,
                              onChanged: (value) {
                                setState(() {
                                  _isPrivate = value ?? false;
                                });
                              },
                              activeColor: (isDark ? Colors.white : Colors.blue),
                            ),
                             Text(
                               _translationService.translate(TranslationKeys.public),
                               style: TextStyle(color: textColor, fontSize: 14),
                             ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  // Visibility setting
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.03),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                         Text(
                           _translationService.translate(TranslationKeys.visibility),
                           style: TextStyle(
                             fontSize: 16,
                             fontWeight: FontWeight.w600,
                             color: textColor,
                           ),
                         ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Radio<bool>(
                              value: true,
                              groupValue: _isVisible,
                              onChanged: (value) {
                                setState(() {
                                  _isVisible = value ?? true;
                                });
                              },
                              activeColor: (isDark ? Colors.white : Colors.blue),
                            ),
                             Text(
                               _translationService.translate(TranslationKeys.visible),
                               style: TextStyle(color: textColor, fontSize: 14),
                             ),
                            const SizedBox(width: 20),
                            Radio<bool>(
                              value: false,
                              groupValue: _isVisible,
                              onChanged: (value) {
                                setState(() {
                                  _isVisible = value ?? false;
                                });
                              },
                              activeColor: (isDark ? Colors.white : Colors.blue),
                            ),
                             Text(
                               _translationService.translate(TranslationKeys.invisible),
                               style: TextStyle(color: textColor, fontSize: 14),
                             ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ] else ...[
                   Text(
                     _translationService.translate(TranslationKeys.setManually),
                     style: TextStyle(color: secondaryTextColor, fontSize: 14),
                   ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildNavigationButtons() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : Colors.black87;

    return Column(
      children: [
        // Continue button
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: (!_isLoading && _canProceedToNextGroup()) 
                ? (_currentGroup == 6 ? _handleRegister : _nextGroup)
                : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.transparent,
              foregroundColor: textColor,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(15),
              ),
              elevation: 0,
            ).copyWith(
              backgroundColor: WidgetStateProperty.all(Colors.transparent),
            ),
            child: Container(
              decoration: BoxDecoration(
                gradient: _canProceedToNextGroup()
                    ? const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Color.fromRGBO(33, 150, 243, 1.0), // Blue
                          Color.fromRGBO(25, 118, 210, 1.0), // Darker blue
                        ],
                      )
                    : const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Color.fromRGBO(158, 158, 158, 1.0), // Grey
                          Color.fromRGBO(117, 117, 117, 1.0), // Darker grey
                        ],
                      ),
                borderRadius: BorderRadius.circular(15),
                border: Border.all(
                  color: _canProceedToNextGroup() 
                      ? (isDark ? Colors.white.withValues(alpha: 0.3) : Colors.black.withValues(alpha: 0.2)) 
                      : (isDark ? Colors.white.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.1)),
                  width: 1.5,
                ),
              ),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Center(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                       Text(
                        _currentGroup == 6 ? _translationService.translate(TranslationKeys.createAccount) : _translationService.translate(TranslationKeys.continueButton),
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: _canProceedToNextGroup() ? Colors.white : Colors.white.withValues(alpha: 0.6),
                          letterSpacing: 0.5,
                        ),
                      ),
                      if (_currentGroup < 6) ...[
                        const SizedBox(width: 8),
                        Icon(
                          Icons.arrow_forward,
                          color: _canProceedToNextGroup() ? Colors.white : Colors.white.withValues(alpha: 0.6),
                          size: 20,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),

        // Go back button (only show if not on first group)
        if (_currentGroup > 0) ...[
          SizedBox(
            width: double.infinity * 0.6, // Reduced width to 60%
            child: ElevatedButton(
              onPressed: _previousGroup,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.transparent,
                foregroundColor: textColor,
                padding: const EdgeInsets.symmetric(vertical: 12), // Reduced from 16
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12), // Reduced from 15
                ),
                elevation: 0,
              ).copyWith(
                backgroundColor: WidgetStateProperty.all(Colors.transparent),
              ),
              child: Container(
                decoration: BoxDecoration(
                  color: isDark ? Colors.white.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(12), // Reduced from 15
                  border: Border.all(
                    color: isDark ? Colors.white.withValues(alpha: 0.3) : Colors.black.withValues(alpha: 0.2),
                    width: 1.0, // Reduced from 1.5
                  ),
                ),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 12), // Reduced from 16
                  child: Center(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.arrow_back,
                          color: textColor,
                          size: 16, // Reduced from 20
                        ),
                        const SizedBox(width: 6), // Reduced from 8
                        Text(
                          _translationService.translate(TranslationKeys.goBack),
                          style: TextStyle(
                            fontSize: 14, // Reduced from 18
                            fontWeight: FontWeight.w600,
                            color: textColor,
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
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : Colors.black87;
    final secondaryTextColor = isDark ? Colors.white70 : Colors.black54;
    final containerColor = isDark ? Colors.white.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.05);

    return Scaffold(
      body: Stack(
        children: [
          const BackgroundGradient(),
          SafeArea(
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Back button and title
                      Row(
                        children: [
                          IconButton(
                            onPressed: () => Navigator.of(context).pop(),
                            icon: Icon(Icons.arrow_back, color: textColor),
                          ),
                          const SizedBox(width: 16),
                          Text(
                            _translationService.translate(TranslationKeys.createAccount),
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: textColor,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),

                      // Progress indicator
                      Row(
                        children: List.generate(7, (index) {
                          return Expanded(
                            child: Container(
                              height: 4,
                              margin: EdgeInsets.only(right: index < 6 ? 8 : 0),
                              decoration: BoxDecoration(
                                color: index <= _currentGroup ? (isDark ? Colors.white : Colors.blue) : (isDark ? Colors.white.withValues(alpha: 0.3) : Colors.black.withValues(alpha: 0.1)),
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          );
                        }),
                      ),
                      const SizedBox(height: 30),

                      // Group content based on current group
                      _buildCurrentGroup(),
                      const SizedBox(height: 30),

                      // Error message
                      if (_errorMessage != null) ...[
                        Container(
                          padding: const EdgeInsets.all(12),
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
                        const SizedBox(height: 20),
                      ],

                      // Navigation buttons
                      _buildNavigationButtons(),
                      const SizedBox(height: 20),

                      // Login link (only show on first group)
                      if (_currentGroup == 0) ...[
                        Center(
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                               Text(
                                _translationService.translate(TranslationKeys.alreadyHaveAccount),
                                style: TextStyle(
                                  color: textColor,
                                  fontSize: 14,
                                ),
                              ),
                              TextButton(
                                onPressed: () => Navigator.of(context).pop(),
                                style: TextButton.styleFrom(
                                  padding: EdgeInsets.zero,
                                  minimumSize: Size.zero,
                                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                ),
                                 child: Text(
                                  _translationService.translate(TranslationKeys.signIn),
                                  style: TextStyle(
                                    color: (isDark ? Colors.white : Colors.blue),
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                    decoration: TextDecoration.underline,
                                    decorationColor: (isDark ? Colors.white : Colors.blue),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
