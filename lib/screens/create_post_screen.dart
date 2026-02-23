import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'dart:ui';
import '../services/post_service.dart';
import '../services/auth_service.dart';
import '../models/post.dart';
import '../models/user.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../widgets/translated_text.dart';
import '../services/translation_service.dart';

class CreatePostScreen extends StatefulWidget {
  final bool isEditing;
  final Post? postToEdit;

  const CreatePostScreen({
    super.key,
    this.isEditing = false,
    this.postToEdit,
  });

  @override
  State<CreatePostScreen> createState() => _CreatePostScreenState();
}

class _CreatePostScreenState extends State<CreatePostScreen> {
  final TextEditingController _contentController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  final PostService _postService = PostService();
  final AuthService _authService = AuthService();
  final ImagePicker _picker = ImagePicker();
  List<File> _selectedFiles = [];
  bool _isPosting = false;
  User? _currentUser;
  int _visibility = 1; // 0: Only me, 1: Friends, 2: Public

  @override
  void initState() {
    super.initState();
    _loadCurrentUser();

    if (widget.isEditing && widget.postToEdit != null) {
      _contentController.text = widget.postToEdit!.content;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _focusNode.requestFocus();
      }
    });
  }

  Future<void> _loadCurrentUser() async {
    final user = await _authService.getStoredUserProfile();
    if (mounted) {
      setState(() {
        _currentUser = user;
      });
    }
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _contentController.dispose();
    super.dispose();
  }

  Future<void> _showMediaPicker() async {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (BuildContext context) {
        return ClipRRect(
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(20),
            topRight: Radius.circular(20),
          ),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Container(
              decoration: BoxDecoration(
                color: Theme.of(context).brightness == Brightness.dark 
                    ? Colors.black.withOpacity(0.7) 
                    : Colors.white.withOpacity(0.7),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(20),
                  topRight: Radius.circular(20),
                ),
              ),
              child: Wrap(
                children: [
                   Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8.0),
                    child: Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Theme.of(context).brightness == Brightness.dark 
                              ? Colors.white.withOpacity(0.3) 
                              : Colors.black.withOpacity(0.3),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  ),
                  ListTile(
                    leading: Icon(Icons.photo, color: Theme.of(context).iconTheme.color),
                    title: Text('Photo Library', style: TextStyle(color: Theme.of(context).textTheme.bodyLarge?.color)),
                    onTap: () {
                      _pickMedia(ImageSource.gallery, false);
                      Navigator.of(context).pop();
                    },
                  ),
                  ListTile(
                    leading: Icon(Icons.videocam, color: Theme.of(context).iconTheme.color),
                    title: Text('Video Library', style: TextStyle(color: Theme.of(context).textTheme.bodyLarge?.color)),
                    onTap: () {
                      _pickMedia(ImageSource.gallery, true);
                      Navigator.of(context).pop();
                    },
                  ),
                  ListTile(
                    leading: Icon(Icons.camera_alt, color: Theme.of(context).iconTheme.color),
                    title: Text('Camera', style: TextStyle(color: Theme.of(context).textTheme.bodyLarge?.color)),
                    onTap: () {
                      _pickMedia(ImageSource.camera, false);
                      Navigator.of(context).pop();
                    },
                  ),
                  ListTile(
                    leading: Icon(Icons.videocam_outlined, color: Theme.of(context).iconTheme.color),
                    title: Text('Video Camera', style: TextStyle(color: Theme.of(context).textTheme.bodyLarge?.color)),
                    onTap: () {
                      _pickMedia(ImageSource.camera, true);
                      Navigator.of(context).pop();
                    },
                  ),
                  SizedBox(height: MediaQuery.of(context).padding.bottom + 20),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _pickMedia(ImageSource source, bool isVideo) async {
    try {
      if (isVideo) {
        final XFile? video = await _picker.pickVideo(source: source, maxDuration: const Duration(minutes: 5));
        if (video != null) {
          setState(() {
            _selectedFiles.add(File(video.path));
          });
        }
      } else {
        final List<XFile>? images = source == ImageSource.gallery 
            ? await _picker.pickMultiImage(imageQuality: 80)
            : [await _picker.pickImage(source: source, imageQuality: 80)].whereType<XFile>().toList();
        
        if (images != null && images.isNotEmpty) {
          setState(() {
            _selectedFiles.addAll(images.map((img) => File(img.path)));
          });
        }
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to pick media: $e')),
      );
    }
  }

  void _onContentChanged(String value) {
    final emojiMap = {
      ':)': '🙂',
      ':D': '😁',
      ':P': '😛',
      ':(': '🙁',
      ';)': '😉',
      ':O': '😮',
      ':*': '😘',
      '<3': '❤️',
      ':/': '😕',
      ':|': '😐',
      ':\$': '🤫',
      ':s': '😕',
    };

    String newText = value;
    bool changed = false;
    emojiMap.forEach((key, emoji) {
      if (newText.contains(key)) {
        newText = newText.replaceAll(key, emoji);
        changed = true;
      }
    });

    if (changed) {
      _contentController.value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(offset: newText.length),
      );
    }
  }

  Future<void> _submitPost() async {
    final content = _contentController.text.trim();
    if (content.isEmpty && _selectedFiles.isEmpty) {
       return; 
    }

    setState(() => _isPosting = true);

    try {
      final userId = await _authService.getStoredUserId();
      if (userId == null) {
        throw Exception('User not logged in');
      }

      if (widget.isEditing && widget.postToEdit != null) {
        await _postService.updatePost(
          postId: widget.postToEdit!.id,
          userId: userId,
          content: content,
        );

        if (mounted) {
          Navigator.of(context).pop('updated');
        }
      } else {
        final result = await _postService.createPost(
          userId: userId,
          content: content,
          mediaFiles: _selectedFiles,
          visibility: _visibility,
        );

        final postId = result['postID'];

        if (mounted) {
          Navigator.of(context).pop(postId);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Failed to ${widget.isEditing ? 'update' : 'create'} post: ${e.toString()}"),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isPosting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    
    return GestureDetector(
      onTap: () {
        if (MediaQuery.of(context).viewInsets.bottom == 0) {
          Navigator.of(context).pop();
        } else {
          FocusScope.of(context).unfocus();
        }
      },
      child: Scaffold(
        resizeToAvoidBottomInset: false,
        backgroundColor: Colors.transparent,
        body: Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                onTap: () => Navigator.of(context).pop(),
                child: Container(
                  color: Colors.transparent,
                ),
              ),
            ),
            SafeArea(
              child: Align(
                alignment: MediaQuery.of(context).viewInsets.bottom > 0 
                  ? const Alignment(0.0, -0.6)
                  : Alignment.center,
                child: SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 20),
                    child: GestureDetector(
                      onTap: () {},
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                          child: Container(
                            width: double.infinity,
                            constraints: const BoxConstraints(
                              maxWidth: 600,
                            ),
                            decoration: BoxDecoration(
                              color: isDarkMode 
                                  ? Colors.black.withOpacity(0.5) 
                                  : Colors.white.withOpacity(0.7),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: isDarkMode 
                                    ? Colors.white.withOpacity(0.08) 
                                    : Colors.black.withOpacity(0.04),
                                width: 0.5,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.2),
                                  blurRadius: 20,
                                  offset: const Offset(0, 10),
                                ),
                              ],
                            ),
                            padding: const EdgeInsets.all(20),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Container(
                                      width: 50,
                                      height: 50,
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(12),
                                        image: DecorationImage(
                                          image: _currentUser != null && _currentUser!.avatar.isNotEmpty
                                              ? CachedNetworkImageProvider(_currentUser!.avatar)
                                              : const AssetImage('assets/images/default_avatar.png') as ImageProvider,
                                          fit: BoxFit.cover,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            _currentUser?.username ?? 'User',
                                            style: TextStyle(
                                              color: isDarkMode ? Colors.white : Colors.black87,
                                              fontSize: 16,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          GestureDetector(
                                            onTap: () {
                                              showMenu(
                                                context: context,
                                                position: const RelativeRect.fromLTRB(100, 100, 0, 0),
                                                items: [
                                                  const PopupMenuItem(value: 0, child: Text('Only me')),
                                                  const PopupMenuItem(value: 1, child: Text('Friends Only')),
                                                  const PopupMenuItem(value: 2, child: Text('Public')),
                                                ],
                                              ).then((value) {
                                                if (value != null) {
                                                  setState(() => _visibility = value as int);
                                                }
                                              });
                                            },
                                            child: Row(
                                              children: [
                                                Icon(
                                                  _visibility == 0 ? Icons.lock : (_visibility == 1 ? Icons.group : Icons.public), 
                                                  size: 14, 
                                                  color: isDarkMode ? Colors.white70 : Colors.black54
                                                ),
                                                const SizedBox(width: 4),
                                                Text(
                                                  _visibility == 0 ? 'Only me' : (_visibility == 1 ? 'Friends Only' : 'Public'),
                                                  style: TextStyle(
                                                    color: isDarkMode ? Colors.white70 : Colors.black54,
                                                    fontSize: 13,
                                                  ),
                                                ),
                                                Icon(
                                                  Icons.keyboard_arrow_down, 
                                                  size: 16, 
                                                  color: isDarkMode ? Colors.white70 : Colors.black54
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (widget.isEditing)
                                    IconButton(
                                      icon: Icon(Icons.close, color: isDarkMode ? Colors.white54 : Colors.black45),
                                      onPressed: () => Navigator.of(context).pop(),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                Flexible(
                                  child: SingleChildScrollView(
                                    child: Column(
                                      children: [
                                        ListenableBuilder(
                                          listenable: TranslationService(),
                                          builder: (context, _) {
                                            return TextField(
                                              controller: _contentController,
                                              focusNode: _focusNode,
                                              maxLines: null,
                                              minLines: 3,
                                              onChanged: _onContentChanged,
                                              style: TextStyle(
                                                color: isDarkMode ? Colors.white : Colors.black87,
                                                fontSize: 16,
                                              ),
                                              decoration: InputDecoration(
                                                hintText: TranslationService().translate(TranslationKeys.whatOnMind),
                                                hintStyle: TextStyle(
                                                  color: isDarkMode ? Colors.white54 : Colors.black38,
                                                ),
                                                border: InputBorder.none,
                                                contentPadding: EdgeInsets.zero,
                                              ),
                                            );
                                          },
                                        ),
                                        if (_selectedFiles.isNotEmpty)
                                          Padding(
                                            padding: const EdgeInsets.only(top: 16.0),
                                            child: SizedBox(
                                              height: 120,
                                              child: ListView.separated(
                                                scrollDirection: Axis.horizontal,
                                                itemCount: _selectedFiles.length,
                                                separatorBuilder: (context, index) => const SizedBox(width: 8),
                                                itemBuilder: (context, index) {
                                                  final file = _selectedFiles[index];
                                                  final isVideo = file.path.endsWith('.mp4') || file.path.endsWith('.mov');
                                                  return Stack(
                                                    children: [
                                                      ClipRRect(
                                                        borderRadius: BorderRadius.circular(12),
                                                        child: isVideo
                                                            ? Container(
                                                                width: 120,
                                                                height: 120,
                                                                color: Colors.black,
                                                                child: const Center(
                                                                  child: Icon(Icons.play_circle_fill, color: Colors.white, size: 30),
                                                                ),
                                                              )
                                                            : Image.file(
                                                                file,
                                                                fit: BoxFit.cover,
                                                                width: 120,
                                                                height: 120,
                                                              ),
                                                      ),
                                                      Positioned(
                                                        top: 4,
                                                        right: 4,
                                                        child: GestureDetector(
                                                          onTap: () => setState(() {
                                                            _selectedFiles.removeAt(index);
                                                          }),
                                                          child: Container(
                                                            padding: const EdgeInsets.all(4),
                                                            decoration: BoxDecoration(
                                                              color: Colors.black.withOpacity(0.6),
                                                              shape: BoxShape.circle,
                                                            ),
                                                            child: const Icon(Icons.close, color: Colors.white, size: 16),
                                                          ),
                                                        ),
                                                      ),
                                                    ],
                                                  );
                                                },
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 16),
                                Row(
                                  children: [
                                    IconButton(
                                      onPressed: _showMediaPicker,
                                      icon: Icon(
                                        Icons.image_outlined, 
                                        color: isDarkMode ? Colors.white70 : Colors.black54
                                      ),
                                      tooltip: 'Add Media',
                                    ),
                                    if (_selectedFiles.isNotEmpty)
                                    Text(
                                      '${_selectedFiles.length}',
                                      style: TextStyle(
                                        color: isDarkMode ? Colors.white70 : Colors.black54,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const Spacer(),
                                    IconButton(
                                      onPressed: _isPosting ? null : _submitPost,
                                      icon: _isPosting 
                                          ? const SizedBox(
                                              width: 20, 
                                              height: 20, 
                                              child: CircularProgressIndicator(strokeWidth: 2)
                                            ) 
                                          : Icon(
                                              Icons.send, 
                                              color: isDarkMode ? Colors.white : Colors.blueAccent,
                                              size: 28,
                                            ),
                                    ),
                                  ],
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
            ),
          ],
        ),
      ),
    );
  }
}
