import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'dart:io';
import 'dart:ui';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../models/user.dart';
import '../widgets/background_gradient.dart';
import '../widgets/custom_app_bar.dart';
import '../widgets/custom_bottom_navigation_bar.dart';
import '../widgets/app_colors.dart';
import '../services/auth_service.dart';
import '../services/theme_service.dart';
import '../services/local_auth_service.dart';
import '../services/translation_service.dart';
import '../services/auto_update_service.dart';
import '../services/friend_service.dart';
import '../services/post_service.dart';
import '../widgets/translated_text.dart';
import '../widgets/update_dialog.dart';
import '../utils/translation_keys.dart';
import '../config/constants.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  // Example user data (replace with real data source)
  String email = '';
  String username = '';
  String nickname = '';
  String profileImage = 'assets/images/logo.png';
  String backgroundImage = 'assets/images/background.png';
  User? user;

  bool notificationsEnabled = true;
  bool isPrivate = false;
  bool _biometricEnabled = false;

  final _oldPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  File? _newAvatarFile;
  File? _newBackgroundFile;
  bool _isUploadingAvatar = false;
  bool _isUploadingWallpaper = false;
  final ImagePicker _picker = ImagePicker();

  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _nicknameController = TextEditingController();
  final TextEditingController _firstNameController = TextEditingController();
  final TextEditingController _middleNameController = TextEditingController();
  final TextEditingController _lastNameController = TextEditingController();
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _bioController = TextEditingController();
  DateTime? _birthDate;

  final List<String> _pinOptions = ['No PIN', '4 digit', '6 digit', '8 digit'];
  String? _selectedPinOption;
  final TextEditingController _currentPinController = TextEditingController();
  final TextEditingController _newPinController = TextEditingController();
  final TextEditingController _confirmPinController = TextEditingController();

  final TextEditingController _secQOneController = TextEditingController();
  final TextEditingController _secAOneController = TextEditingController();
  final TextEditingController _secQTwoController = TextEditingController();
  final TextEditingController _secATwoController = TextEditingController();

  List<double>? avatarMargin;
  List<double>? backgroundMargin;

  // Add focus nodes for proper focus management
  final FocusNode _emailFocusNode = FocusNode();
  final FocusNode _usernameFocusNode = FocusNode();
  final FocusNode _nicknameFocusNode = FocusNode();
  final FocusNode _firstNameFocusNode = FocusNode();
  final FocusNode _middleNameFocusNode = FocusNode();
  final FocusNode _lastNameFocusNode = FocusNode();
  final FocusNode _titleFocusNode = FocusNode();
  final FocusNode _bioFocusNode = FocusNode();
  final FocusNode _oldPasswordFocusNode = FocusNode();
  final FocusNode _newPasswordFocusNode = FocusNode();
  final FocusNode _confirmPasswordFocusNode = FocusNode();
  final FocusNode _currentPinFocusNode = FocusNode();
  final FocusNode _newPinFocusNode = FocusNode();
  final FocusNode _confirmPinFocusNode = FocusNode();
  final FocusNode _secQOneFocusNode = FocusNode();
  final FocusNode _secAOneFocusNode = FocusNode();
  final FocusNode _secQTwoFocusNode = FocusNode();
  final FocusNode _secATwoFocusNode = FocusNode();
  
  // IP History
  List<Map<String, dynamic>> _ipHistory = [];
  bool _isLoadingIpHistory = false;

  // Update check status
  String _updateCheckStatus = '';
  bool _isCheckingForUpdates = false;
  final GlobalKey _notificationButtonKey = GlobalKey();


  @override
  void initState() {
    super.initState();
    _loadUserProfile();
    _loadBiometricSetting();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      setState(() {
        _selectedPinOption = _getPinOptionFromValue(user?.pinV);
        _secQOneController.text = user?.secQOne ?? '';
        _secAOneController.text = user?.secAOne ?? '';
        _secQTwoController.text = user?.secQTwo ?? '';
        _secATwoController.text = user?.secATwo ?? '';
      });
    });
  }

  Future<void> _loadUserProfile() async {
    final cachedUser = await AuthService().getStoredUserProfile();
    print('Loaded cached user:');
    print(cachedUser);
    if (cachedUser != null) {
      print('Cached user email: \'${cachedUser.email}\'');
      print('Cached user username: \'${cachedUser.username}\'');
      print('Cached user nickname: \'${cachedUser.nickname}\'');
      _emailController.text = cachedUser.email;
      _usernameController.text = cachedUser.username;
      _nicknameController.text = cachedUser.nickname;
      _firstNameController.text = cachedUser.fname;
      _middleNameController.text = cachedUser.mname;
      _lastNameController.text = cachedUser.lname;
      _titleController.text = cachedUser.title;
      _bioController.text = cachedUser.bio;
      setState(() {
        user = cachedUser;
        email = cachedUser.email;
        username = cachedUser.username;
        nickname = cachedUser.nickname;
        isPrivate = cachedUser.visible == '0';
        if (cachedUser.avatar.isNotEmpty) {
          profileImage = cachedUser.avatar;
        }
        if (cachedUser.wallpaper.isNotEmpty) {
          backgroundImage = cachedUser.wallpaper;
        }
      });
      // Load IP history
      _loadIpHistory();
    } else {
      print('No cached user found.');
    }
  }

  Future<void> _loadBiometricSetting() async {
    final isEnabled = await LocalAuthService.isBiometricEnabled();
    setState(() {
      _biometricEnabled = isEnabled;
    });
  }

  @override
  void dispose() {
    // Dispose all focus nodes to prevent memory leaks and context menu conflicts
    _emailFocusNode.dispose();
    _usernameFocusNode.dispose();
    _nicknameFocusNode.dispose();
    _oldPasswordFocusNode.dispose();
    _newPasswordFocusNode.dispose();
    _confirmPasswordFocusNode.dispose();
    _currentPinFocusNode.dispose();
    _newPinFocusNode.dispose();
    _confirmPinFocusNode.dispose();
    _secQOneFocusNode.dispose();
    _secAOneFocusNode.dispose();
    _secQTwoFocusNode.dispose();
    _secATwoFocusNode.dispose();

    // Dispose controllers
    _emailController.dispose();
    _usernameController.dispose();
    _nicknameController.dispose();
    _firstNameController.dispose();
    _middleNameController.dispose();
    _lastNameController.dispose();
    _titleController.dispose();
    _bioController.dispose();
    _oldPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    _currentPinController.dispose();
    _newPinController.dispose();
    _confirmPinController.dispose();
    _secQOneController.dispose();
    _secAOneController.dispose();
    _secQTwoController.dispose();
    _secATwoController.dispose();
    
    // Dispose focus nodes
    _firstNameFocusNode.dispose();
    _middleNameFocusNode.dispose();
    _lastNameFocusNode.dispose();
    _titleFocusNode.dispose();
    _bioFocusNode.dispose();
    
    super.dispose();
  }

  // Helper to show picker dialog for avatar or wallpaper
  Future<void> _showImageSourceDialog({required bool isAvatar}) async {
    if (!mounted) return;
    
    try {
      final source = await showDialog<ImageSource>(
        context: context,
        builder: (context) => SimpleDialog(
          title: Text(isAvatar ? TranslationKeys.updateAvatar.tr : TranslationKeys.updateWallpaper.tr),
          children: [
            SimpleDialogOption(
              onPressed: () => Navigator.of(context).pop(ImageSource.camera),
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
              child: Row(
                children: [
                  const Icon(Icons.camera_alt, size: 28),
                  const SizedBox(width: 16),
                  Text(TranslationKeys.takePhoto.tr, style: const TextStyle(fontSize: 18)),
                ],
              ),
            ),
            SimpleDialogOption(
              onPressed: () => Navigator.of(context).pop(ImageSource.gallery),
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
              child: Row(
                children: [
                  const Icon(Icons.photo_library, size: 28),
                  const SizedBox(width: 16),
                  Text(TranslationKeys.chooseFromGallery.tr, style: const TextStyle(fontSize: 18)),
                ],
              ),
            ),
          ],
        ),
      );
      
      if (source != null && mounted) {
        if (isAvatar) {
          await _pickAndCropAvatar(source: source);
        } else {
          await _pickAndCropBackground(source: source);
        }
      }
    } catch (e) {
      print('Error showing image source dialog: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<File> _getFileFromUrl(String url) async {
    final response = await http.get(Uri.parse(url));
    final bytes = response.bodyBytes;
    final tempDir = await getTemporaryDirectory();
    final file = File('${tempDir.path}/${DateTime.now().millisecondsSinceEpoch}.jpg');
    await file.writeAsBytes(bytes);
    return file;
  }

  // Upload avatar image
  Future<void> _uploadAvatar() async {
    if (_newAvatarFile == null || user == null) return;

    setState(() => _isUploadingAvatar = true);

    try {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('${ApiConstants.apiBase}/profile_update.php'),
      );

      request.fields['userID'] = user!.id;
      request.files.add(
        await http.MultipartFile.fromPath('avatar', _newAvatarFile!.path),
      );

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      try {
        final data = json.decode(response.body);
        if (response.statusCode == 200 && data['responseCode'] == '1') {
          // Refresh user profile
          await AuthService().fetchUserProfile(user!.username);
          if (mounted) {
            setState(() {
              _newAvatarFile = null;
              _isUploadingAvatar = false;
            });
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(data['message'] ?? TranslationKeys.profileUpdateSuccess.tr),
                backgroundColor: Colors.green,
              ),
            );
            // Reload profile data
            await _loadUserProfile();
          }
        } else {
          if (mounted) {
            setState(() => _isUploadingAvatar = false);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(data['message'] ?? TranslationKeys.profileUpdateError.tr),
                backgroundColor: Colors.red,
              ),
            );
          }
        }
      } catch (e) {
        print('Error parsing avatar upload response: $e');
        if (mounted) {
          setState(() => _isUploadingAvatar = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${TranslationKeys.profileUpdateError.tr}: ${response.body}'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      print('Error uploading avatar: $e');
      if (mounted) {
        setState(() => _isUploadingAvatar = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(TranslationKeys.profileUpdateError.tr),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // Upload wallpaper image
  Future<void> _uploadWallpaper() async {
    if (_newBackgroundFile == null || user == null) return;

    setState(() => _isUploadingWallpaper = true);

    try {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('${ApiConstants.apiBase}/profile_update.php'),
      );

      request.fields['userID'] = user!.id;
      request.files.add(
        await http.MultipartFile.fromPath('wallpaper', _newBackgroundFile!.path),
      );

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      try {
        final data = json.decode(response.body);
        if (response.statusCode == 200 && data['responseCode'] == '1') {
          // Refresh user profile
          await AuthService().fetchUserProfile(user!.username);
          if (mounted) {
            setState(() {
              _newBackgroundFile = null;
              _isUploadingWallpaper = false;
            });
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(data['message'] ?? TranslationKeys.profileUpdateSuccess.tr),
                backgroundColor: Colors.green,
              ),
            );
            // Reload profile data
            await _loadUserProfile();
          }
        } else {
          if (mounted) {
            setState(() => _isUploadingWallpaper = false);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(data['message'] ?? TranslationKeys.profileUpdateError.tr),
                backgroundColor: Colors.red,
              ),
            );
          }
        }
      } catch (e) {
        print('Error parsing wallpaper upload response: $e');
        if (mounted) {
          setState(() => _isUploadingWallpaper = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${TranslationKeys.profileUpdateError.tr}: ${response.body}'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      print('Error uploading wallpaper: $e');
      if (mounted) {
        setState(() => _isUploadingWallpaper = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(TranslationKeys.profileUpdateError.tr),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // Update _pickAndCropAvatar to accept source
  Future<void> _pickAndCropAvatar({File? existingFile, ImageSource? source}) async {
    try {
      if (!mounted) return;
      
      File? imageFile;
      if (existingFile != null) {
        imageFile = existingFile;
      } else if (source != null) {
        try {
          final XFile? picked = await _picker.pickImage(
            source: source,
            imageQuality: 85,
          );
          if (picked != null && mounted) {
            imageFile = File(picked.path);
          }
        } catch (e) {
          print('Error picking image: $e');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Error selecting image: ${e.toString()}'),
                backgroundColor: Colors.red,
              ),
            );
          }
          return;
        }
      } else if (profileImage.startsWith('http')) {
        try {
          imageFile = await _getFileFromUrl(profileImage);
        } catch (e) {
          print('Error loading image from URL: $e');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Error loading image: ${e.toString()}'),
                backgroundColor: Colors.red,
              ),
            );
          }
          return;
        }
      }

      if (imageFile != null && mounted) {
        try {
          // Crop the image
          final croppedFile = await ImageCropper().cropImage(
            sourcePath: imageFile.path,
            aspectRatio: const CropAspectRatio(ratioX: 1, ratioY: 1), // Square for avatar
            uiSettings: [
              AndroidUiSettings(
                toolbarTitle: TranslationService().translate(TranslationKeys.cropImage) ?? 'Crop Image',
                toolbarColor: Colors.black,
                toolbarWidgetColor: Colors.white,
                initAspectRatio: CropAspectRatioPreset.square,
                lockAspectRatio: true,
              ),
              IOSUiSettings(
                title: TranslationService().translate(TranslationKeys.cropImage) ?? 'Crop Image',
                aspectRatioLockEnabled: true,
                aspectRatioLockDimensionSwapEnabled: false,
              ),
            ],
          );

          if (croppedFile != null && mounted) {
            setState(() {
              _newAvatarFile = File(croppedFile.path);
              avatarMargin = [0.0, 0.0, 0.0, 0.0]; // Default margins
            });
          }
        } catch (e) {
          print('Error cropping image: $e');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Error cropping image: ${e.toString()}'),
                backgroundColor: Colors.red,
              ),
            );
          }
        }
      }
    } catch (e) {
      print('Error in _pickAndCropAvatar: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error processing image: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // Update _pickAndCropBackground to accept source
  Future<void> _pickAndCropBackground({File? existingFile, ImageSource? source}) async {
    try {
      if (!mounted) return;
      
      File? imageFile;
      if (existingFile != null) {
        imageFile = existingFile;
      } else if (source != null) {
        try {
          final XFile? picked = await _picker.pickImage(
            source: source,
            imageQuality: 85,
          );
          if (picked != null && mounted) {
            imageFile = File(picked.path);
          }
        } catch (e) {
          print('Error picking image: $e');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Error selecting image: ${e.toString()}'),
                backgroundColor: Colors.red,
              ),
            );
          }
          return;
        }
      } else if (backgroundImage.startsWith('http')) {
        try {
          imageFile = await _getFileFromUrl(backgroundImage);
        } catch (e) {
          print('Error loading image from URL: $e');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Error loading image: ${e.toString()}'),
                backgroundColor: Colors.red,
              ),
            );
          }
          return;
        }
      }

      if (imageFile != null && mounted) {
        try {
          // Crop the image (free aspect ratio for wallpaper)
          final croppedFile = await ImageCropper().cropImage(
            sourcePath: imageFile.path,
            aspectRatio: const CropAspectRatio(ratioX: 16, ratioY: 9), // 16:9 for wallpaper
            uiSettings: [
              AndroidUiSettings(
                toolbarTitle: TranslationService().translate(TranslationKeys.cropImage) ?? 'Crop Image',
                toolbarColor: Colors.black,
                toolbarWidgetColor: Colors.white,
                initAspectRatio: CropAspectRatioPreset.ratio16x9,
                lockAspectRatio: false, // Allow free cropping for wallpaper
              ),
              IOSUiSettings(
                title: TranslationService().translate(TranslationKeys.cropImage) ?? 'Crop Image',
                aspectRatioLockEnabled: false, // Allow free cropping for wallpaper
                aspectRatioLockDimensionSwapEnabled: false,
              ),
            ],
          );

          if (croppedFile != null && mounted) {
            setState(() {
              _newBackgroundFile = File(croppedFile.path);
              backgroundMargin = [0.0, 0.0, 0.0, 0.0]; // Default margins
            });
          }
        } catch (e) {
          print('Error cropping image: $e');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Error cropping image: ${e.toString()}'),
                backgroundColor: Colors.red,
              ),
            );
          }
        }
      }
    } catch (e) {
      print('Error in _pickAndCropBackground: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error processing image: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // Removed unused _saveTempFile helper

  // Removed unused _getBackgroundAspectRatio helper

  // Removed unused _changeProfileImage stub

  // Removed unused _changeBackgroundImage stub

  // Note: _savePassword and _savePin are implemented later in the file with HTTP API calls.
  // Earlier implementations removed to avoid duplicates.
  
  // Helper methods for PIN (used by later implementations and initState)
  String? _getPinOptionFromValue(String? pinV) {
    if (pinV == null || pinV.isEmpty || pinV == '0') {
      return 'No PIN';
    }
    final value = int.tryParse(pinV);
    if (value == null) return 'No PIN';
    return '$value digit';
  }

  int _getPinValueFromOption(String? option) {
    if (option == null || option == 'No PIN') return 0;
    if (option == '4 digit') return 4;
    if (option == '6 digit') return 6;
    if (option == '8 digit') return 8;
    return 0;
  }

  // Note: _saveBasicInfo and _saveSecurityQuestions are implemented later in the file
  // with HTTP API calls. Earlier implementations removed to avoid duplicates.

  @override
  Widget build(BuildContext context) {
    final appBarHeight = AppBarConfig.getAppBarHeight(context);
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final transparentColor = isDarkMode ? Colors.white.withValues(alpha: 0.2) : Colors.black.withValues(alpha: 0.3);
    final iconBackgroundColor = isDarkMode ? const Color.fromRGBO(255, 255, 255, 0.20) : const Color.fromRGBO(0, 0, 0, 0.30);

    // Define wallpaper logic safely here
    final String wallpaperUrl = user?.wallpaper ?? '';
    final String avatarUrl = user?.avatar ?? '';
    final bool useDefaultWallpaper = wallpaperUrl.isEmpty || wallpaperUrl == avatarUrl;

    return Scaffold(
      extendBodyBehindAppBar: true,
      extendBody: true,
      appBar: CustomAppBar(
        logoPath: 'assets/images/logo.png',
        onLogoPressed: () {
          Navigator.of(context).pushReplacementNamed('/home');
        },
        onSearchFormToggle: null,
        isSearchFormVisible: false,
      ),
      bottomNavigationBar: Padding(
        padding: EdgeInsets.only(
          bottom: Theme.of(context).platform == TargetPlatform.iOS ? 8.0 : 8.0 + MediaQuery.of(context).padding.bottom,
        ),
        child: CustomBottomNavigationBar(
          onAddPressed: () {},
          notificationButtonKey: _notificationButtonKey,
        ),
      ),
      body: Stack(
        children: [
          const BackgroundGradient(),
          SingleChildScrollView(
            child: Column(
              children: [
                SizedBox(height: appBarHeight + MediaQuery.of(context).padding.top + 20),
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      width: double.infinity,
                      height: 200,
                      child: _newBackgroundFile != null
                          ? Image.file(
                              _newBackgroundFile!,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) {
                                return Image.asset(
                                  'assets/images/background.png',
                                  fit: BoxFit.cover,
                                );
                              },
                            )
                          : useDefaultWallpaper
                              ? Image.asset(
                                  'assets/images/background.png',
                                  fit: BoxFit.cover,
                                )
                              : CachedNetworkImage(
                                  imageUrl: wallpaperUrl,
                                  fit: BoxFit.cover,
                                  httpHeaders: const {},
                                  placeholder: (context, url) => Image.asset(
                                    'assets/images/background.png',
                                    fit: BoxFit.cover,
                                  ),
                                  errorWidget: (context, url, error) {
                                    // Handle all errors including 404 (HttpExceptionWithStatus)
                                    return Image.asset(
                                      'assets/images/background.png',
                                      fit: BoxFit.cover,
                                    );
                                  },
                                ),
                    ),
                    Positioned(
                      top: 12,
                      right: 12,
                      child: Material(
                        type: MaterialType.transparency,
                        child: Row(
                          children: [
                            GestureDetector(
                              onTap: () => _showImageSourceDialog(isAvatar: false),
                              child: CircleAvatar(
                                backgroundColor: iconBackgroundColor,
                                radius: 20,
                                child: Icon(Icons.edit, color: AppColors.getIconColor(context), size: 20),
                              ),
                            ),
                            if (_newBackgroundFile != null || (backgroundImage.isNotEmpty && backgroundImage.startsWith('http'))) ...[
                              const SizedBox(width: 8),
                              GestureDetector(
                                onTap: () {
                                  _pickAndCropBackground(existingFile: _newBackgroundFile);
                                },
                                child: CircleAvatar(
                                  backgroundColor: iconBackgroundColor,
                                  radius: 20,
                                  child: Icon(Icons.crop, color: AppColors.getIconColor(context), size: 20),
                                ),
                              ),
                            ]
                          ],
                        ),
                      ),
                    ),
                    // Save button for wallpaper
                    if (_newBackgroundFile != null)
                      Positioned(
                        bottom: 12,
                        right: 12,
                        child: Material(
                          type: MaterialType.transparency,
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.green.withOpacity(0.9),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: IconButton(
                              icon: _isUploadingWallpaper
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                      ),
                                    )
                                  : const Icon(Icons.check, color: Colors.white, size: 20),
                              onPressed: _isUploadingWallpaper ? null : _uploadWallpaper,
                              tooltip: TranslationKeys.save.tr,
                            ),
                          ),
                        ),
                      ),
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: -48,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          Container(
                            width: 100,
                            height: 100,
                            decoration: BoxDecoration(
                              color: Colors.black,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: AppColors.getIconColor(context), width: 1),
                            ),
                            alignment: Alignment.center,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(16),
                              child: Stack(
                                children: [
                                  _newAvatarFile != null
                                      ? Image.file(
                                          _newAvatarFile!,
                                          width: 100,
                                          height: 100,
                                          fit: BoxFit.cover,
                                          errorBuilder: (context, error, stackTrace) {
                                            // Return default icon on error
                                            return Image.asset(
                                              'assets/images/icon.png',
                                              width: 100,
                                              height: 100,
                                              fit: BoxFit.cover,
                                            );
                                          },
                                        )
                                      : profileImage.startsWith('http')
                                          ? CachedNetworkImage(
                                              imageUrl: profileImage,
                                              width: 100,
                                              height: 100,
                                              fit: BoxFit.cover,
                                              httpHeaders: const {},
                                              placeholder: (context, url) => Image.asset(
                                                'assets/images/icon.png',
                                                width: 100,
                                                height: 100,
                                                fit: BoxFit.cover,
                                              ),
                                              errorWidget: (context, url, error) {
                                                // Handle all errors including 404 (HttpExceptionWithStatus)
                                                return Image.asset(
                                                  'assets/images/icon.png',
                                                  width: 100,
                                                  height: 100,
                                                  fit: BoxFit.cover,
                                                );
                                              },
                                            )
                                          : Image.asset(
                                              profileImage,
                                              width: 100,
                                              height: 100,
                                              fit: BoxFit.cover,
                                            ),
                                  Positioned(
                                    top: 4,
                                    right: 4,
                                    child: Material(
                                      type: MaterialType.transparency,
                                      child: Row(
                                        children: [
                                          GestureDetector(
                                            onTap: () => _showImageSourceDialog(isAvatar: true),
                                            child: CircleAvatar(
                                              backgroundColor: iconBackgroundColor,
                                              radius: 14,
                                              child: Icon(Icons.edit, color: AppColors.getIconColor(context), size: 14),
                                            ),
                                          ),
                                          if (_newAvatarFile != null || (profileImage.isNotEmpty && profileImage.startsWith('http'))) ...[
                                            const SizedBox(width: 4),
                                            GestureDetector(
                                              onTap: () {
                                                _pickAndCropAvatar(existingFile: _newAvatarFile);
                                              },
                                              child: CircleAvatar(
                                                backgroundColor: iconBackgroundColor,
                                                radius: 14,
                                                child: Icon(Icons.crop, color: AppColors.getIconColor(context), size: 14),
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                // Save button for avatar (outside the avatar box)
                if (_newAvatarFile != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          decoration: BoxDecoration(
                            color: Colors.green.withOpacity(0.9),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: IconButton(
                            icon: _isUploadingAvatar
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                    ),
                                  )
                                : const Icon(Icons.check, color: Colors.white, size: 20),
                            onPressed: _isUploadingAvatar ? null : _uploadAvatar,
                            tooltip: TranslationKeys.save.tr,
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 60),
                // Basic Info Section
                _buildExpansionTile(
                  title: TranslationKeys.general,
                  tileColor: transparentColor,
                  children: [
                    ListenableBuilder(
                      listenable: TranslationService(),
                      builder: (context, _) {
                        return TextField(
                          controller: _emailController,
                          focusNode: _emailFocusNode,
                          style: TextStyle(color: AppColors.getTextColor(context)),
                          decoration: InputDecoration(
                            labelText: TranslationKeys.email.tr,
                            labelStyle: TextStyle(color: AppColors.getSecondaryTextColor(context)),
                            enabledBorder: UnderlineInputBorder(
                              borderSide: BorderSide(color: AppColors.getSecondaryTextColor(context).withOpacity(0.3)),
                            ),
                            focusedBorder: UnderlineInputBorder(
                              borderSide: BorderSide(color: AppColors.getTextColor(context)),
                            ),
                          ),
                          onTap: () {
                            // Unfocus other fields to prevent context menu conflicts
                            _unfocusOtherFields(_emailFocusNode);
                          },
                        );
                      },
                    ),
                    const SizedBox(height: 16),
                    ListenableBuilder(
                      listenable: TranslationService(),
                      builder: (context, _) {
                        return TextField(
                          controller: _usernameController,
                          focusNode: _usernameFocusNode,
                          style: TextStyle(color: AppColors.getTextColor(context)),
                          decoration: InputDecoration(
                            labelText: TranslationKeys.username.tr,
                            labelStyle: TextStyle(color: AppColors.getSecondaryTextColor(context)),
                            enabledBorder: UnderlineInputBorder(
                              borderSide: BorderSide(color: AppColors.getSecondaryTextColor(context).withOpacity(0.3)),
                            ),
                            focusedBorder: UnderlineInputBorder(
                              borderSide: BorderSide(color: AppColors.getTextColor(context)),
                            ),
                          ),
                          readOnly: true,
                          onTap: () {
                            _unfocusOtherFields(_usernameFocusNode);
                          },
                        );
                      },
                    ),
                    const SizedBox(height: 16),
                    ListenableBuilder(
                      listenable: TranslationService(),
                      builder: (context, _) {
                        return TextField(
                          controller: _nicknameController,
                          focusNode: _nicknameFocusNode,
                          style: TextStyle(color: AppColors.getTextColor(context)),
                          decoration: InputDecoration(
                            labelText: TranslationKeys.nickname.tr,
                            labelStyle: TextStyle(color: AppColors.getSecondaryTextColor(context)),
                            enabledBorder: UnderlineInputBorder(
                              borderSide: BorderSide(color: AppColors.getSecondaryTextColor(context).withOpacity(0.3)),
                            ),
                            focusedBorder: UnderlineInputBorder(
                              borderSide: BorderSide(color: AppColors.getTextColor(context)),
                            ),
                          ),
                          onTap: () {
                            _unfocusOtherFields(_nicknameFocusNode);
                          },
                        );
                      },
                    ),
                    const SizedBox(height: 16),
                    ListenableBuilder(
                      listenable: TranslationService(),
                      builder: (context, _) {
                        return TextField(
                          controller: _titleController,
                          focusNode: _titleFocusNode,
                          style: TextStyle(color: AppColors.getTextColor(context)),
                          decoration: InputDecoration(
                            labelText: TranslationKeys.title.tr,
                            labelStyle: TextStyle(color: AppColors.getSecondaryTextColor(context)),
                            enabledBorder: UnderlineInputBorder(
                              borderSide: BorderSide(color: AppColors.getSecondaryTextColor(context).withOpacity(0.3)),
                            ),
                            focusedBorder: UnderlineInputBorder(
                              borderSide: BorderSide(color: AppColors.getTextColor(context)),
                            ),
                          ),
                          onTap: () {
                            _unfocusOtherFields(_titleFocusNode);
                          },
                        );
                      },
                    ),
                    const SizedBox(height: 16),
                    ListenableBuilder(
                      listenable: TranslationService(),
                      builder: (context, _) {
                        return TextField(
                          controller: _firstNameController,
                          focusNode: _firstNameFocusNode,
                          style: TextStyle(color: AppColors.getTextColor(context)),
                          decoration: InputDecoration(
                            labelText: TranslationKeys.firstName.tr,
                            labelStyle: TextStyle(color: AppColors.getSecondaryTextColor(context)),
                            enabledBorder: UnderlineInputBorder(
                              borderSide: BorderSide(color: AppColors.getSecondaryTextColor(context).withOpacity(0.3)),
                            ),
                            focusedBorder: UnderlineInputBorder(
                              borderSide: BorderSide(color: AppColors.getTextColor(context)),
                            ),
                          ),
                          onTap: () {
                            _unfocusOtherFields(_firstNameFocusNode);
                          },
                        );
                      },
                    ),
                    const SizedBox(height: 16),
                    ListenableBuilder(
                      listenable: TranslationService(),
                      builder: (context, _) {
                        return TextField(
                          controller: _middleNameController,
                          focusNode: _middleNameFocusNode,
                          style: TextStyle(color: AppColors.getTextColor(context)),
                          decoration: InputDecoration(
                            labelText: TranslationKeys.middleName.tr,
                            labelStyle: TextStyle(color: AppColors.getSecondaryTextColor(context)),
                            enabledBorder: UnderlineInputBorder(
                              borderSide: BorderSide(color: AppColors.getSecondaryTextColor(context).withOpacity(0.3)),
                            ),
                            focusedBorder: UnderlineInputBorder(
                              borderSide: BorderSide(color: AppColors.getTextColor(context)),
                            ),
                          ),
                          onTap: () {
                            _unfocusOtherFields(_middleNameFocusNode);
                          },
                        );
                      },
                    ),
                    const SizedBox(height: 16),
                    ListenableBuilder(
                      listenable: TranslationService(),
                      builder: (context, _) {
                        return TextField(
                          controller: _lastNameController,
                          focusNode: _lastNameFocusNode,
                          style: TextStyle(color: AppColors.getTextColor(context)),
                          decoration: InputDecoration(
                            labelText: TranslationKeys.lastName.tr,
                            labelStyle: TextStyle(color: AppColors.getSecondaryTextColor(context)),
                            enabledBorder: UnderlineInputBorder(
                              borderSide: BorderSide(color: AppColors.getSecondaryTextColor(context).withOpacity(0.3)),
                            ),
                            focusedBorder: UnderlineInputBorder(
                              borderSide: BorderSide(color: AppColors.getTextColor(context)),
                            ),
                          ),
                          onTap: () {
                            _unfocusOtherFields(_lastNameFocusNode);
                          },
                        );
                      },
                    ),
                    const SizedBox(height: 16),
                    ListenableBuilder(
                      listenable: TranslationService(),
                      builder: (context, _) {
                        return InkWell(
                          onTap: () async {
                            final DateTime? picked = await showDatePicker(
                              context: context,
                              initialDate: _birthDate ?? DateTime.now().subtract(const Duration(days: 365 * 18)),
                              firstDate: DateTime(1960),
                              lastDate: DateTime.now().subtract(const Duration(days: 365 * 15)),
                            );
                            if (picked != null) {
                              setState(() {
                                _birthDate = picked;
                              });
                            }
                          },
                          child: InputDecorator(
                            decoration: InputDecoration(
                              labelText: TranslationKeys.dateOfBirth.tr,
                              labelStyle: TextStyle(color: AppColors.getSecondaryTextColor(context)),
                              enabledBorder: UnderlineInputBorder(
                                borderSide: BorderSide(color: AppColors.getSecondaryTextColor(context).withOpacity(0.3)),
                              ),
                              focusedBorder: UnderlineInputBorder(
                                borderSide: BorderSide(color: AppColors.getTextColor(context)),
                              ),
                              suffixIcon: Icon(Icons.calendar_today, color: AppColors.getIconColor(context)),
                            ),
                            child: Text(
                              _birthDate != null
                                  ? '${_birthDate!.year}-${_birthDate!.month.toString().padLeft(2, '0')}-${_birthDate!.day.toString().padLeft(2, '0')}'
                                  : TranslationKeys.selectDate.tr,
                              style: TextStyle(color: AppColors.getTextColor(context)),
                            ),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 16),
                    ListenableBuilder(
                      listenable: TranslationService(),
                      builder: (context, _) {
                        return TextField(
                          controller: _bioController,
                          focusNode: _bioFocusNode,
                          maxLines: 3,
                          style: TextStyle(color: AppColors.getTextColor(context)),
                          decoration: InputDecoration(
                            labelText: TranslationKeys.bio.tr,
                            labelStyle: TextStyle(color: AppColors.getSecondaryTextColor(context)),
                            enabledBorder: UnderlineInputBorder(
                              borderSide: BorderSide(color: AppColors.getSecondaryTextColor(context).withOpacity(0.3)),
                            ),
                            focusedBorder: UnderlineInputBorder(
                              borderSide: BorderSide(color: AppColors.getTextColor(context)),
                            ),
                          ),
                          onTap: () {
                            _unfocusOtherFields(_bioFocusNode);
                          },
                        );
                      },
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _saveBasicInfo,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue,
                          foregroundColor: AppColors.getTextColor(context),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: TranslatedText(TranslationKeys.saveChanges),
                      ),
                    ),
                  ],
                ),
                // Password Section
                _buildExpansionTile(
                  title: TranslationKeys.changePassword,
                  tileColor: transparentColor,
                  children: [
                    TextField(
                      controller: _oldPasswordController,
                      focusNode: _oldPasswordFocusNode,
                      obscureText: true,
                      style: TextStyle(color: AppColors.getTextColor(context)),
                      decoration: InputDecoration(
                        labelText: TranslationKeys.passwordCurrent.tr,
                        labelStyle: TextStyle(color: AppColors.getSecondaryTextColor(context)),
                        enabledBorder: UnderlineInputBorder(
                          borderSide: BorderSide(color: AppColors.getSecondaryTextColor(context).withOpacity(0.3)),
                        ),
                        focusedBorder: UnderlineInputBorder(
                          borderSide: BorderSide(color: AppColors.getTextColor(context)),
                        ),
                      ),
                      onTap: () {
                        _unfocusOtherFields(_oldPasswordFocusNode);
                      },
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _newPasswordController,
                      focusNode: _newPasswordFocusNode,
                      obscureText: true,
                      style: TextStyle(color: AppColors.getTextColor(context)),
                      decoration: InputDecoration(
                        labelText: TranslationKeys.newPassword.tr,
                        labelStyle: TextStyle(color: AppColors.getSecondaryTextColor(context)),
                        enabledBorder: UnderlineInputBorder(
                          borderSide: BorderSide(color: AppColors.getSecondaryTextColor(context).withOpacity(0.3)),
                        ),
                        focusedBorder: UnderlineInputBorder(
                          borderSide: BorderSide(color: AppColors.getTextColor(context)),
                        ),
                      ),
                      onTap: () {
                        _unfocusOtherFields(_newPasswordFocusNode);
                      },
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _confirmPasswordController,
                      focusNode: _confirmPasswordFocusNode,
                      obscureText: true,
                      style: TextStyle(color: AppColors.getTextColor(context)),
                      decoration: InputDecoration(
                        labelText: TranslationKeys.confirmNewPassword.tr,
                        labelStyle: TextStyle(color: AppColors.getSecondaryTextColor(context)),
                        enabledBorder: UnderlineInputBorder(
                          borderSide: BorderSide(color: AppColors.getSecondaryTextColor(context).withOpacity(0.3)),
                        ),
                        focusedBorder: UnderlineInputBorder(
                          borderSide: BorderSide(color: AppColors.getTextColor(context)),
                        ),
                      ),
                      onTap: () {
                        _unfocusOtherFields(_confirmPasswordFocusNode);
                      },
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _savePassword,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue,
                          foregroundColor: AppColors.getTextColor(context),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: TranslatedText(TranslationKeys.changePassword),
                      ),
                    ),
                  ],
                ),
                // PIN Section
                _buildExpansionTile(
                  title: TranslationKeys.pinCode,
                  tileColor: transparentColor,
                  children: [
                    DropdownButtonFormField<String>(
                      initialValue: _selectedPinOption,
                      items: _pinOptions.map((option) {
                        return DropdownMenuItem<String>(
                          value: option,
                          child: Text(option, style: TextStyle(color: AppColors.getTextColor(context))),
                        );
                      }).toList(),
                      onChanged: (value) {
                        setState(() {
                          _selectedPinOption = value;
                        });
                      },
                      decoration: InputDecoration(
                        labelText: TranslationKeys.pinCode,
                        labelStyle: TextStyle(color: AppColors.getSecondaryTextColor(context)),
                        enabledBorder: UnderlineInputBorder(
                          borderSide: BorderSide(color: AppColors.getSecondaryTextColor(context).withOpacity(0.3)),
                        ),
                        focusedBorder: UnderlineInputBorder(
                          borderSide: BorderSide(color: AppColors.getTextColor(context)),
                        ),
                      ),
                      dropdownColor: AppColors.getCardBackgroundColor(context),
                    ),
                    if (_selectedPinOption != null && _selectedPinOption != 'No PIN') ...[
                      const SizedBox(height: 16),
                      if (user?.pin != null && user!.pin.isNotEmpty) ...[
                        TextField(
                          controller: _currentPinController,
                          focusNode: _currentPinFocusNode,
                          obscureText: true,
                          style: TextStyle(color: AppColors.getTextColor(context)),
                          decoration: InputDecoration(
                            labelText: TranslationKeys.pinCodeCurrent.tr,
                            labelStyle: TextStyle(color: AppColors.getSecondaryTextColor(context)),
                            enabledBorder: UnderlineInputBorder(
                              borderSide: BorderSide(color: AppColors.getSecondaryTextColor(context).withOpacity(0.3)),
                            ),
                            focusedBorder: UnderlineInputBorder(
                              borderSide: BorderSide(color: AppColors.getTextColor(context)),
                            ),
                          ),
                          onTap: () {
                            _unfocusOtherFields(_currentPinFocusNode);
                          },
                        ),
                        const SizedBox(height: 16),
                      ],
                      TextField(
                        controller: _newPinController,
                        focusNode: _newPinFocusNode,
                        obscureText: true,
                        style: TextStyle(color: AppColors.getTextColor(context)),
                        decoration: InputDecoration(
                          labelText: TranslationKeys.pinCodeNew.tr,
                          labelStyle: TextStyle(color: AppColors.getSecondaryTextColor(context)),
                          enabledBorder: UnderlineInputBorder(
                            borderSide: BorderSide(color: AppColors.getSecondaryTextColor(context).withOpacity(0.3)),
                          ),
                          focusedBorder: UnderlineInputBorder(
                            borderSide: BorderSide(color: AppColors.getTextColor(context)),
                          ),
                        ),
                        onTap: () {
                          _unfocusOtherFields(_newPinFocusNode);
                        },
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _confirmPinController,
                        focusNode: _confirmPinFocusNode,
                        obscureText: true,
                        style: TextStyle(color: AppColors.getTextColor(context)),
                        decoration: InputDecoration(
                          labelText: TranslationKeys.confirmPinCode.tr,
                          labelStyle: TextStyle(color: AppColors.getSecondaryTextColor(context)),
                          enabledBorder: UnderlineInputBorder(
                            borderSide: BorderSide(color: AppColors.getSecondaryTextColor(context).withOpacity(0.3)),
                          ),
                          focusedBorder: UnderlineInputBorder(
                            borderSide: BorderSide(color: AppColors.getTextColor(context)),
                          ),
                        ),
                        onTap: () {
                          _unfocusOtherFields(_confirmPinFocusNode);
                        },
                      ),
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _savePin,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue,
                            foregroundColor: AppColors.getTextColor(context),
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          child: TranslatedText(TranslationKeys.savePinCode),
                        ),
                      ),
                    ],
                  ],
                ),
                // Security Questions Section
                _buildExpansionTile(
                  title: TranslationKeys.securityQuestions,
                  tileColor: transparentColor,
                  children: [
                    TextField(
                      controller: _secQOneController,
                      focusNode: _secQOneFocusNode,
                      style: TextStyle(color: AppColors.getTextColor(context)),
                      decoration: InputDecoration(
                        labelText: TranslationKeys.securityQuestion1.tr,
                        labelStyle: TextStyle(color: AppColors.getSecondaryTextColor(context)),
                        enabledBorder: UnderlineInputBorder(
                          borderSide: BorderSide(color: AppColors.getSecondaryTextColor(context).withOpacity(0.3)),
                        ),
                        focusedBorder: UnderlineInputBorder(
                          borderSide: BorderSide(color: AppColors.getTextColor(context)),
                        ),
                      ),
                      onTap: () {
                        _unfocusOtherFields(_secQOneFocusNode);
                      },
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _secAOneController,
                      focusNode: _secAOneFocusNode,
                      style: TextStyle(color: AppColors.getTextColor(context)),
                      decoration: InputDecoration(
                        labelText: TranslationKeys.answer1.tr,
                        labelStyle: TextStyle(color: AppColors.getSecondaryTextColor(context)),
                        enabledBorder: UnderlineInputBorder(
                          borderSide: BorderSide(color: AppColors.getSecondaryTextColor(context).withOpacity(0.3)),
                        ),
                        focusedBorder: UnderlineInputBorder(
                          borderSide: BorderSide(color: AppColors.getTextColor(context)),
                        ),
                      ),
                      onTap: () {
                        _unfocusOtherFields(_secAOneFocusNode);
                      },
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _secQTwoController,
                      focusNode: _secQTwoFocusNode,
                      style: TextStyle(color: AppColors.getTextColor(context)),
                      decoration: InputDecoration(
                        labelText: TranslationKeys.securityQuestion2.tr,
                        labelStyle: TextStyle(color: AppColors.getSecondaryTextColor(context)),
                        enabledBorder: UnderlineInputBorder(
                          borderSide: BorderSide(color: AppColors.getSecondaryTextColor(context).withOpacity(0.3)),
                        ),
                        focusedBorder: UnderlineInputBorder(
                          borderSide: BorderSide(color: AppColors.getTextColor(context)),
                        ),
                      ),
                      onTap: () {
                        _unfocusOtherFields(_secQTwoFocusNode);
                      },
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _secATwoController,
                      focusNode: _secATwoFocusNode,
                      style: TextStyle(color: AppColors.getTextColor(context)),
                      decoration: InputDecoration(
                        labelText: TranslationKeys.answer2.tr,
                        labelStyle: TextStyle(color: AppColors.getSecondaryTextColor(context)),
                        enabledBorder: UnderlineInputBorder(
                          borderSide: BorderSide(color: AppColors.getSecondaryTextColor(context).withOpacity(0.3)),
                        ),
                        focusedBorder: UnderlineInputBorder(
                          borderSide: BorderSide(color: AppColors.getTextColor(context)),
                        ),
                      ),
                      onTap: () {
                        _unfocusOtherFields(_secATwoFocusNode);
                      },
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _saveSecurityQuestions,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue,
                          foregroundColor: AppColors.getTextColor(context),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: TranslatedText(TranslationKeys.saveSecurityQuestions),
                      ),
                    ),
                  ],
                ),
                // Settings Section
                _buildExpansionTile(
                  title: TranslationKeys.preferences,
                  tileColor: transparentColor,
                  children: [
                    SwitchListTile(
                      title: TranslatedText(
                        TranslationKeys.enableNotifications,
                        style: TextStyle(color: AppColors.getTextColor(context)),
                      ),
                      value: notificationsEnabled,
                      onChanged: (bool value) async {
                        setState(() {
                          notificationsEnabled = value;
                        });
                        // Note: Notifications preference is stored locally
                        // If you want to sync with server, implement API call here
                      },
                      activeThumbColor: Colors.blue,
                    ),
                    SwitchListTile(
                      title: TranslatedText(
                        TranslationKeys.privateProfile,
                        style: TextStyle(color: AppColors.getTextColor(context)),
                      ),
                      value: isPrivate,
                      onChanged: (bool value) async {
                        setState(() {
                          isPrivate = value;
                        });
                        await _saveVisibilitySettings();
                      },
                      activeThumbColor: Colors.blue,
                    ),
                    SwitchListTile(
                      title: TranslatedText(
                        TranslationKeys.biometricLock,
                        style: TextStyle(color: AppColors.getTextColor(context)),
                      ),
                      value: _biometricEnabled,
                      onChanged: (bool value) async {
                        if (value) {
                          final didAuthenticate = await LocalAuthService.authenticate();
                          if (didAuthenticate) {
                            await LocalAuthService.setBiometricEnabled(true);
                            setState(() {
                              _biometricEnabled = true;
                            });
                          }
                        } else {
                          await LocalAuthService.setBiometricEnabled(false);
                          setState(() {
                            _biometricEnabled = false;
                          });
                        }
                      },
                      activeThumbColor: Colors.blue,
                    ),
                  ],
                ),
                // Appearance Section
                Consumer<ThemeService>(
                  builder: (context, themeService, child) {
                    return _buildExpansionTile(
                      title: TranslationKeys.appearance,
                      tileColor: transparentColor,
                      children: [
                        ListTile(
                          title: TranslatedText(
                            TranslationKeys.themeMode,
                            style: TextStyle(color: AppColors.getTextColor(context)),
                          ),
                          subtitle: Text(
                            themeService.themeModeString,
                            style: TextStyle(color: AppColors.getSecondaryTextColor(context)),
                          ),
                          trailing: Icon(
                            Icons.palette,
                            color: AppColors.getIconColor(context),
                          ),
                          onTap: () {
                            _showThemeModeDialog(context, themeService);
                          },
                        ),
                      ],
                    );
                  },
                ),
                // Language Section
                ListenableBuilder(
                  listenable: TranslationService(),
                  builder: (context, _) {
                    return _buildExpansionTile(
                      title: TranslationKeys.language,
                      tileColor: transparentColor,
                      children: [
                        _buildLanguageDropdown(context),
                      ],
                    );
                  },
                ),
                // Cache Management Section
                _buildExpansionTile(
                  title: TranslationKeys.cache,
                  tileColor: transparentColor,
                  children: [
                    _buildCacheManagementSection(context),
                  ],
                ),
                // IP History Section
                _buildExpansionTile(
                  title: TranslationKeys.ipHistory,
                  tileColor: transparentColor,
                  children: [
                    _buildIpHistorySection(context),
                  ],
                ),
                // About Skybyn Section
                _buildExpansionTile(
                  title: TranslationKeys.about,
                  tileColor: transparentColor,
                  children: [
                    _buildAboutSection(context),
                  ],
                ),
                const SizedBox(height: 125),
              ],
            ),
          ),
          // Search form removed - not needed in settings screen
        ],
      ),
    );
  }

  Widget _buildExpansionTile({
    required String title,
    required List<Widget> children,
    required Color tileColor,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: tileColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          title: TranslatedText(
            title,
            style: TextStyle(
              color: AppColors.getTextColor(context),
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          iconColor: AppColors.getIconColor(context),
          collapsedIconColor: AppColors.getIconColor(context),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          children: children,
        ),
      ),
    );
  }

  // Removed unused _buildField helper

  // Removed unused _buildPasswordField helper

  void _showThemeModeDialog(BuildContext context, ThemeService themeService) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: Colors.grey[900],
          title: Text(
            TranslationKeys.chooseThemeMode.tr,
            style: TextStyle(color: AppColors.getTextColor(context)),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              RadioListTile<ThemeMode>(
                title: Text(
                  TranslationKeys.systemRecommended.tr,
                  style: TextStyle(color: AppColors.getTextColor(context)),
                ),
                subtitle: Text(
                  TranslationKeys.automaticallyFollowDeviceTheme.tr,
                  style: TextStyle(color: AppColors.getSecondaryTextColor(context)),
                ),
                value: ThemeMode.system,
                groupValue: themeService.themeMode,
                onChanged: (ThemeMode? value) async {
                  if (value != null) {
                    await themeService.setThemeMode(value);
                    Navigator.of(context).pop();
                  }
                },
                activeColor: Colors.blue,
              ),
              RadioListTile<ThemeMode>(
                title: Text(
                  TranslationKeys.light.tr,
                  style: TextStyle(color: AppColors.getTextColor(context)),
                ),
                subtitle: Text(
                  TranslationKeys.alwaysUseLightTheme.tr,
                  style: TextStyle(color: AppColors.getSecondaryTextColor(context)),
                ),
                value: ThemeMode.light,
                groupValue: themeService.themeMode,
                onChanged: (ThemeMode? value) async {
                  if (value != null) {
                    await themeService.setThemeMode(value);
                    Navigator.of(context).pop();
                  }
                },
                activeColor: Colors.blue,
              ),
              RadioListTile<ThemeMode>(
                title: Text(
                  TranslationKeys.dark.tr,
                  style: TextStyle(color: AppColors.getTextColor(context)),
                ),
                subtitle: Text(
                  TranslationKeys.alwaysUseDarkTheme.tr,
                  style: TextStyle(color: AppColors.getSecondaryTextColor(context)),
                ),
                value: ThemeMode.dark,
                groupValue: themeService.themeMode,
                onChanged: (ThemeMode? value) async {
                  if (value != null) {
                    await themeService.setThemeMode(value);
                    Navigator.of(context).pop();
                  }
                },
                activeColor: Colors.blue,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(
                TranslationKeys.cancel.tr,
                style: TextStyle(color: AppColors.getSecondaryTextColor(context)),
              ),
            ),
          ],
        );
      },
    );
  }

  // Helper method to build a reactive TextField with translated label
  Widget _buildReactiveTextField({
    required TextEditingController controller,
    required FocusNode focusNode,
    required String labelKey,
    bool obscureText = false,
    bool readOnly = false,
    VoidCallback? onTap,
  }) {
    return ListenableBuilder(
      listenable: TranslationService(),
      builder: (context, _) {
        return TextField(
          controller: controller,
          focusNode: focusNode,
          obscureText: obscureText,
          readOnly: readOnly,
          style: TextStyle(color: AppColors.getTextColor(context)),
          decoration: InputDecoration(
            labelText: TranslationService().translate(labelKey),
            labelStyle: TextStyle(color: AppColors.getSecondaryTextColor(context)),
            enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: AppColors.getSecondaryTextColor(context).withOpacity(0.3)),
            ),
            focusedBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: AppColors.getTextColor(context)),
            ),
          ),
          onTap: onTap ?? () => _unfocusOtherFields(focusNode),
        );
      },
    );
  }

  // Helper method to unfocus other fields to prevent context menu conflicts
  void _unfocusOtherFields(FocusNode currentFocusNode) {
    final allFocusNodes = [
      _emailFocusNode,
      _usernameFocusNode,
      _nicknameFocusNode,
      _firstNameFocusNode,
      _middleNameFocusNode,
      _lastNameFocusNode,
      _titleFocusNode,
      _bioFocusNode,
      _oldPasswordFocusNode,
      _newPasswordFocusNode,
      _confirmPasswordFocusNode,
      _currentPinFocusNode,
      _newPinFocusNode,
      _confirmPinFocusNode,
      _secQOneFocusNode,
      _secAOneFocusNode,
      _secQTwoFocusNode,
      _secATwoFocusNode,
    ];

    for (final focusNode in allFocusNodes) {
      if (focusNode != currentFocusNode && focusNode.hasFocus) {
        focusNode.unfocus();
      }
    }
  }

  Widget _buildLanguageDropdown(BuildContext context) {
    final translationService = TranslationService();

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.7),
            borderRadius: BorderRadius.circular(8),
          ),
          child: ListenableBuilder(
            listenable: translationService,
            builder: (context, child) {
              return DropdownButtonFormField<String>(
                initialValue: translationService.currentLanguage,
                items: TranslationService.supportedLanguages.map((languageCode) {
                  final languageName = translationService.getLanguageName(languageCode);
                  final flagEmoji = _getFlagEmoji(languageCode);
                  return DropdownMenuItem<String>(
                    value: languageCode,
                    child: Row(
                      children: [
                        if (flagEmoji != null) ...[
                          Text(
                            flagEmoji,
                            style: const TextStyle(fontSize: 20),
                          ),
                          const SizedBox(width: 8),
                        ],
                        Text(
                          languageName,
                          style: TextStyle(color: AppColors.getTextColor(context)),
                        ),
                      ],
                    ),
                  );
                }).toList(),
                onChanged: (String? value) async {
                  if (value != null) {
                    await translationService.setLanguage(value);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: const TranslatedText(
                          TranslationKeys.languageChanged,
                          fallback: 'Language changed successfully!',
                        ),
                        backgroundColor: Colors.green,
                        action: SnackBarAction(
                          label: TranslationKeys.ok.tr,
                          onPressed: () {
                            ScaffoldMessenger.of(context).hideCurrentSnackBar();
                          },
                        ),
                      ),
                    );
                  }
                },
                decoration: InputDecoration(
                  labelText: TranslationKeys.language.tr,
                  labelStyle: TextStyle(color: AppColors.getSecondaryTextColor(context)),
                  enabledBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: AppColors.getSecondaryTextColor(context).withOpacity(0.3)),
                  ),
                  focusedBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: AppColors.getTextColor(context)),
                  ),
                  filled: true,
                  fillColor: Colors.transparent,
                ),
                dropdownColor: Colors.black.withValues(alpha: 0.85),
              );
            },
          ),
        ),
      ),
    );
  }

  // Get flag emoji for each language
  String? _getFlagEmoji(String languageCode) {
    switch (languageCode) {
      case 'en':
        return '🇬🇧'; // English - UK flag
      case 'no':
        return '🇳🇴'; // Norwegian
      case 'dk':
        return '🇩🇰'; // Danish
      case 'se':
        return '🇸🇪'; // Swedish
      case 'de':
        return '🇩🇪'; // German
      case 'fr':
        return '🇫🇷'; // French
      case 'pl':
        return '🇵🇱'; // Polish
      case 'es':
        return '🇪🇸'; // Spanish
      case 'it':
        return '🇮🇹'; // Italian
      case 'pt':
        return '🇵🇹'; // Portuguese
      case 'nl':
        return '🇳🇱'; // Dutch
      case 'fi':
        return '🇫🇮'; // Finnish
      default:
        return null;
    }
  }

  Widget _buildAboutSection(BuildContext context) {
    return FutureBuilder<PackageInfo>(
      future: PackageInfo.fromPlatform(),
      builder: (context, snapshot) {
        final version = snapshot.data?.version ?? 'Unknown';
        final buildNumber = snapshot.data?.buildNumber ?? 'Unknown';
        
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Skybyn is a social networking platform that connects people from around the world. Share your moments, connect with friends, and discover new communities.',
              style: TextStyle(
                color: AppColors.getTextColor(context),
                fontSize: 14,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 16),
            if (snapshot.hasData) ...[
              Row(
                children: [
                  Text(
                    '${TranslationKeys.version.tr}: ',
                    style: TextStyle(
                      color: AppColors.getSecondaryTextColor(context),
                      fontSize: 14,
                    ),
                  ),
                  Text(
                    version,
                    style: TextStyle(
                      color: AppColors.getTextColor(context),
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Text(
                    '${TranslationKeys.buildNumber.tr}: ',
                    style: TextStyle(
                      color: AppColors.getSecondaryTextColor(context),
                      fontSize: 14,
                    ),
                  ),
                  Text(
                    buildNumber,
                    style: TextStyle(
                      color: AppColors.getTextColor(context),
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
            ],
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isCheckingForUpdates ? null : () {
                  print('🔘 [SettingsScreen] Button onPressed called');
                  _checkForUpdates();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: AppColors.getTextColor(context),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: _isCheckingForUpdates
                    ? Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            _updateCheckStatus.isNotEmpty
                                ? _updateCheckStatus
                                : TranslationKeys.checkingForUpdates.tr,
                            style: const TextStyle(color: Colors.white),
                          ),
                        ],
                      )
                    : TranslatedText(TranslationKeys.checkForUpdates),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _checkForUpdates() async {
    print('🔍 [SettingsScreen] Check for updates button clicked');
    
    // Skip app update checks in debug mode
    if (kDebugMode) {
      print('⚠️ [SettingsScreen] Debug mode detected');
      if (mounted) {
        setState(() {
          _updateCheckStatus = 'Update check disabled in debug mode';
          _isCheckingForUpdates = false;
        });
        // Reset status after 3 seconds
        Future.delayed(const Duration(seconds: 3), () {
          if (mounted) {
            setState(() {
              _updateCheckStatus = '';
            });
          }
        });
      }
      return;
    }

    print('✅ [SettingsScreen] Proceeding with update check');
    
    final translationService = TranslationService();

    if (!Platform.isAndroid) {
      print('⚠️ [SettingsScreen] Not Android platform');
      if (mounted) {
        setState(() {
          _updateCheckStatus = translationService.translate('auto_updates_only_android');
          _isCheckingForUpdates = false;
        });
        // Reset status after 3 seconds
        Future.delayed(const Duration(seconds: 3), () {
          if (mounted) {
            setState(() {
              _updateCheckStatus = '';
            });
          }
        });
      }
      return;
    }

    // Prevent multiple dialogs from showing at once
    if (AutoUpdateService.isDialogShowing) {
      print('⚠️ [SettingsScreen] Update dialog already showing, skipping...');
      if (mounted) {
        setState(() {
          _updateCheckStatus = 'Update check already in progress';
          _isCheckingForUpdates = false;
        });
        // Reset status after 2 seconds
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) {
            setState(() {
              _updateCheckStatus = '';
            });
          }
        });
      }
      return;
    }

    // Set initial status
    if (mounted) {
      setState(() {
        _isCheckingForUpdates = true;
        _updateCheckStatus = translationService.translate('checking_for_updates') ?? 'Checking for updates...';
      });
    }

    try {
      print('📡 [SettingsScreen] Calling AutoUpdateService.checkForUpdates()');
      final updateInfo = await AutoUpdateService.checkForUpdates();
      print('📡 [SettingsScreen] Update check completed. Update available: ${updateInfo?.isAvailable ?? false}');

      if (mounted) {
        if (updateInfo != null && updateInfo.isAvailable) {
          // Update available
          setState(() {
            _updateCheckStatus = 'Update available!';
            _isCheckingForUpdates = false;
          });
          
          // Show update dialog if not already showing
          if (!AutoUpdateService.isDialogShowing) {
            // Mark dialog as showing immediately to prevent duplicates
            AutoUpdateService.setDialogShowing(true);
            
            // Get current version
            final packageInfo = await PackageInfo.fromPlatform();
            final currentVersion = packageInfo.version;
            
            // Mark this version as shown (so we don't spam the user)
            await AutoUpdateService.markUpdateShownForVersion(updateInfo.version);
            
            await showDialog(
              context: context,
              barrierDismissible: false,
              builder: (context) => UpdateDialog(
                currentVersion: currentVersion,
                latestVersion: updateInfo.version,
                releaseNotes: updateInfo.releaseNotes,
                downloadUrl: updateInfo.downloadUrl,
              ),
            ).then((_) {
              // Dialog closed, mark as not showing
              AutoUpdateService.setDialogShowing(false);
              // Reset button status after dialog closes
              if (mounted) {
                setState(() {
                  _updateCheckStatus = '';
                });
              }
            });
          }
        } else {
          // No update available
          setState(() {
            _updateCheckStatus = translationService.translate('no_updates_available') ?? 'You are using the latest version';
            _isCheckingForUpdates = false;
          });
          
          // Reset status after 3 seconds
          Future.delayed(const Duration(seconds: 3), () {
            if (mounted) {
              setState(() {
                _updateCheckStatus = '';
              });
            }
          });
        }
      }
    } catch (e, stackTrace) {
      print('❌ [SettingsScreen] Error checking for updates: $e');
      print('❌ [SettingsScreen] Stack trace: $stackTrace');
      
      // Update button status with error
      if (mounted) {
        setState(() {
          _updateCheckStatus = translationService.translate('error_checking_updates') ?? 'Error checking for updates';
          _isCheckingForUpdates = false;
        });
        
        // Reset status after 3 seconds
        Future.delayed(const Duration(seconds: 3), () {
          if (mounted) {
            setState(() {
              _updateCheckStatus = '';
            });
          }
        });
      }
    }
  }

  // Load IP History
  Future<void> _loadIpHistory() async {
    if (user == null) return;
    
    setState(() {
      _isLoadingIpHistory = true;
    });

    try {
      final response = await http.post(
        Uri.parse('${ApiConstants.apiBase}/profile_ip_history.php'),
        body: {
          'userID': user!.id,
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['responseCode'] == '1' && data['data'] != null) {
          setState(() {
            _ipHistory = List<Map<String, dynamic>>.from(data['data']);
            _isLoadingIpHistory = false;
          });
        } else {
          setState(() {
            _isLoadingIpHistory = false;
          });
        }
      } else {
        setState(() {
          _isLoadingIpHistory = false;
        });
      }
    } catch (e) {
      print('Error loading IP history: $e');
      setState(() {
        _isLoadingIpHistory = false;
      });
    }
  }

  // Build IP History Section
  Widget _buildIpHistorySection(BuildContext context) {
    if (_isLoadingIpHistory) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(16.0),
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (_ipHistory.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(16.0),
        child: Text(
          TranslationKeys.noResultsFound.tr,
          style: TextStyle(color: AppColors.getSecondaryTextColor(context)),
        ),
      );
    }

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _ipHistory.length,
      itemBuilder: (context, index) {
        final ipEntry = _ipHistory[index];
        final ip = ipEntry['ip'] ?? 'Unknown';
        final timestamp = ipEntry['date'] ?? 0;
        final date = DateTime.fromMillisecondsSinceEpoch(timestamp * 1000);
        final dateStr = '${date.day}/${date.month}/${date.year} ${date.hour}:${date.minute.toString().padLeft(2, '0')}';

        return ListTile(
          title: Text(
            ip,
            style: TextStyle(color: AppColors.getTextColor(context)),
          ),
          subtitle: Text(
            dateStr,
            style: TextStyle(color: AppColors.getSecondaryTextColor(context)),
          ),
        );
      },
    );
  }

  // Save Basic Info
  Future<void> _saveBasicInfo() async {
    if (user == null) return;

    try {
      final Map<String, String> body = {
        'userID': user!.id,
        'email': _emailController.text.trim(),
        'nickname': _nicknameController.text.trim(),
        'title': _titleController.text.trim(),
        'first_name': _firstNameController.text.trim(),
        'middle_name': _middleNameController.text.trim(),
        'last_name': _lastNameController.text.trim(),
        'bio': _bioController.text.trim(),
      };

      if (_birthDate != null) {
        body['birth_date'] = '${_birthDate!.year}-${_birthDate!.month.toString().padLeft(2, '0')}-${_birthDate!.day.toString().padLeft(2, '0')}';
      }

      final response = await http.post(
        Uri.parse('${ApiConstants.apiBase}/profile_update.php'),
        body: body,
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['responseCode'] == '1') {
          // Update email separately if changed
          if (_emailController.text.trim() != user!.email) {
            await http.post(
              Uri.parse('${ApiConstants.apiBase}/profile_email_update.php'),
              body: {
                'userID': user!.id,
                'new_email': _emailController.text.trim(),
              },
            );
          }

          // Refresh user profile
          await AuthService().fetchUserProfile(user!.username);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(data['message'] ?? TranslationKeys.profileUpdateSuccess.tr),
                backgroundColor: Colors.green,
              ),
            );
          }
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(data['message'] ?? TranslationKeys.profileUpdateError.tr),
                backgroundColor: Colors.red,
              ),
            );
          }
        }
      }
    } catch (e) {
      print('Error saving basic info: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(TranslationKeys.profileUpdateError.tr),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // Save Password
  Future<void> _savePassword() async {
    if (user == null) return;

    if (_newPasswordController.text != _confirmPasswordController.text) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(TranslationKeys.passwordsDoNotMatch.tr),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    try {
      final response = await http.post(
        Uri.parse('${ApiConstants.apiBase}/profile_password.php'),
        body: {
          'userID': user!.id,
          'old_pw': _oldPasswordController.text,
          'new_pw': _newPasswordController.text,
          'cnew_pw': _confirmPasswordController.text,
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(data['message'] ?? ''),
              backgroundColor: data['responseCode'] == '1' ? Colors.green : Colors.red,
            ),
          );
        }

        if (data['responseCode'] == '1') {
          _oldPasswordController.clear();
          _newPasswordController.clear();
          _confirmPasswordController.clear();
        }
      }
    } catch (e) {
      print('Error saving password: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(TranslationKeys.errorOccurred.tr),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // Save PIN
  Future<void> _savePin() async {
    if (user == null) return;

    final pinv = _getPinValueFromOption(_selectedPinOption);
    
    if (pinv > 0) {
      if (_newPinController.text != _confirmPinController.text) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(TranslationKeys.pinsDoNotMatch.tr),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      if (_newPinController.text.length != pinv) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('PIN must be $pinv digits'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }
    }

    try {
      final Map<String, String> body = {
        'userID': user!.id,
        'pinv': pinv.toString(),
      };

      if (pinv > 0) {
        body['pin'] = _newPinController.text;
        body['cpin'] = _confirmPinController.text;
        if (user!.pinV.isNotEmpty && int.tryParse(user!.pinV) != null && int.parse(user!.pinV) > 0) {
          body['current_pin'] = _currentPinController.text;
        }
      }

      final response = await http.post(
        Uri.parse('${ApiConstants.apiBase}/profile_pin.php'),
        body: body,
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(data['message'] ?? ''),
              backgroundColor: data['responseCode'] == '1' ? Colors.green : Colors.red,
            ),
          );
        }

        if (data['responseCode'] == '1') {
          _currentPinController.clear();
          _newPinController.clear();
          _confirmPinController.clear();
          // Refresh user profile
          await AuthService().fetchUserProfile(user!.username);
        }
      }
    } catch (e) {
      print('Error saving PIN: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(TranslationKeys.errorOccurred.tr),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // Save Security Questions
  Future<void> _saveSecurityQuestions() async {
    if (user == null) return;

    if (_secQOneController.text.trim().isEmpty || _secAOneController.text.trim().isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Security question 1 and answer are required'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    if (_secQTwoController.text.trim().isEmpty || _secATwoController.text.trim().isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Security question 2 and answer are required'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    try {
      final response = await http.post(
        Uri.parse('${ApiConstants.apiBase}/profile_security_questions.php'),
        body: {
          'userID': user!.id,
          'sec_q_one': _secQOneController.text.trim(),
          'sec_a_one': _secAOneController.text.trim(),
          'sec_q_two': _secQTwoController.text.trim(),
          'sec_a_two': _secATwoController.text.trim(),
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(data['message'] ?? ''),
              backgroundColor: data['responseCode'] == '1' ? Colors.green : Colors.red,
            ),
          );
        }

        if (data['responseCode'] == '1') {
          // Refresh user profile
          await AuthService().fetchUserProfile(user!.username);
        }
      }
    } catch (e) {
      print('Error saving security questions: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(TranslationKeys.errorOccurred.tr),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // Save Visibility Settings
  Future<void> _saveVisibilitySettings() async {
    if (user == null) return;

    try {
      final response = await http.post(
        Uri.parse('${ApiConstants.apiBase}/profile_visibility.php'),
        body: {
          'userID': user!.id,
          'visible': isPrivate ? '0' : '1',
          'private': isPrivate ? '1' : '0',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['responseCode'] == '1') {
          // Refresh user profile
          await AuthService().fetchUserProfile(user!.username);
        }
      }
    } catch (e) {
      print('Error saving visibility settings: $e');
    }
  }

  // Cache Management Section
  Widget _buildCacheManagementSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Clear Translations Cache
        ListTile(
          leading: Icon(Icons.translate, color: AppColors.getIconColor(context)),
          title: TranslatedText(
            TranslationKeys.clearTranslationsCache,
            style: TextStyle(color: AppColors.getTextColor(context)),
          ),
          subtitle: Text(
            'Clear cached translation data',
            style: TextStyle(color: AppColors.getSecondaryTextColor(context), fontSize: 12),
          ),
          trailing: Icon(Icons.chevron_right, color: AppColors.getIconColor(context)),
          onTap: () => _clearTranslationsCache(context),
        ),
        const Divider(height: 1),
        // Clear Posts Cache
        ListTile(
          leading: Icon(Icons.article, color: AppColors.getIconColor(context)),
          title: TranslatedText(
            TranslationKeys.clearPostsCache,
            style: TextStyle(color: AppColors.getTextColor(context)),
          ),
          subtitle: Text(
            'Clear cached posts and timeline data',
            style: TextStyle(color: AppColors.getSecondaryTextColor(context), fontSize: 12),
          ),
          trailing: Icon(Icons.chevron_right, color: AppColors.getIconColor(context)),
          onTap: () => _clearPostsCache(context),
        ),
        const Divider(height: 1),
        // Clear Friends Cache
        ListTile(
          leading: Icon(Icons.people, color: AppColors.getIconColor(context)),
          title: TranslatedText(
            TranslationKeys.clearFriendsCache,
            style: TextStyle(color: AppColors.getTextColor(context)),
          ),
          subtitle: Text(
            'Clear cached friends list data',
            style: TextStyle(color: AppColors.getSecondaryTextColor(context), fontSize: 12),
          ),
          trailing: Icon(Icons.chevron_right, color: AppColors.getIconColor(context)),
          onTap: () => _clearFriendsCache(context),
        ),
        const SizedBox(height: 16),
        // Clear All Cache Button
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: () => _clearAllCache(context),
            icon: const Icon(Icons.delete_sweep, size: 20),
            label: TranslatedText(TranslationKeys.clearAllCache),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // Clear Translations Cache
  Future<void> _clearTranslationsCache(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: TranslatedText(TranslationKeys.clearCache),
        content: TranslatedText(TranslationKeys.confirmClearCache),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: TranslatedText(TranslationKeys.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: TranslatedText(TranslationKeys.ok, style: const TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      try {
        await TranslationService().clearCache();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: TranslatedText(TranslationKeys.cacheClearedSuccessfully),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error clearing cache: ${e.toString()}'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  // Clear Posts Cache
  Future<void> _clearPostsCache(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: TranslatedText(TranslationKeys.clearCache),
        content: TranslatedText(TranslationKeys.confirmClearCache),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: TranslatedText(TranslationKeys.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: TranslatedText(TranslationKeys.ok, style: const TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      try {
        final postService = PostService();
        await postService.clearTimelineCache();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: TranslatedText(TranslationKeys.cacheClearedSuccessfully),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error clearing cache: ${e.toString()}'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  // Clear Friends Cache
  Future<void> _clearFriendsCache(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: TranslatedText(TranslationKeys.clearCache),
        content: TranslatedText(TranslationKeys.confirmClearCache),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: TranslatedText(TranslationKeys.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: TranslatedText(TranslationKeys.ok, style: const TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      try {
        final friendService = FriendService();
        await friendService.clearCache();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: TranslatedText(TranslationKeys.cacheClearedSuccessfully),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error clearing cache: ${e.toString()}'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  // Clear All Cache
  Future<void> _clearAllCache(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: TranslatedText(TranslationKeys.clearAllCache),
        content: TranslatedText(TranslationKeys.confirmClearAllCache),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: TranslatedText(TranslationKeys.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: TranslatedText(TranslationKeys.ok, style: const TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      try {
        // Clear all caches
        await TranslationService().clearCache();
        final postService = PostService();
        await postService.clearTimelineCache();
        final friendService = FriendService();
        await friendService.clearCache();
        
        // Clear any other cached data
        final prefs = await SharedPreferences.getInstance();
        // Clear cached update info
        await prefs.remove('cached_app_update');
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: TranslatedText(TranslationKeys.cacheClearedSuccessfully),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 2),
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error clearing cache: ${e.toString()}'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

}
