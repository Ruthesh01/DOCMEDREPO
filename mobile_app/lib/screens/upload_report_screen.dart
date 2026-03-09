import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../services/api_service.dart';
import '../widgets/app_button.dart';

class UploadReportScreen extends StatefulWidget {
  const UploadReportScreen({super.key});

  @override
  State<UploadReportScreen> createState() => _UploadReportScreenState();
}

class _UploadReportScreenState extends State<UploadReportScreen> {
  PlatformFile? _selectedFile;
  String? _fileError;
  final _descCtrl = TextEditingController();
  bool   _uploading = false;
  bool   _uploaded  = false;
  String? _uploadError;

  static const _maxBytes = 10 * 1024 * 1024; // 10 MB
  static const _allowedExtensions = ['pdf', 'jpg', 'jpeg', 'png'];

  Future<void> _pickFile() async {
    setState(() { _fileError = null; _uploadError = null; });

    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: _allowedExtensions,
      allowMultiple: false,
      withData: kIsWeb,
    );

    if (result == null || result.files.isEmpty) return;

    final picked = result.files.first;
    if (picked.size > _maxBytes) {
      setState(() => _fileError = 'File exceeds the 10MB size limit.');
      return;
    }

    setState(() {
      _selectedFile = picked;
    });
  }

  Future<void> _upload() async {
    if (_selectedFile == null) {
      setState(() => _fileError = 'Please select a file first.');
      return;
    }
    setState(() { _uploading = true; _uploadError = null; });

    try {
      await ApiService.instance.uploadReport(
        filePath:    kIsWeb ? null : _selectedFile!.path,
        fileBytes:   _selectedFile!.bytes,
        fileName:    _selectedFile!.name,
        description: _descCtrl.text.trim(),
      );
      if (mounted) setState(() { _uploading = false; _uploaded = true; });
    } on ApiException catch (e) {
      if (mounted) setState(() { _uploading = false; _uploadError = e.message; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Upload Report')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: _uploaded ? _successView(theme) : _uploadForm(theme),
      ),
    );
  }

  Widget _uploadForm(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Upload Medical Report', style: theme.textTheme.titleLarge),
        const SizedBox(height: 4),
        Text('Supported formats: PDF, JPG, PNG · Max 10MB',
            style: theme.textTheme.bodySmall),
        const SizedBox(height: 24),

        // File picker area
        GestureDetector(
          onTap: _uploading ? null : _pickFile,
          child: Container(
            height: 140,
            decoration: BoxDecoration(
              border: Border.all(
                color: _fileError != null
                    ? theme.colorScheme.error
                    : theme.colorScheme.outline.withOpacity(0.4),
                width: 1.5,
                style: BorderStyle.solid,
              ),
              borderRadius: BorderRadius.circular(16),
              color: theme.colorScheme.surfaceVariant.withOpacity(0.3),
            ),
            child: _selectedFile == null
                ? Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.upload_file_outlined,
                          size: 36, color: theme.colorScheme.primary),
                      const SizedBox(height: 10),
                      Text('Tap to select a file',
                          style: theme.textTheme.titleSmall),
                      const SizedBox(height: 4),
                      Text('PDF, JPG, or PNG',
                          style: theme.textTheme.bodySmall),
                    ],
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.insert_drive_file_outlined,
                          size: 28, color: theme.colorScheme.primary),
                      const SizedBox(width: 12),
                      Flexible(
                        child: Text(_selectedFile?.name ?? '',
                            style: theme.textTheme.titleSmall,
                            overflow: TextOverflow.ellipsis),
                      ),
                      const SizedBox(width: 12),
                      IconButton(
                        icon: const Icon(Icons.close, size: 20),
                        onPressed: () => setState(() {
                          _selectedFile = null;
                        }),
                      ),
                    ],
                  ),
          ),
        ),
        if (_fileError != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(_fileError!,
                style: TextStyle(color: theme.colorScheme.error, fontSize: 12)),
          ),

        const SizedBox(height: 20),

        TextFormField(
          controller: _descCtrl,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: 'Description (optional)',
            hintText: 'e.g. Blood test results, X-Ray, MRI scan...',
            alignLabelWithHint: true,
          ),
        ),

        const SizedBox(height: 16),

        if (_uploadError != null)
          Container(
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.errorContainer,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(_uploadError!,
                style: TextStyle(color: theme.colorScheme.error, fontSize: 13)),
          ),

        AppButton(
          label: 'Upload Report',
          icon: Icons.cloud_upload_outlined,
          isLoading: _uploading,
          onPressed: _upload,
        ),
      ],
    );
  }

  Widget _successView(ThemeData theme) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const SizedBox(height: 60),
        Container(
          width: 80, height: 80,
          decoration: const BoxDecoration(
            color: Color(0xFFD1FAE5),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.check_rounded, color: Color(0xFF059669), size: 40),
        ),
        const SizedBox(height: 24),
        Text('Report Uploaded!', style: theme.textTheme.titleLarge),
        const SizedBox(height: 8),
        Text(
          'Your report has been uploaded successfully.\nOur AI is now analysing it — '
          "you'll receive a notification when it's ready.",
          style: theme.textTheme.bodyMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),

        // Animated analysis in-progress indicator
        Container(
          margin: const EdgeInsets.symmetric(vertical: 16),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: theme.colorScheme.primary.withOpacity(0.06),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 16, height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(width: 10),
              Text('AI analysis in progress...',
                  style: TextStyle(
                    fontFamily: 'DMSans',
                    fontSize: 13,
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w500,
                  )),
            ],
          ),
        ),
        const SizedBox(height: 24),
        AppButton(
          label: 'Back to Dashboard',
          variant: AppButtonVariant.outline,
          onPressed: () => Navigator.pop(context),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _descCtrl.dispose();
    super.dispose();
  }
}
