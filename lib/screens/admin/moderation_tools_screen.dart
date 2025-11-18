import 'package:flutter/material.dart';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import '../../widgets/background_gradient.dart';
import '../../widgets/custom_app_bar.dart';
import '../../models/report.dart';
import '../../services/auth_service.dart';
import '../../config/constants.dart';
import '../../utils/translation_keys.dart';
import '../../widgets/translated_text.dart';
import '../../services/translation_service.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

class ModerationToolsScreen extends StatefulWidget {
  const ModerationToolsScreen({super.key});

  @override
  State<ModerationToolsScreen> createState() => _ModerationToolsScreenState();
}

class _ModerationToolsScreenState extends State<ModerationToolsScreen> {
  List<Report> _reports = [];
  bool _isLoading = false;
  String _filterStatus = 'all'; // all, pending, resolved
  int _totalReports = 0;
  int _currentOffset = 0;
  final int _limit = 50;
  String? _currentUserId;

  // HTTP client
  static http.Client? _httpClient;
  static http.Client get _client {
    if (_httpClient == null) {
      _httpClient = _createHttpClient();
    }
    return _httpClient!;
  }

  static http.Client _createHttpClient() {
    HttpClient httpClient;
    if (HttpOverrides.current != null) {
      httpClient = HttpOverrides.current!.createHttpClient(null);
    } else {
      httpClient = HttpClient();
    }
    httpClient.userAgent = 'Skybyn-App/1.0';
    httpClient.connectionTimeout = const Duration(seconds: 30);
    return IOClient(httpClient);
  }

  @override
  void initState() {
    super.initState();
    _loadCurrentUserId();
    _loadReports();
  }

  Future<void> _loadCurrentUserId() async {
    final authService = AuthService();
    _currentUserId = await authService.getStoredUserId();
  }

  Future<void> _loadReports({bool reset = false}) async {
    if (reset) {
      _currentOffset = 0;
      _reports.clear();
    }

    setState(() => _isLoading = true);

    try {
      final response = await _client.post(
        Uri.parse(ApiConstants.adminReports),
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
          'X-API-Key': ApiConstants.apiKey,
        },
        body: {
          'userID': _currentUserId ?? '',
          'action': 'list',
          'status': _filterStatus,
          'limit': _limit.toString(),
          'offset': _currentOffset.toString(),
        },
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true && data['data'] != null) {
          final reportsData = data['data']['reports'] as List;
          final newReports = reportsData.map((r) => Report.fromJson(r)).toList();
          
          setState(() {
            if (reset) {
              _reports = newReports;
            } else {
              _reports.addAll(newReports);
            }
            _totalReports = data['data']['total'] ?? 0;
            _currentOffset += newReports.length;
            _isLoading = false;
          });
        } else {
          throw Exception(data['message'] ?? 'Failed to load reports');
        }
      } else {
        throw Exception('Server error: ${response.statusCode}');
      }
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading reports: $e')),
        );
      }
    }
  }

  Future<void> _resolveReport(Report report) async {
    try {
      final response = await _client.post(
        Uri.parse(ApiConstants.adminReports),
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
          'X-API-Key': ApiConstants.apiKey,
        },
        body: {
          'userID': _currentUserId ?? '',
          'action': 'resolve',
          'report_id': report.id.toString(),
        },
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Report resolved successfully')),
            );
            _loadReports(reset: true);
          }
        } else {
          throw Exception(data['message'] ?? 'Failed to resolve report');
        }
      } else {
        throw Exception('Server error: ${response.statusCode}');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  void _showReportDetails(Report report) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: Colors.grey[900],
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Report Details',
                  style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildDetailRow('Reporter', report.reporterDisplayName),
            _buildDetailRow('Reported User', report.reportedDisplayName),
            _buildDetailRow('Date', DateFormat('yyyy-MM-dd HH:mm').format(DateTime.fromMillisecondsSinceEpoch(report.date * 1000))),
            _buildDetailRow('Status', report.isResolved ? 'Resolved' : 'Pending'),
            const SizedBox(height: 12),
            const Text(
              'Report Content:',
              style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                report.content.isNotEmpty ? report.content : 'No content provided',
                style: const TextStyle(color: Colors.white),
              ),
            ),
            const SizedBox(height: 16),
            if (!report.isResolved)
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context);
                    _resolveReport(report);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                  ),
                  child: const Text('Mark as Resolved'),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              '$label:',
              style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final statusBarHeight = mediaQuery.padding.top;
    final appBarHeight = 60.0;

    return Scaffold(
      body: Stack(
        children: [
          const BackgroundGradient(),
          Column(
            children: [
              CustomAppBar(
                logoPath: 'assets/images/logo_faded_clean.png',
                onLogoPressed: () => Navigator.pop(context),
                appBarHeight: appBarHeight,
              ),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(
                    top: statusBarHeight,
                    left: 16,
                    right: 16,
                    bottom: 16,
                  ),
                  child: Column(
                    children: [
                      const SizedBox(height: 20),
                      TranslatedText(
                        TranslationKeys.moderationTools,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),
                      // Filter buttons
                      Row(
                        children: [
                          Expanded(
                            child: _buildFilterButton('All', 'all'),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _buildFilterButton('Pending', 'pending'),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _buildFilterButton('Resolved', 'resolved'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      if (_isLoading && _reports.isEmpty)
                        const Expanded(
                          child: Center(child: CircularProgressIndicator()),
                        )
                      else if (_reports.isEmpty)
                        Expanded(
                          child: Center(
                            child: Text(
                              'No reports found',
                              style: TextStyle(color: Colors.white.withOpacity(0.7)),
                            ),
                          ),
                        )
                      else
                        Expanded(
                          child: ListView.builder(
                            itemCount: _reports.length + (_isLoading ? 1 : 0),
                            itemBuilder: (context, index) {
                              if (index == _reports.length) {
                                return const Center(
                                  child: Padding(
                                    padding: EdgeInsets.all(16.0),
                                    child: CircularProgressIndicator(),
                                  ),
                                );
                              }
                              final report = _reports[index];
                              return _buildReportCard(report);
                            },
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFilterButton(String label, String status) {
    final isSelected = _filterStatus == status;
    return GestureDetector(
      onTap: () {
        setState(() {
          _filterStatus = status;
        });
        _loadReports(reset: true);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? Colors.blue : Colors.white.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? Colors.blue : Colors.white.withOpacity(0.2),
          ),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              color: isSelected ? Colors.white : Colors.white70,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildReportCard(Report report) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: report.isResolved 
              ? Colors.green.withOpacity(0.3) 
              : Colors.orange.withOpacity(0.3),
          width: report.isResolved ? 1 : 2,
        ),
      ),
      child: ListTile(
        title: Text(
          'Reported: ${report.reportedDisplayName}',
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'By: ${report.reporterDisplayName}',
              style: TextStyle(color: Colors.white.withOpacity(0.7)),
            ),
            const SizedBox(height: 4),
            if (report.content.isNotEmpty)
              Text(
                report.content.length > 50 
                    ? '${report.content.substring(0, 50)}...' 
                    : report.content,
                style: TextStyle(color: Colors.white.withOpacity(0.6)),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            const SizedBox(height: 4),
            Row(
              children: [
                Text(
                  DateFormat('MMM dd, yyyy').format(DateTime.fromMillisecondsSinceEpoch(report.date * 1000)),
                  style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: report.isResolved ? Colors.green : Colors.orange,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    report.isResolved ? 'RESOLVED' : 'PENDING',
                    style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ],
        ),
        trailing: IconButton(
          icon: const Icon(Icons.arrow_forward_ios, color: Colors.white, size: 16),
          onPressed: () => _showReportDetails(report),
        ),
        onTap: () => _showReportDetails(report),
      ),
    );
  }
}

