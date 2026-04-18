import 'dart:async';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/api_service.dart';
import '../widgets/error_state.dart';

class ReportDetailScreen extends StatefulWidget {
  final String reportId;
  final bool isDoctorView; // true if accessed by doctor
  final String? qrToken;

  const ReportDetailScreen({
    super.key,
    required this.reportId,
    this.isDoctorView = false,
    this.qrToken,
  });

  @override
  State<ReportDetailScreen> createState() => _ReportDetailScreenState();
}

class _ReportDetailScreenState extends State<ReportDetailScreen> {
  Map<String, dynamic>? _report;
  String? _pdfUrl;
  bool _loading = true;
  String? _error;
  Timer? _pollingTimer;

  @override
  void initState() {
    super.initState();
    _fetchReportDetails();
  }

  Future<void> _fetchReportDetails() async {
    try {
      final results = await Future.wait([
        ApiService.instance.getReport(widget.reportId, qrToken: widget.qrToken),
        ApiService.instance.getReportUrl(widget.reportId, qrToken: widget.qrToken),
      ]);

      if (mounted) {
        setState(() {
          _report = results[0]['report'] as Map<String, dynamic>;
          _pdfUrl = results[1]['url'] as String;
          _loading = false;
          _error = null;
        });
        _setupPolling();
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          _loading = false;
        });
      }
    }
  }

  void _setupPolling() {
    final status = _report?['analysisStatus'] as String? ?? 'pending';
    if (status == 'pending' || status == 'processing') {
      _pollingTimer?.cancel();
      _pollingTimer = Timer.periodic(const Duration(seconds: 10), (timer) async {
        try {
          final res = await ApiService.instance.getReportStatus(widget.reportId, qrToken: widget.qrToken);
          final newStatus = res['analysisStatus'] as String?;
          if (newStatus == 'complete' || newStatus == 'failed') {
            timer.cancel();
            _fetchReportDetails(); // Re-fetch full report to get the summary
          } else if (mounted) {
            setState(() {
              if (_report != null) {
                _report!['analysisStatus'] = newStatus;
              }
            });
          }
        } catch (_) {}
      });
    } else {
      _pollingTimer?.cancel();
    }
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    super.dispose();
  }

  Future<void> _openPdf() async {
    if (_pdfUrl == null) return;
    final uri = Uri.parse(_pdfUrl!);
    if (!await launchUrl(uri)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open file')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (_error != null && _report == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Report Details')),
        body: ErrorState(message: _error!, onRetry: _fetchReportDetails),
      );
    }

    final theme = Theme.of(context);
    final report = _report!;
    final status = report['analysisStatus'] as String? ?? 'pending';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Report Details'),
        actions: [
          if (_pdfUrl != null)
            IconButton(
              icon: const Icon(Icons.open_in_new_rounded),
              tooltip: 'View Original File',
              onPressed: _openPdf,
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(theme, report),
            const SizedBox(height: 24),
            _buildStatusCard(theme, status),
            const SizedBox(height: 24),
            if (status == 'complete' && report['aiSummary'] != null)
              _buildCompleteView(theme, report['aiSummary'] as Map<String, dynamic>),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(ThemeData theme, Map<String, dynamic> report) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(report['description'] as String? ?? 'Medical Report',
            style: theme.textTheme.headlineSmall),
        const SizedBox(height: 8),
        Text('Type: ${report['fileType']?.toString().toUpperCase() ?? 'UNKNOWN'}',
            style: theme.textTheme.bodyMedium?.copyWith(color: Colors.grey[600])),
      ],
    );
  }

  Widget _buildStatusCard(ThemeData theme, String status) {
    if (status == 'complete') return const SizedBox.shrink();

    if (status == 'failed') {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: theme.colorScheme.error.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: theme.colorScheme.error.withValues(alpha: 0.3)),
        ),
        child: Column(
          children: [
            Icon(Icons.error_outline_rounded, color: theme.colorScheme.error, size: 40),
            const SizedBox(height: 12),
            Text('Analysis Failed',
                style: theme.textTheme.titleMedium?.copyWith(color: theme.colorScheme.error)),
            const SizedBox(height: 8),
            Text('We could not analyse your report. Please try re-uploading.',
                textAlign: TextAlign.center, style: theme.textTheme.bodyMedium),
          ],
        ),
      );
    }

    // pending or processing
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          Text('Analysing Report', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Text('Check back soon...', style: theme.textTheme.bodyMedium),
        ],
      ),
    );
  }

  Widget _buildCompleteView(ThemeData theme, Map<String, dynamic> aiSummary) {
    final patientSummary = aiSummary['summaryForPatient'] as String? ?? '';
    final doctorSummary = aiSummary['summaryForDoctor'] as String? ?? '';
    final summaryText = widget.isDoctorView ? doctorSummary : patientSummary;

    final diagnoses = List<String>.from(aiSummary['diagnoses'] as List? ?? []);
    final medications = List<String>.from(aiSummary['medicationsMentioned'] as List? ?? []);
    final abnormal = List<Map<String, dynamic>>.from(
        (aiSummary['abnormalValues'] as List? ?? []).map((e) => Map<String, dynamic>.from(e)));
    final score = (aiSummary['confidenceScore'] as num?)?.toDouble() ?? 0.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildConfidenceBar(theme, score),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: theme.colorScheme.primary.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: theme.colorScheme.primary.withValues(alpha: 0.15)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.auto_awesome, color: theme.colorScheme.primary, size: 20),
                  const SizedBox(width: 8),
                  Text('AI Summary', style: theme.textTheme.titleMedium),
                ],
              ),
              const SizedBox(height: 12),
              Text(summaryText, style: theme.textTheme.bodyLarge?.copyWith(height: 1.5)),
            ],
          ),
        ),
        if (diagnoses.isNotEmpty) ...[
          const SizedBox(height: 24),
          Text('Diagnoses', style: theme.textTheme.titleMedium),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: diagnoses
                .map((d) => Chip(
                      label: Text(d),
                      backgroundColor: theme.colorScheme.secondary.withValues(alpha: 0.1),
                    ))
                .toList(),
          ),
        ],
        if (abnormal.isNotEmpty) ...[
          const SizedBox(height: 24),
          Text('Abnormal Values', style: theme.textTheme.titleMedium),
          const SizedBox(height: 12),
          _buildAbnormalTable(theme, abnormal),
        ],
        if (medications.isNotEmpty) ...[
          const SizedBox(height: 24),
          Text('Medications Mentioned', style: theme.textTheme.titleMedium),
          const SizedBox(height: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: medications
                .map((m) => Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        children: [
                          const Icon(Icons.circle, size: 6, color: Colors.grey),
                          const SizedBox(width: 8),
                          Expanded(child: Text(m, style: theme.textTheme.bodyMedium)),
                        ],
                      ),
                    ))
                .toList(),
          ),
        ],
      ],
    );
  }

  Widget _buildConfidenceBar(ThemeData theme, double score) {
    Color color;
    if (score >= 0.8) {
      color = Colors.green;
    } else if (score >= 0.6) {
      color = Colors.orange;
    } else {
      color = Colors.red;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('AI Confidence Score', style: theme.textTheme.titleSmall),
            Text('${(score * 100).toInt()}%',
                style: theme.textTheme.titleSmall?.copyWith(color: color)),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: score,
            backgroundColor: Colors.grey[200],
            valueColor: AlwaysStoppedAnimation<Color>(color),
            minHeight: 8,
          ),
        ),
      ],
    );
  }

  Widget _buildAbnormalTable(ThemeData theme, List<Map<String, dynamic>> abnormal) {
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: Table(
        columnWidths: const {
          0: FlexColumnWidth(2),
          1: FlexColumnWidth(1),
          2: IntrinsicColumnWidth(),
        },
        children: [
          TableRow(
            decoration: BoxDecoration(
              color: Colors.grey[100],
              borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            ),
            children: [
              _buildTableCell('Test', isHeader: true),
              _buildTableCell('Value', isHeader: true),
              _buildTableCell('Flag', isHeader: true),
            ],
          ),
          ...abnormal.map((a) {
            final flag = a['flag'] as String? ?? '';
            Color flagColor = Colors.grey;
            if (flag == 'HIGH') flagColor = Colors.red;
            if (flag == 'LOW') flagColor = Colors.blue;

            return TableRow(
              decoration: BoxDecoration(border: Border(top: BorderSide(color: Colors.grey[200]!))),
              children: [
                _buildTableCell(a['test'] as String? ?? ''),
                _buildTableCell(a['value'] as String? ?? ''),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: flagColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      flag,
                      style: TextStyle(color: flagColor, fontSize: 11, fontWeight: FontWeight.bold),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ],
            );
          }),
        ],
      ),
    );
  }

  Widget _buildTableCell(String text, {bool isHeader = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      child: Text(
        text,
        style: TextStyle(
          fontWeight: isHeader ? FontWeight.bold : FontWeight.normal,
          fontSize: isHeader ? 13 : 14,
          color: isHeader ? Colors.grey[700] : Colors.black87,
        ),
      ),
    );
  }
}
