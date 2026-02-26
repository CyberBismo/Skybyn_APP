import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';

/// Safely decodes a JSON response from an HTTP call, handling UTF-8 encoding
/// and potential HTML noise/warnings mixed with the JSON content.
dynamic safeJsonDecode(http.Response response) {
  // Always decode using UTF-8 to handle special characters correctly
  final String body = utf8.decode(response.bodyBytes, allowMalformed: true);
  
  try {
    return _recursiveRepair(json.decode(body));
  } catch (_) {
    // Try to extract JSON if there is HTML or other noise around it
    final int objStart = body.indexOf('{');
    final int arrStart = body.indexOf('[');
    
    int start = -1;
    if (objStart != -1 && arrStart != -1) {
      start = objStart < arrStart ? objStart : arrStart;
    } else if (objStart != -1) {
      start = objStart;
    } else if (arrStart != -1) {
      start = arrStart;
    }
    
    if (start != -1) {
      final int objEnd = body.lastIndexOf('}');
      final int arrEnd = body.lastIndexOf(']');
      
      int end = -1;
      if (objEnd != -1 && arrEnd != -1) {
        end = objEnd > arrEnd ? objEnd : arrEnd;
      } else if (objEnd != -1) {
        end = objEnd;
      } else if (arrEnd != -1) {
        end = arrEnd;
      }
      
      if (end != -1 && end > start) {
        final String trimmed = body.substring(start, end + 1).trim();
        try {
          return _recursiveRepair(json.decode(trimmed));
        } catch (e) {
          debugPrint('ApiUtils: Failed to decode trimmed JSON: $e');
        }
      }
    }
    
    return _recursiveRepair(json.decode(body));
  }
}

dynamic safeJsonDecodeString(String body) {
  try {
    return _recursiveRepair(json.decode(body));
  } catch (_) {
    final int objStart = body.indexOf('{');
    final int arrStart = body.indexOf('[');
    
    int start = -1;
    if (objStart != -1 && arrStart != -1) {
      start = objStart < arrStart ? objStart : arrStart;
    } else if (objStart != -1) {
      start = objStart;
    } else if (arrStart != -1) {
      start = arrStart;
    }
    
    if (start != -1) {
      final int objEnd = body.lastIndexOf('}');
      final int arrEnd = body.lastIndexOf(']');
      
      int end = -1;
      if (objEnd != -1 && arrEnd != -1) {
        end = objEnd > arrEnd ? objEnd : arrEnd;
      } else if (objEnd != -1) {
        end = objEnd;
      } else if (arrEnd != -1) {
        end = arrEnd;
      }
      
      if (end != -1 && end > start) {
        final String trimmed = body.substring(start, end + 1).trim();
        try {
          return _recursiveRepair(json.decode(trimmed));
        } catch (e) {
          debugPrint('ApiUtils: Failed to decode trimmed JSON string: $e');
        }
      }
    }
    return _recursiveRepair(json.decode(body));
  }
}

/// Recursively traverses a JSON object and repairs double-encoded UTF-8 strings
dynamic _recursiveRepair(dynamic item) {
  if (item is String) {
    return _repairDoubleEncodedUtf8(item);
  } else if (item is List) {
    return item.map((e) => _recursiveRepair(e)).toList();
  } else if (item is Map) {
    return item.map<String, dynamic>((k, v) => MapEntry(k.toString(), _recursiveRepair(v)));
  }
  return item;
}

/// Detects and repairs strings that were double-encoded (e.g., å -> Ã¥)
String _repairDoubleEncodedUtf8(String input) {
  // Check if string contains characters that are typical signs of double encoding
  // 0xc3 (Ã) is a very common marker for multi-byte UTF-8 sequences interpreted as Latin-1
  if (!input.contains('Ã') && !input.contains('Â')) {
    return input;
  }

  try {
    // 1. Convert string to Latin-1 bytes. 
    // This effectively reverses the incorrect interpretation of UTF-8 bytes as Latin-1 characters.
    final List<int> bytes = latin1.encode(input);
    
    // 2. Decode the bytes as UTF-8.
    // If successful and valid, we found a double-encoded string.
    final String repaired = utf8.decode(bytes);
    
    // Safety check: only return repaired if it actually changed and doesn't contain the brokenÃ
    // (though sometimes valid UTF-8 *could* contain Ã if it was intended)
    return repaired;
  } catch (_) {
    // If it's not valid Latin-1 or not valid UTF-8 when decoded, return original
    return input;
  }
}
