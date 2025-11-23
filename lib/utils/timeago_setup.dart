import 'package:timeago/timeago.dart' as timeago;

void setupTimeago() {
  timeago.setLocaleMessages('en', timeago.EnMessages());
  timeago.setLocaleMessages('en_short', timeago.EnShortMessages());
  // Add other locales here if needed
}
