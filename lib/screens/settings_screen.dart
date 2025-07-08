import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'dart:io';
import 'dart:ui';
import 'dart:typed_data';
import '../models/user.dart';
import '../widgets/background_gradient.dart';
import '../widgets/custom_app_bar.dart';
import '../widgets/custom_bottom_navigation_bar.dart';
import '../widgets/search_form.dart';
import '../services/auth_service.dart';
import '../services/theme_service.dart';
import '../services/local_auth_service.dart';
import 'create_post_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({Key? key}) : super(key: key);

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
  final ImagePicker _picker = ImagePicker();

  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _nicknameController = TextEditingController();

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

  final GlobalKey<SearchFormState> _searchFormKey = GlobalKey<SearchFormState>();
  bool _showSearchForm = false;

  // Add focus nodes for proper focus management
  final FocusNode _emailFocusNode = FocusNode();
  final FocusNode _usernameFocusNode = FocusNode();
  final FocusNode _nicknameFocusNode = FocusNode();
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
      print('Cached user email: \'${cachedUser.email}\'' );
      print('Cached user username: \'${cachedUser.username}\'' );
      print('Cached user nickname: \'${cachedUser.nickname}\'' );
      _emailController.text = cachedUser.email;
      _usernameController.text = cachedUser.username;
      _nicknameController.text = cachedUser.nickname;
      setState(() {
        user = cachedUser;
        email = cachedUser.email;
        username = cachedUser.username;
        nickname = cachedUser.nickname;
        if (cachedUser.avatar.isNotEmpty) {
          profileImage = cachedUser.avatar;
        }
        if (cachedUser.wallpaper.isNotEmpty) {
          backgroundImage = cachedUser.wallpaper;
        }
        // Optionally set backgroundImage if you store it in the user profile
      });
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
    super.dispose();
  }

  // Helper to show picker dialog for avatar or wallpaper
  Future<void> _showImageSourceDialog({required bool isAvatar}) async {
    final source = await showDialog<ImageSource>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(isAvatar ? 'Update Avatar' : 'Update Wallpaper'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.of(context).pop(ImageSource.camera),
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
            child: Row(
              children: [
                const Icon(Icons.camera_alt, size: 28),
                const SizedBox(width: 16),
                const Text('Take Photo', style: TextStyle(fontSize: 18)),
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
                const Text('Choose from Gallery', style: TextStyle(fontSize: 18)),
              ],
            ),
          ),
        ],
      ),
    );
    if (source != null) {
      if (isAvatar) {
        await _pickAndCropAvatar(source: source);
      } else {
        await _pickAndCropBackground(source: source);
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

  // Update _pickAndCropAvatar to accept source
  Future<void> _pickAndCropAvatar({File? existingFile, ImageSource? source}) async {
    File? imageFile;
    if (existingFile != null) {
      imageFile = existingFile;
    } else if (source != null) {
      final XFile? picked = await _picker.pickImage(
        source: source,
        imageQuality: 85,
      );
      if (picked != null) imageFile = File(picked.path);
    } else if (profileImage.startsWith('http')) {
      imageFile = await _getFileFromUrl(profileImage);
    }

    if (imageFile != null) {
      // For now, use the image directly without cropping
      setState(() {
        _newAvatarFile = imageFile;
        avatarMargin = [0.0, 0.0, 0.0, 0.0]; // Default margins
      });
    }
  }

  // Update _pickAndCropBackground to accept source
  Future<void> _pickAndCropBackground({File? existingFile, ImageSource? source}) async {
    File? imageFile;
    if (existingFile != null) {
      imageFile = existingFile;
    } else if (source != null) {
      final XFile? picked = await _picker.pickImage(
        source: source,
        imageQuality: 85,
      );
      if (picked != null) imageFile = File(picked.path);
    } else if (backgroundImage.startsWith('http')) {
      imageFile = await _getFileFromUrl(backgroundImage);
    }

    if (imageFile != null) {
      // For now, use the image directly without cropping
      setState(() {
        _newBackgroundFile = imageFile;
        backgroundMargin = [0.0, 0.0, 0.0, 0.0]; // Default margins
      });
    }
  }

  Future<File> _saveTempFile(Uint8List? data, String filename) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$filename');
    await file.writeAsBytes(data!);
    return file;
  }

  double _getBackgroundAspectRatio(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    if (width < 600) {
      // Mobile: vertical rectangle (e.g., 9:16)
      return 9 / 16;
    } else {
      // Tablet/Desktop: horizontal rectangle (e.g., 16:9)
      return 16 / 9;
    }
  }

  void _changeProfileImage() {
    // TODO: Implement image picker
  }

  void _changeBackgroundImage() {
    // TODO: Implement image picker
  }

  void _savePassword() {
    // TODO: Implement password change logic
  }

  String _getPinOptionFromValue(String? value) {
    switch (value) {
      case '4':
        return '4 digit';
      case '6':
        return '6 digit';
      case '8':
        return '8 digit';
      default:
        return 'No PIN';
    }
  }

  String _getPinValueFromOption(String? option) {
    switch (option) {
      case '4 digit':
        return '4';
      case '6 digit':
        return '6';
      case '8 digit':
        return '8';
      default:
        return '';
    }
  }

  Future<void> _savePin() async {
    // TODO: Implement PIN save logic
    // Show loading indicator
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return const Center(
          child: CircularProgressIndicator(),
        );
      },
    );
    try {
      // Validate new PIN
      if (_newPinController.text != _confirmPinController.text) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('New PIN and confirmation do not match'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
      // Update user profile with new PIN type and value
      final updatedUser = User(
        id: user!.id,
        username: user?.username ?? '',
        secQOne: user?.secQOne ?? '',
        secAOne: user?.secAOne ?? '',
        secQTwo: user?.secQTwo ?? '',
        secATwo: user?.secATwo ?? '',
        pinV: _getPinValueFromOption(_selectedPinOption),
        pin: _selectedPinOption == 'No PIN' ? '' : _newPinController.text,
        email: user?.email ?? '',
        fname: user?.fname ?? '',
        mname: user?.mname ?? '',
        lname: user?.lname ?? '',
        title: user?.title ?? '',
        nickname: user?.nickname ?? '',
        avatar: user?.avatar ?? '',
        bio: user?.bio ?? '',
        color: user?.color ?? '',
        rank: user?.rank ?? '',
        deactivated: user?.deactivated ?? '',
        deactivatedReason: user?.deactivatedReason ?? '',
        banned: user?.banned ?? '',
        bannedReason: user?.bannedReason ?? '',
        visible: user?.visible ?? '',
        registered: user?.registered ?? '',
        token: user?.token ?? '',
        reset: user?.reset ?? '',
        online: user?.online ?? '',
        relationship: user?.relationship ?? '',
        wallpaper: user?.wallpaper ?? '',
        wallpaperMargin: user?.wallpaperMargin ?? '',
        avatarMargin: user?.avatarMargin ?? '',
      );
      await AuthService().updateUserProfile(updatedUser);
      setState(() {
        user = updatedUser;
        _currentPinController.clear();
        _newPinController.clear();
        _confirmPinController.clear();
      });
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('PIN updated successfully'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error updating PIN:  ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _saveBasicInfo() async {
    // Show loading indicator
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return const Center(
          child: CircularProgressIndicator(),
        );
      },
    );

    try {
      // Update the user profile with all required fields
      final updatedUser = User(
        id: user!.id,
        username: _usernameController.text,
        secQOne: user?.secQOne ?? '',
        secAOne: user?.secAOne ?? '',
        secQTwo: user?.secQTwo ?? '',
        secATwo: user?.secATwo ?? '',
        pinV: user?.pinV ?? '',
        pin: user?.pin ?? '',
        email: _emailController.text,
        fname: user?.fname ?? '',
        mname: user?.mname ?? '',
        lname: user?.lname ?? '',
        title: user?.title ?? '',
        nickname: _nicknameController.text,
        avatar: user?.avatar ?? '',
        bio: user?.bio ?? '',
        color: user?.color ?? '',
        rank: user?.rank ?? '',
        deactivated: user?.deactivated ?? '',
        deactivatedReason: user?.deactivatedReason ?? '',
        banned: user?.banned ?? '',
        bannedReason: user?.bannedReason ?? '',
        visible: user?.visible ?? '',
        registered: user?.registered ?? '',
        token: user?.token ?? '',
        reset: user?.reset ?? '',
        online: user?.online ?? '',
        relationship: user?.relationship ?? '',
        wallpaper: user?.wallpaper ?? '',
        wallpaperMargin: user?.wallpaperMargin ?? '',
        avatarMargin: user?.avatarMargin ?? '',
      );

      // Save to backend/local storage
      await AuthService().updateUserProfile(updatedUser);

      // Update local state
      setState(() {
        user = updatedUser;
        email = updatedUser.email;
        username = updatedUser.username;
        nickname = updatedUser.nickname;
      });

      // Hide loading indicator
      Navigator.pop(context);

      // Show success message
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Profile updated successfully'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      // Hide loading indicator
      Navigator.pop(context);

      // Show error message
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error updating profile: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _saveSecurityQuestions() async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return const Center(child: CircularProgressIndicator());
      },
    );
    try {
      final updatedUser = User(
        id: user!.id,
        username: user?.username ?? '',
        secQOne: user?.secQOne ?? '',
        secAOne: user?.secAOne ?? '',
        secQTwo: user?.secQTwo ?? '',
        secATwo: user?.secATwo ?? '',
        pinV: _getPinValueFromOption(_selectedPinOption),
        pin: _selectedPinOption == 'No PIN' ? '' : _newPinController.text,
        email: user?.email ?? '',
        fname: user?.fname ?? '',
        mname: user?.mname ?? '',
        lname: user?.lname ?? '',
        title: user?.title ?? '',
        nickname: user?.nickname ?? '',
        avatar: user?.avatar ?? '',
        bio: user?.bio ?? '',
        color: user?.color ?? '',
        rank: user?.rank ?? '',
        deactivated: user?.deactivated ?? '',
        deactivatedReason: user?.deactivatedReason ?? '',
        banned: user?.banned ?? '',
        bannedReason: user?.bannedReason ?? '',
        visible: user?.visible ?? '',
        registered: user?.registered ?? '',
        token: user?.token ?? '',
        reset: user?.reset ?? '',
        online: user?.online ?? '',
        relationship: user?.relationship ?? '',
        wallpaper: user?.wallpaper ?? '',
        wallpaperMargin: user?.wallpaperMargin ?? '',
        avatarMargin: user?.avatarMargin ?? '',
      );
      await AuthService().updateUserProfile(updatedUser);
      setState(() {
        user = updatedUser;
      });
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Security questions updated successfully'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error updating security questions:  ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final appBarHeight = AppBarConfig.getAppBarHeight(context);
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final transparentColor = isDarkMode
        ? Colors.white.withOpacity(0.2)
        : Colors.black.withOpacity(0.5);
    final iconBackgroundColor = isDarkMode ? Colors.white24 : Colors.black45;

    // Define wallpaper logic safely here
    final String wallpaperUrl = user?.wallpaper ?? '';
    final String avatarUrl = user?.avatar ?? '';
    final bool useDefaultWallpaper = wallpaperUrl.isEmpty || wallpaperUrl == avatarUrl;

    return Scaffold(
      extendBodyBehindAppBar: true,
      extendBody: true,
      appBar: CustomAppBar(
        logoPath: 'assets/images/logo.png',
        onLogout: () {},
        onLogoPressed: () {
          Navigator.of(context).pushReplacementNamed('/home');
        },
        onSearchFormToggle: () {
          setState(() {
            _showSearchForm = !_showSearchForm;
          });
        },
        isSearchFormVisible: _showSearchForm,
      ),
      bottomNavigationBar: Padding(
        padding: EdgeInsets.only(
          bottom: Theme.of(context).platform == TargetPlatform.iOS
              ? 8.0
              : 8.0 + MediaQuery.of(context).padding.bottom,
        ),
        child: CustomBottomNavigationBar(
          onStarPressed: () {},
          onAddPressed: () {},
          onFriendsPressed: () {},
          onChatPressed: () {},
          onNotificationsPressed: () {},
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
                      height: 160,
                      decoration: BoxDecoration(
                        image: _newBackgroundFile != null
                            ? DecorationImage(
                                image: FileImage(_newBackgroundFile!),
                                fit: BoxFit.cover,
                              )
                            : useDefaultWallpaper
                                ? null // No image, gradient will show through
                                : DecorationImage(
                                    image: CachedNetworkImageProvider(wallpaperUrl),
                                    fit: BoxFit.cover,
                                  ),
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
                                child: const Icon(Icons.edit, color: Colors.white, size: 20),
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
                                  child: const Icon(Icons.crop, color: Colors.white, size: 20),
                                ),
                              ),
                            ]
                          ],
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
                              border: Border.all(color: Colors.white, width: 1),
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
                                        )
                                      : profileImage.startsWith('http')
                                          ? CachedNetworkImage(
                                              imageUrl: profileImage,
                                              width: 100,
                                              height: 100,
                                              fit: BoxFit.cover,
                                              placeholder: (context, url) => const Center(
                                                child: CircularProgressIndicator(
                                                  color: Colors.white,
                                                ),
                                              ),
                                              errorWidget: (context, url, error) =>
                                                  Image.asset(
                                                'assets/images/logo.png',
                                                width: 100,
                                                height: 100,
                                                fit: BoxFit.cover,
                                              ),
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
                                              child: const Icon(Icons.edit, color: Colors.white, size: 14),
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
                                                child: const Icon(Icons.crop, color: Colors.white, size: 14),
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
                const SizedBox(height: 60),
                // Basic Info Section
                _buildExpansionTile(
                  title: 'Basic Information',
                  tileColor: transparentColor,
                  children: [
                    TextField(
                      controller: _emailController,
                      focusNode: _emailFocusNode,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        labelText: 'Email',
                        labelStyle: TextStyle(color: Colors.white70),
                        enabledBorder: UnderlineInputBorder(
                          borderSide: BorderSide(color: Colors.white30),
                        ),
                        focusedBorder: UnderlineInputBorder(
                          borderSide: BorderSide(color: Colors.white),
                        ),
                      ),
                      onTap: () {
                        // Unfocus other fields to prevent context menu conflicts
                        _unfocusOtherFields(_emailFocusNode);
                      },
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _usernameController,
                      focusNode: _usernameFocusNode,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        labelText: 'Username',
                        labelStyle: TextStyle(color: Colors.white70),
                        enabledBorder: UnderlineInputBorder(
                          borderSide: BorderSide(color: Colors.white30),
                        ),
                        focusedBorder: UnderlineInputBorder(
                          borderSide: BorderSide(color: Colors.white),
                        ),
                      ),
                      readOnly: true,
                      onTap: () {
                        _unfocusOtherFields(_usernameFocusNode);
                      },
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _nicknameController,
                      focusNode: _nicknameFocusNode,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        labelText: 'Nickname',
                        labelStyle: TextStyle(color: Colors.white70),
                        enabledBorder: UnderlineInputBorder(
                          borderSide: BorderSide(color: Colors.white30),
                        ),
                        focusedBorder: UnderlineInputBorder(
                          borderSide: BorderSide(color: Colors.white),
                        ),
                      ),
                      onTap: () {
                        _unfocusOtherFields(_nicknameFocusNode);
                      },
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _saveBasicInfo,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: const Text('Save Changes'),
                      ),
                    ),
                  ],
                ),
                // Password Section
                _buildExpansionTile(
                  title: 'Change Password',
                  tileColor: transparentColor,
                  children: [
                    TextField(
                      controller: _oldPasswordController,
                      focusNode: _oldPasswordFocusNode,
                      obscureText: true,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        labelText: 'Current Password',
                        labelStyle: TextStyle(color: Colors.white70),
                        enabledBorder: UnderlineInputBorder(
                          borderSide: BorderSide(color: Colors.white30),
                        ),
                        focusedBorder: UnderlineInputBorder(
                          borderSide: BorderSide(color: Colors.white),
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
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        labelText: 'New Password',
                        labelStyle: TextStyle(color: Colors.white70),
                        enabledBorder: UnderlineInputBorder(
                          borderSide: BorderSide(color: Colors.white30),
                        ),
                        focusedBorder: UnderlineInputBorder(
                          borderSide: BorderSide(color: Colors.white),
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
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        labelText: 'Confirm New Password',
                        labelStyle: TextStyle(color: Colors.white70),
                        enabledBorder: UnderlineInputBorder(
                          borderSide: BorderSide(color: Colors.white30),
                        ),
                        focusedBorder: UnderlineInputBorder(
                          borderSide: BorderSide(color: Colors.white),
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
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: const Text('Change Password'),
                      ),
                    ),
                  ],
                ),
                // PIN Section
                _buildExpansionTile(
                  title: 'PIN Code',
                  tileColor: transparentColor,
                  children: [
                    DropdownButtonFormField<String>(
                      value: _selectedPinOption,
                      items: _pinOptions.map((option) {
                        return DropdownMenuItem<String>(
                          value: option,
                          child: Text(option, style: const TextStyle(color: Colors.black)),
                        );
                      }).toList(),
                      onChanged: (value) {
                        setState(() {
                          _selectedPinOption = value;
                        });
                      },
                      decoration: const InputDecoration(
                        labelText: 'PIN Type',
                        labelStyle: TextStyle(color: Colors.white70),
                        enabledBorder: UnderlineInputBorder(
                          borderSide: BorderSide(color: Colors.white30),
                        ),
                        focusedBorder: UnderlineInputBorder(
                          borderSide: BorderSide(color: Colors.white),
                        ),
                      ),
                      dropdownColor: Colors.white,
                    ),
                    if (_selectedPinOption != null && _selectedPinOption != 'No PIN') ...[
                      const SizedBox(height: 16),
                      if (user?.pin != null && user!.pin.isNotEmpty) ...[
                        TextField(
                          controller: _currentPinController,
                          focusNode: _currentPinFocusNode,
                          obscureText: true,
                          style: const TextStyle(color: Colors.white),
                          decoration: const InputDecoration(
                            labelText: 'Current PIN',
                            labelStyle: TextStyle(color: Colors.white70),
                            enabledBorder: UnderlineInputBorder(
                              borderSide: BorderSide(color: Colors.white30),
                            ),
                            focusedBorder: UnderlineInputBorder(
                              borderSide: BorderSide(color: Colors.white),
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
                        style: const TextStyle(color: Colors.white),
                        decoration: const InputDecoration(
                          labelText: 'New PIN',
                          labelStyle: TextStyle(color: Colors.white70),
                          enabledBorder: UnderlineInputBorder(
                            borderSide: BorderSide(color: Colors.white30),
                          ),
                          focusedBorder: UnderlineInputBorder(
                            borderSide: BorderSide(color: Colors.white),
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
                        style: const TextStyle(color: Colors.white),
                        decoration: const InputDecoration(
                          labelText: 'Confirm PIN',
                          labelStyle: TextStyle(color: Colors.white70),
                          enabledBorder: UnderlineInputBorder(
                            borderSide: BorderSide(color: Colors.white30),
                          ),
                          focusedBorder: UnderlineInputBorder(
                            borderSide: BorderSide(color: Colors.white),
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
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          child: const Text('Save PIN'),
                        ),
                      ),
                    ],
                  ],
                ),
                // Security Questions Section
                _buildExpansionTile(
                  title: 'Security Questions',
                  tileColor: transparentColor,
                  children: [
                    TextField(
                      controller: _secQOneController,
                      focusNode: _secQOneFocusNode,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        labelText: 'Security Question 1',
                        labelStyle: TextStyle(color: Colors.white70),
                        enabledBorder: UnderlineInputBorder(
                          borderSide: BorderSide(color: Colors.white30),
                        ),
                        focusedBorder: UnderlineInputBorder(
                          borderSide: BorderSide(color: Colors.white),
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
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        labelText: 'Answer 1',
                        labelStyle: TextStyle(color: Colors.white70),
                        enabledBorder: UnderlineInputBorder(
                          borderSide: BorderSide(color: Colors.white30),
                        ),
                        focusedBorder: UnderlineInputBorder(
                          borderSide: BorderSide(color: Colors.white),
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
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        labelText: 'Security Question 2',
                        labelStyle: TextStyle(color: Colors.white70),
                        enabledBorder: UnderlineInputBorder(
                          borderSide: BorderSide(color: Colors.white30),
                        ),
                        focusedBorder: UnderlineInputBorder(
                          borderSide: BorderSide(color: Colors.white),
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
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        labelText: 'Answer 2',
                        labelStyle: TextStyle(color: Colors.white70),
                        enabledBorder: UnderlineInputBorder(
                          borderSide: BorderSide(color: Colors.white30),
                        ),
                        focusedBorder: UnderlineInputBorder(
                          borderSide: BorderSide(color: Colors.white),
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
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: const Text('Save Security Questions'),
                      ),
                    ),
                  ],
                ),
                // Settings Section
                _buildExpansionTile(
                  title: 'Preferences',
                  tileColor: transparentColor,
                  children: [
                    SwitchListTile(
                      title: const Text(
                        'Enable Notifications',
                        style: TextStyle(color: Colors.white),
                      ),
                      value: notificationsEnabled,
                      onChanged: (bool value) {
                        setState(() {
                          notificationsEnabled = value;
                        });
                      },
                      activeColor: Colors.blue,
                    ),
                    SwitchListTile(
                      title: const Text(
                        'Private Profile',
                        style: TextStyle(color: Colors.white),
                      ),
                      value: isPrivate,
                      onChanged: (bool value) {
                        setState(() {
                          isPrivate = value;
                        });
                      },
                      activeColor: Colors.blue,
                    ),
                    SwitchListTile(
                      title: const Text(
                        'Biometric Lock',
                        style: TextStyle(color: Colors.white),
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
                      activeColor: Colors.blue,
                    ),
                  ],
                ),
                // Appearance Section
                Consumer<ThemeService>(
                  builder: (context, themeService, child) {
                    return _buildExpansionTile(
                      title: 'Appearance',
                      tileColor: transparentColor,
                      children: [
                        ListTile(
                          title: const Text(
                            'Theme Mode',
                            style: TextStyle(color: Colors.white),
                          ),
                          subtitle: Text(
                            themeService.themeModeString,
                            style: const TextStyle(color: Colors.white70),
                          ),
                          trailing: const Icon(
                            Icons.palette,
                            color: Colors.white,
                          ),
                          onTap: () {
                            _showThemeModeDialog(context, themeService);
                          },
                        ),
                        SwitchListTile(
                          title: const Text(
                            'Force Dark Mode',
                            style: TextStyle(color: Colors.white),
                          ),
                          subtitle: const Text(
                            'Override system theme',
                            style: TextStyle(color: Colors.white70),
                          ),
                          value: themeService.themeMode == ThemeMode.dark,
                          onChanged: (bool value) async {
                            if (value) {
                              await themeService.setThemeMode(ThemeMode.dark);
                            } else {
                              await themeService.setThemeMode(ThemeMode.system);
                            }
                          },
                          activeColor: Colors.blue,
                        ),
                        SwitchListTile(
                          title: const Text(
                            'Force Light Mode',
                            style: TextStyle(color: Colors.white),
                          ),
                          subtitle: const Text(
                            'Override system theme',
                            style: TextStyle(color: Colors.white70),
                          ),
                          value: themeService.themeMode == ThemeMode.light,
                          onChanged: (bool value) async {
                            if (value) {
                              await themeService.setThemeMode(ThemeMode.light);
                            } else {
                              await themeService.setThemeMode(ThemeMode.system);
                            }
                          },
                          activeColor: Colors.blue,
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 125),
              ],
            ),
          ),
          if (_showSearchForm)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SearchForm(
                key: _searchFormKey,
                onClose: () {
                  setState(() {
                    _showSearchForm = false;
                  });
                },
                onSearch: (query) {
                  print('Searching for: $query');
                  _searchFormKey.currentState?.closeForm();
                },
              ),
            ),
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
          title: Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          iconColor: Colors.white,
          collapsedIconColor: Colors.white,
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          children: children,
        ),
      ),
    );
  }

  Widget _buildField(String label, String value, {required bool readOnly}) {
    TextEditingController controller;
    if (label == 'Email') {
      controller = _emailController;
    } else if (label == 'Username') {
      controller = _usernameController;
    } else if (label == 'Nickname') {
      controller = _nicknameController;
    } else {
      controller = TextEditingController(text: value);
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: TextField(
        controller: controller,
        readOnly: readOnly,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }

  Widget _buildPasswordField(String label, TextEditingController controller) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: TextField(
        controller: controller,
        obscureText: true,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }

  void _showThemeModeDialog(BuildContext context, ThemeService themeService) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: Colors.grey[900],
          title: const Text(
            'Choose Theme Mode',
            style: TextStyle(color: Colors.white),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              RadioListTile<ThemeMode>(
                title: const Text(
                  'System',
                  style: TextStyle(color: Colors.white),
                ),
                subtitle: const Text(
                  'Follow system settings',
                  style: TextStyle(color: Colors.white70),
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
                title: const Text(
                  'Light',
                  style: TextStyle(color: Colors.white),
                ),
                subtitle: const Text(
                  'Always use light theme',
                  style: TextStyle(color: Colors.white70),
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
                title: const Text(
                  'Dark',
                  style: TextStyle(color: Colors.white),
                ),
                subtitle: const Text(
                  'Always use dark theme',
                  style: TextStyle(color: Colors.white70),
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
              child: const Text(
                'Cancel',
                style: TextStyle(color: Colors.white70),
              ),
            ),
          ],
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
} 