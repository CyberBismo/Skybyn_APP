import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'dart:ui';
import '../services/post_service.dart';
import '../services/auth_service.dart';
import '../models/post.dart';
import '../widgets/translated_text.dart';
import '../services/translation_service.dart';

import 'package:video_player/video_player.dart';
import '../widgets/app_banner.dart';

class CreatePostWidget extends StatefulWidget {
  final bool isEditing;
  final Post? postToEdit;
  final Function(String postId)? onPostCreated;
  final Function()? onPostUpdated;
  final Function()? onCancel;

  static Future<T?> show<T>({
    required BuildContext context,
    bool isEditing = false,
    Post? postToEdit,
  }) {
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.9,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        builder: (context, scrollController) => Container(
          margin: EdgeInsets.only(
            top: MediaQuery.of(context).padding.top + 60,
          ),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.5),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: Padding(
                padding: EdgeInsets.only(
                  bottom: MediaQuery.of(context).viewInsets.bottom,
                  left: 16,
                  right: 16,
                  top: 16,
                ),
                child: CreatePostWidget(
                  isEditing: isEditing,
                  postToEdit: postToEdit,
                  onPostCreated: (postId) => Navigator.of(context).pop(postId),
                  onPostUpdated: () => Navigator.of(context).pop('updated'),
                  onCancel: () => Navigator.of(context).pop(),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  const CreatePostWidget({
    super.key,
    this.isEditing = false,
    this.postToEdit,
    this.onPostCreated,
    this.onPostUpdated,
    this.onCancel,
  });

  @override
  State<CreatePostWidget> createState() => _CreatePostWidgetState();
}

class _CreatePostWidgetState extends State<CreatePostWidget> {
  final TextEditingController _contentController = TextEditingController();
  final TextEditingController _urlController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  final PostService _postService = PostService();
  final AuthService _authService = AuthService();
  File? _selectedMedia;
  VideoPlayerController? _videoController;
  bool _isVideo = false;
  final ImagePicker _picker = ImagePicker();
  bool _isPosting = false;
  bool _showUrlField = false;

  @override
  void initState() {
    super.initState();

    if (widget.isEditing && widget.postToEdit != null) {
      _contentController.text = widget.postToEdit!.content;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _focusNode.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _contentController.dispose();
    _urlController.dispose();
    _videoController?.dispose();
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
                border: Border(
                  top: BorderSide(
                    color: Theme.of(context).brightness == Brightness.dark
                        ? Colors.white.withOpacity(0.1)
                        : Colors.black.withOpacity(0.1),
                  ),
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
                    leading: Icon(Icons.photo,
                        color: Theme.of(context).iconTheme.color),
                    title: Text('Photo Library',
                        style: TextStyle(
                            color:
                                Theme.of(context).textTheme.bodyLarge?.color)),
                    onTap: () {
                      _pickMedia(ImageSource.gallery, false);
                      Navigator.of(context).pop();
                    },
                  ),
                  ListTile(
                    leading: Icon(Icons.videocam,
                        color: Theme.of(context).iconTheme.color),
                    title: Text('Video Library',
                        style: TextStyle(
                            color:
                                Theme.of(context).textTheme.bodyLarge?.color)),
                    onTap: () {
                      _pickMedia(ImageSource.gallery, true);
                      Navigator.of(context).pop();
                    },
                  ),
                  SizedBox(height: MediaQuery.of(context).padding.bottom + 50),
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
      final XFile? media = isVideo
          ? await _picker.pickVideo(
              source: source, maxDuration: const Duration(minutes: 5))
          : await _picker.pickImage(source: source, imageQuality: 80);

      if (media != null) {
        _videoController?.dispose();
        _videoController = null;

        if (isVideo) {
          final controller = VideoPlayerController.file(File(media.path));
          await controller.initialize();
          await controller.setLooping(true);
          await controller.setVolume(0);
          await controller.play();
          if (mounted) {
            setState(() {
              _selectedMedia = File(media.path);
              _isVideo = true;
              _videoController = controller;
            });
          }
        } else {
          if (mounted) {
            setState(() {
              _selectedMedia = File(media.path);
              _isVideo = false;
            });
          }
        }
      }
    } catch (e) {
      AppBanner.info('Failed to pick media: $e');
    }
  }

  Future<void> _submitPost() async {
    final content = _contentController.text.trim();
    final mediaUrl = _urlController.text.trim();
    if (content.isEmpty && _selectedMedia == null && mediaUrl.isEmpty) {
<<<<<<< Updated upstream
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: TranslatedText(TranslationKeys.fieldRequired),
          backgroundColor: Colors.red,
        ),
      );
=======
      AppBanner.error(TranslationKeys.fieldRequired.tr);
>>>>>>> Stashed changes
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
          if (widget.onPostUpdated != null) {
            widget.onPostUpdated!();
          } else {
            Navigator.of(context).pop('updated');
          }
        }
      } else {
        final result = await _postService.createPost(
          userId: userId,
          content: content,
          mediaFile: _selectedMedia,
          isVideo: _isVideo,
          mediaUrl: _selectedMedia == null ? mediaUrl : null,
        );

        final postId = result['postID'];

        if (mounted) {
          if (widget.onPostCreated != null) {
            widget.onPostCreated!(postId);
          } else {
            Navigator.of(context).pop(postId);
          }
        }
      }
    } catch (e) {
      if (mounted) {
        AppBanner.error('Failed to ${widget.isEditing ? 'update' : 'create'} post: ${e.toString()}');
      }
    } finally {
      if (mounted) {
        setState(() => _isPosting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
          ),
          child: Column(
            children: [
              ListenableBuilder(
                listenable: TranslationService(),
                builder: (context, _) {
                  return TextField(
                    controller: _contentController,
                    focusNode: _focusNode,
                    maxLines: 10,
                    minLines: 5,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: TranslationService()
                          .translate(TranslationKeys.whatOnMind),
                      hintStyle: const TextStyle(color: Colors.white70),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.all(16),
                    ),
                  );
                },
              ),
              const Divider(height: 1, color: Colors.white24),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8.0),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.image, color: Colors.white70),
                      onPressed: () => _showMediaPicker(),
                      tooltip: 'Add Photo/Video',
                    ),
                    IconButton(
                      icon: const Icon(Icons.camera_alt, color: Colors.white70),
                      onPressed: () => _pickMedia(ImageSource.camera, false),
                      tooltip: 'Take Photo',
                    ),
                    IconButton(
                      icon: const Icon(Icons.videocam, color: Colors.white70),
                      onPressed: () => _pickMedia(ImageSource.camera, true),
                      tooltip: 'Take Video',
                    ),
                    IconButton(
                      icon: Icon(
                        Icons.link,
                        color: _showUrlField ? Colors.white : Colors.white70,
                      ),
                      onPressed: () => setState(() => _showUrlField = !_showUrlField),
                      tooltip: 'Add Media URL',
                    ),
                    const Spacer(),
                    IconButton(
                      icon: _isPosting
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                      Colors.white)),
                            )
                          : const Icon(Icons.send, color: Colors.white70),
                      onPressed: _isPosting ? null : _submitPost,
                      tooltip: 'Post',
                    ),
                  ],
                ),
              ),
              if (_showUrlField) ...[
                const Divider(height: 1, color: Colors.white24),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  child: TextField(
                    controller: _urlController,
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                    keyboardType: TextInputType.url,
                    decoration: const InputDecoration(
                      hintText: 'Paste image or video URL…',
                      hintStyle: TextStyle(color: Colors.white38, fontSize: 13),
                      border: InputBorder.none,
                      icon: Icon(Icons.link, color: Colors.white38, size: 18),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        if (_selectedMedia != null)
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
            margin: const EdgeInsets.only(top: 12),
            child: Container(
              constraints: const BoxConstraints(maxHeight: 250),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.3),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    if (_isVideo && _videoController != null)
                      AspectRatio(
                        aspectRatio: _videoController!.value.aspectRatio,
                        child: VideoPlayer(_videoController!),
                      )
                    else if (!_isVideo)
                      Image.file(
                        _selectedMedia!,
                        fit: BoxFit.cover,
                        width: double.infinity,
                        errorBuilder: (context, error, stackTrace) {
                          return Container(
                            height: 180,
                            color: Colors.grey.withOpacity(0.3),
                            child: const Center(
                              child: Icon(Icons.error, color: Colors.grey),
                            ),
                          );
                        },
                      ),
                    Positioned(
                      top: 8,
                      right: 8,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.4),
                              shape: BoxShape.circle,
                              border: Border.all(
                                  color: Colors.white.withOpacity(0.2)),
                            ),
                            child: IconButton(
                              icon: const Icon(Icons.close,
                                  color: Colors.white, size: 20),
                              onPressed: () {
                                setState(() {
                                  _videoController?.dispose();
                                  _videoController = null;
                                  _selectedMedia = null;
                                  _isVideo = false;
                                });
                              },
                              padding: const EdgeInsets.all(8),
                              constraints: const BoxConstraints(),
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (_isVideo &&
                        _videoController != null &&
                        !_videoController!.value.isInitialized)
                      const CircularProgressIndicator(color: Colors.white),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}
