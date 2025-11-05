import 'package:flutter/material.dart';
import 'dart:ui';
import 'package:cached_network_image/cached_network_image.dart';
import '../services/friend_service.dart';
import '../services/auth_service.dart';
import '../models/friend.dart';
import '../screens/chat_screen.dart';

class ChatListModal extends StatefulWidget {
  const ChatListModal({super.key});

  @override
  State<ChatListModal> createState() => _ChatListModalState();
}

class _ChatListModalState extends State<ChatListModal> {
  final FriendService _friendService = FriendService();
  final AuthService _authService = AuthService();

  List<Friend> _friends = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadFriends();
  }

  Future<void> _loadFriends() async {
    final userId = await _authService.getStoredUserId();
    if (!mounted) return;
    if (userId == null) {
      setState(() {
        _friends = [];
        _isLoading = false;
      });
      return;
    }

    // Load cached data first, then update if changes detected
    final friends = await _friendService.fetchFriendsForUser(
      userId: userId,
      onUpdated: (updatedFriends) {
        // Update UI when friends list changes in background
        if (mounted) {
          setState(() {
            _friends = updatedFriends;
          });
        }
      },
    );
    if (!mounted) return;
    setState(() {
      _friends = friends;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          color: Colors.white.withOpacity(0.05),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                    child: Container(
                      color: Colors.white.withOpacity(0.12),
                      child: const TextField(
                        decoration: InputDecoration(
                          hintText: 'Search friends...',
                          hintStyle: TextStyle(color: Colors.white70),
                          border: InputBorder.none,
                          prefixIcon: Icon(Icons.search, color: Colors.white),
                          contentPadding: EdgeInsets.symmetric(vertical: 14),
                        ),
                        style: TextStyle(color: Colors.white),
                      ),
                    ),
                  ),
                ),
              ),
              if (_isLoading)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: Image.asset(
                      'assets/images/icon.png',
                      width: 64,
                      height: 64,
                      fit: BoxFit.contain,
                    ),
                  ),
                )
              else
                Flexible(
                  child: _friends.isEmpty
                      ? const Padding(
                          padding: EdgeInsets.all(16.0),
                          child: Center(
                            child: Text(
                              'No friends found',
                              style: TextStyle(color: Colors.white70),
                            ),
                          ),
                        )
                      : RefreshIndicator(
                          onRefresh: _loadFriends,
                          child: ListView.separated(
                            shrinkWrap: true,
                            itemCount: _friends.length,
                            separatorBuilder: (context, index) => const SizedBox(height: 8),
                            itemBuilder: (context, index) {
                              final friend = _friends[index];
                              return Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 16),
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(0.10),
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  child: ListTile(
                                    leading: CircleAvatar(
                                      radius: 22,
                                      backgroundColor: Colors.white.withOpacity(0.2),
                                      child: friend.avatar.isNotEmpty
                                          ? ClipOval(
                                              child: CachedNetworkImage(
                                                imageUrl: friend.avatar,
                                                width: 44,
                                                height: 44,
                                                fit: BoxFit.cover,
                                                placeholder: (context, url) => Image.asset(
                                                  'assets/images/icon.png',
                                                  width: 44,
                                                  height: 44,
                                                  fit: BoxFit.cover,
                                                ),
                                                errorWidget: (context, url, error) => Image.asset(
                                                  'assets/images/icon.png',
                                                  width: 44,
                                                  height: 44,
                                                  fit: BoxFit.cover,
                                                ),
                                              ),
                                            )
                                          : Image.asset(
                                              'assets/images/icon.png',
                                              width: 44,
                                              height: 44,
                                              fit: BoxFit.cover,
                                            ),
                                    ),
                                    title: Text(
                                      friend.nickname.isNotEmpty ? friend.nickname : friend.username,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                      ),
                                    ),
                                    subtitle: friend.nickname.isNotEmpty
                                        ? Text(
                                            '@${friend.username}',
                                            style: const TextStyle(
                                              color: Colors.white70,
                                              fontSize: 13,
                                            ),
                                          )
                                        : null,
                                    trailing: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Container(
                                          width: 10,
                                          height: 10,
                                          decoration: BoxDecoration(
                                            color: friend.online ? Colors.greenAccent : Colors.white,
                                            shape: BoxShape.circle,
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        Text(
                                          friend.online ? 'Online' : 'Offline',
                                          style: TextStyle(
                                            color: friend.online ? Colors.greenAccent : Colors.white,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ],
                                    ),
                                    onTap: () {
                                      Navigator.of(context).pop(); // Close the modal first
                                      Navigator.of(context).push(
                                        MaterialPageRoute(
                                          builder: (context) => ChatScreen(
                                            friend: friend,
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}