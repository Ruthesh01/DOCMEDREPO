import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../widgets/loading_skeleton.dart';
import '../widgets/error_state.dart';
import '../widgets/empty_state.dart';
import 'prescription_detail_screen.dart';

class PatientHistoryScreen extends StatefulWidget {
  const PatientHistoryScreen({super.key});

  @override
  State<PatientHistoryScreen> createState() => _PatientHistoryScreenState();
}

class _PatientHistoryScreenState extends State<PatientHistoryScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  List<Map<String, dynamic>> _reports       = [];
  List<Map<String, dynamic>> _prescriptions = [];
  bool _loading = true;
  String? _error;

  String? _searchQuery;
  String? _statusFilter;
  String? _typeFilter;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final repData = await ApiService.instance.getMyReports(
        search: _searchQuery,
        status: _statusFilter,
        fileType: _typeFilter,
      );
      final rxData = await ApiService.instance.getMyPrescriptions();

      setState(() {
        _reports = List<Map<String, dynamic>>.from(
            (repData['reports'] as List).map((e) => Map<String, dynamic>.from(e)));
        _prescriptions = List<Map<String, dynamic>>.from(
            (rxData['prescriptions'] as List).map((e) => Map<String, dynamic>.from(e)));
        _loading = false;
      });
    } on ApiException catch (e) {
      setState(() { _error = e.message; _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Medical History'),
        bottom: TabBar(
          controller: _tabs,
          tabs: const [Tab(text: 'Reports'), Tab(text: 'Prescriptions')],
        ),
      ),
      body: _loading
          ? LoadingSkeleton.dashboard()
          : _error != null
              ? ErrorState(message: _error!, onRetry: _load)
              : RefreshIndicator(
                  onRefresh: _load,
                  child: TabBarView(
                    controller: _tabs,
                    children: [_reportsList(), _prescriptionsList()],
                  ),
                ),
    );
  }

  Widget _reportsList() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              TextField(
                decoration: InputDecoration(
                  hintText: 'Search description...',
                  prefixIcon: const Icon(Icons.search),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  contentPadding: EdgeInsets.zero,
                ),
                onSubmitted: (val) {
                  _searchQuery = val.trim();
                  _load();
                },
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String?>(
                      initialValue: _statusFilter,
                      decoration: const InputDecoration(labelText: 'Status', isDense: true, border: OutlineInputBorder()),
                      items: const [
                        DropdownMenuItem(value: null, child: Text('All')),
                        DropdownMenuItem(value: 'complete', child: Text('Complete')),
                        DropdownMenuItem(value: 'processing', child: Text('Processing')),
                        DropdownMenuItem(value: 'pending', child: Text('Pending')),
                        DropdownMenuItem(value: 'failed', child: Text('Failed')),
                      ],
                      onChanged: (v) {
                        _statusFilter = v;
                        _load();
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<String?>(
                      initialValue: _typeFilter,
                      decoration: const InputDecoration(labelText: 'File Type', isDense: true, border: OutlineInputBorder()),
                      items: const [
                        DropdownMenuItem(value: null, child: Text('All')),
                        DropdownMenuItem(value: 'pdf', child: Text('PDF')),
                        DropdownMenuItem(value: 'jpg', child: Text('JPG')),
                        DropdownMenuItem(value: 'png', child: Text('PNG')),
                      ],
                      onChanged: (v) {
                        _typeFilter = v;
                        _load();
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        Expanded(
          child: _reports.isEmpty
              ? const EmptyState(
                  icon: Icons.search_off,
                  title: 'No reports found',
                  message: 'Try adjusting your filters',
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  itemCount: _reports.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) => _ReportTile(report: _reports[i]),
                ),
        ),
      ],
    );
  }

  Widget _prescriptionsList() {
    if (_prescriptions.isEmpty) {
      return const EmptyState(
        icon: Icons.medication_outlined,
        title: 'No prescriptions',
        message: 'Prescriptions from your doctors will appear here.',
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _prescriptions.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) => _PrescriptionTile(rx: _prescriptions[i]),
    );
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }
}

class _ReportTile extends StatelessWidget {
  final Map<String, dynamic> report;
  const _ReportTile({required this.report});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = report['analysisStatus'] as String? ?? 'pending';
    return Card(
      child: ExpansionTile(
        leading: Icon(Icons.description_outlined, color: theme.colorScheme.primary),
        title: Text(report['description'] as String? ?? 'Medical Report',
            style: theme.textTheme.titleSmall),
        subtitle: Text('${(report['fileType'] as String? ?? '').toUpperCase()} · $status'),
        children: [
          if (report['aiSummary'] != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Divider(),
                  Text('AI Summary', style: theme.textTheme.labelSmall),
                  const SizedBox(height: 6),
                  Text(
                    (report['aiSummary'] as Map)['summaryForPatient'] as String? ?? '',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _PrescriptionTile extends StatelessWidget {
  final Map<String, dynamic> rx;
  const _PrescriptionTile({required this.rx});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final doctor = rx['doctorId'] as Map<String, dynamic>?;
    final meds   = rx['medications'] as List? ?? [];
    return Card(
      child: ListTile(
        leading: Icon(Icons.medication_outlined, color: theme.colorScheme.secondary),
        title: Text('Dr. ${doctor?['name'] ?? 'Unknown'}',
            style: theme.textTheme.titleSmall),
        subtitle: Text('${meds.length} medication(s) · ${doctor?['specialization'] as String? ?? ''}'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => PrescriptionDetailScreen(prescription: rx),
            ),
          );
        },
      ),
    );
  }
}
