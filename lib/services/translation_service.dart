import 'package:flutter/foundation.dart';
import 'package:easy_localization/easy_localization.dart' as ez;

class TranslationService extends ChangeNotifier {
  static final TranslationService _instance = TranslationService._internal();
  factory TranslationService() => _instance;
  TranslationService._internal();

  bool _isInitialized = false;

  Future<void> initialize() async {
    if (_isInitialized) return;
    _isInitialized = true;
    notifyListeners();
  }

  /// Translate a key using easy_localization.
  String translate(String key) {
    return ez.tr(key);
  }

  bool get isInitialized => _isInitialized;

  // Stubs for language switching (single language for now)
  static const List<String> supportedLanguages = ['en'];
  static const Map<String, String> languageNames = {'en': 'English'};
  String get currentLanguage => 'en';
  String getLanguageName(String code) => languageNames[code] ?? code;
  Future<void> setLanguage(String languageCode) async {}
  Future<void> clearCache() async {}
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
  static const String groupsBenefitMeetingGround =
      'groups_benefit_meeting_ground';
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
  static const String or = 'or';
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
  static const String loginFailedCheckCredentials =
      'login_failed_check_credentials';
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
  static const String securityQuestionsUpdateSuccess =
      'security_questions_update_success';
  static const String securityQuestionsUpdateError =
      'security_questions_update_error';
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
  static const String hide = 'hide';
  static const String hidePost = 'hide_post';
  static const String confirmHidePostMessage = 'confirm_hide_post_message';
  static const String postHiddenSuccessfully = 'post_hidden_successfully';
  static const String editComment = 'edit_comment';
  static const String reportPost = 'report_post';
  static const String confirmReportPostMessage = 'confirm_report_post_message';
  static const String postReportedSuccessfully = 'post_reported_successfully';
  static const String reportComment = 'report_comment';
  static const String confirmReportCommentMessage =
      'confirm_report_comment_message';
  static const String commentReportedSuccessfully =
      'comment_reported_successfully';
  static const String failedToHidePost = 'failed_to_hide_post';
  static const String failedToReportPost = 'failed_to_report_post';
  static const String failedToReportComment = 'failed_to_report_comment';
  static const String failedToUpdateComment = 'failed_to_update_comment';
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
  static const String signInWithGoogle = 'sign_in_with_google';
  static const String postLinkCopiedToClipboard =
      'post_link_copied_to_clipboard';
  static const String commentPostedButCouldNotLoadDetails =
      'comment_posted_but_could_not_load_details';
  static const String failedToPostComment = 'failed_to_post_comment';
  static const String failedToDeleteComment = 'failed_to_delete_comment';
  static const String failedToDeletePost = 'failed_to_delete_post';
  static const String allComments = 'all_comments';
  static const String addCommentPlaceholder = 'add_comment';

  // Comments
  static const String addComment = 'add_comment';
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
  static const String automaticallyFollowDeviceTheme =
      'automatically_follow_device_theme';
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
  static const String postCreatedButCouldNotLoadDetails =
      'post_created_but_could_not_load_details';
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
  static const String pleaseLogInToFindFriends =
      'please_log_in_to_find_friends';
  static const String unableToGetLocation = 'unable_to_get_location';
  static const String foundUsersNearby = 'found_users_nearby';
  static const String errorFindingFriends = 'error_finding_friends';
  static const String noMessages = 'no_messages';
  static const String installPermissionRequired = 'install_permission_required';
  static const String installPermissionDeniedMessage =
      'install_permission_denied_message';
  static const String permissionNotGranted = 'permission_not_granted';
  static const String downloadUrlNotAvailable = 'download_url_not_available';
  static const String updateFailed = 'update_failed';
  static const String failedToInstallUpdate = 'failed_to_install_update';
  static const String permissionDeniedCannotCheckUpdates =
      'permission_denied_cannot_check_updates';
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
  static const String totalStorageUsage = 'total_storage_usage';

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
  static const String microphonePermissionRequired =
      'microphone_permission_required';
  static const String microphonePermissionMessage =
      'microphone_permission_message';
  static const String cameraPermissionRequired = 'camera_permission_required';
  static const String cameraPermissionMessage = 'camera_permission_message';
  static const String permissionRequiredTitle = 'permission_required_title';
  static const String permissionPermanentlyDeniedMessage =
      'permission_permanently_denied_message';

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
  static const String updateCheckFailed = 'update_check_failed';
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

  // Relationship Statuses
  static const String relSingle = 'rel_single';
  static const String relInRelationship = 'rel_in_relationship';
  static const String relComplicated = 'rel_complicated';
  static const String relDivorced = 'rel_divorced';
  static const String relOther = 'rel_other';
  static const String relWidowed = 'rel_widowed';
  static const String relEngaged = 'rel_engaged';
  static const String relMarried = 'rel_married';
  static const String relSeparated = 'rel_separated';

  static const String allow = 'allow';
  static const String locationPermissionRationale =
      'location_permission_rationale';
}
