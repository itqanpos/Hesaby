// lib/features/support/presentation/pages/company_support_page.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../shared/layouts/app_shell.dart';
import '../../../../shared/widgets/app_button.dart';
import '../../../../shared/widgets/app_empty.dart';
import '../../../../shared/widgets/app_error.dart';
import '../../../../shared/widgets/app_loader.dart';
import '../../../../shared/widgets/app_text_field.dart';
import '../../../companies/presentation/providers/company_context_provider.dart';
import '../../../companies/presentation/providers/company_context_state.dart';

// ============================================================================
// Models (مبسطة للشركة)
// ============================================================================

class CompanyTicket {
  const CompanyTicket({
    required this.id,
    required this.subject,
    required this.description,
    required this.status,
    required this.createdAt,
  });

  final String id;
  final String subject;
  final String description;
  final String status;
  final DateTime createdAt;

  factory CompanyTicket.fromMap(Map<String, dynamic> map) {
    return CompanyTicket(
      id: map['id'] as String,
      subject: map['subject'] as String,
      description: map['description'] as String,
      status: map['status'] as String? ?? 'new',
      createdAt: DateTime.tryParse(map['created_at']?.toString() ?? '')?.toLocal() ?? DateTime.now(),
    );
  }

  String get statusLabel {
    switch (status) {
      case 'new': return 'جديدة';
      case 'in_progress': return 'قيد المعالجة';
      case 'resolved': return 'تم الحل';
      default: return status;
    }
  }
}

class CompanyTicketReply {
  const CompanyTicketReply({
    required this.id,
    required this.message,
    required this.isAdminReply,
    required this.createdAt,
  });

  final String id;
  final String message;
  final bool isAdminReply;
  final DateTime createdAt;

  factory CompanyTicketReply.fromMap(Map<String, dynamic> map) {
    return CompanyTicketReply(
      id: map['id'] as String,
      message: map['message'] as String,
      isAdminReply: map['is_admin_reply'] as bool? ?? false,
      createdAt: DateTime.tryParse(map['created_at']?.toString() ?? '')?.toLocal() ?? DateTime.now(),
    );
  }
}

// ============================================================================
// Providers
// ============================================================================

final companyTicketsProvider = FutureProvider.autoDispose<List<CompanyTicket>>((ref) async {
  final companyId = ref.watch(companyContextProvider.select((s) => s.currentCompany?.id));
  if (companyId == null) return [];

  final client = Supabase.instance.client;
  final response = await client
      .from('support_tickets')
      .select()
      .eq('company_id', companyId)
      .order('created_at', ascending: false);

  return (response as List).whereType<Map<String, dynamic>>().map((e) => CompanyTicket.fromMap(e)).toList();
});

// ============================================================================
// UI
// ============================================================================

class CompanySupportPage extends ConsumerWidget {
  const CompanySupportPage({super.key});

  Future<void> _showNewTicketDialog(BuildContext context, WidgetRef ref) async {
    final bool? created = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _NewTicketDialog(),
    );
    if (created == true) ref.invalidate(companyTicketsProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncTickets = ref.watch(companyTicketsProvider);

    return AppShell(
      appBar: AppBar(title: const Text('الدعم الفني')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showNewTicketDialog(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('تذكرة جديدة'),
      ),
      body: asyncTickets.when(
        loading: () => const AppLoader(),
        error: (Object e, StackTrace _) => AppErrorView(
          title: 'تعذّر تحميل التذاكر',
          message: 'حدث خطأ: $e',
          retryLabel: 'إعادة المحاولة',
          onRetry: () => ref.invalidate(companyTicketsProvider),
        ),
        data: (List<CompanyTicket> tickets) {
          if (tickets.isEmpty) {
            return const AppEmptyView(
              icon: Icons.support_agent,
              title: 'لا توجد تذاكر',
              message: 'إذا واجهت أي مشكلة، اضغط على زر "تذكرة جديدة" وسنقوم بمساعدتك.',
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: tickets.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              return _CompanyTicketCard(ticket: tickets[index]);
            },
          );
        },
      ),
    );
  }
}

class _CompanyTicketCard extends StatelessWidget {
  const _CompanyTicketCard({required this.ticket});
  final CompanyTicket ticket;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return InkWell(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => _CompanyTicketDetailPage(ticket: ticket)),
      ),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: scheme.outlineVariant),
        ),
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(ticket.subject, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: ticket.status == 'resolved' ? const Color(0xFFC8E6C9) : scheme.errorContainer,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    ticket.statusLabel,
                    style: TextStyle(
                      color: ticket.status == 'resolved' ? const Color(0xFF1B5E20) : scheme.onErrorContainer,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              ticket.description,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: Text(
                DateFormat('yyyy/MM/dd HH:mm').format(ticket.createdAt),
                style: theme.textTheme.labelSmall?.copyWith(color: scheme.outline),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// Ticket Detail Page (للشركة)
// ============================================================================

class _CompanyTicketDetailPage extends ConsumerStatefulWidget {
  final CompanyTicket ticket;
  const _CompanyTicketDetailPage({required this.ticket});

  @override
  ConsumerState<_CompanyTicketDetailPage> createState() => _CompanyTicketDetailPageState();
}

class _CompanyTicketDetailPageState extends ConsumerState<_CompanyTicketDetailPage> {
  final TextEditingController _replyController = TextEditingController();
  bool _isSending = false;
  List<CompanyTicketReply> _replies = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadReplies();
  }

  @override
  void dispose() {
    _replyController.dispose();
    super.dispose();
  }

  Future<void> _loadReplies() async {
    try {
      final client = Supabase.instance.client;
      final response = await client
          .from('ticket_replies')
          .select()
          .eq('ticket_id', widget.ticket.id)
          .order('created_at', ascending: true);
      if (mounted) {
        setState(() {
          _replies = (response as List)
              .whereType<Map<String, dynamic>>()
              .map((e) => CompanyTicketReply.fromMap(e))
              .toList();
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _sendReply() async {
    final msg = _replyController.text.trim();
    if (msg.isEmpty) return;

    setState(() => _isSending = true);
    try {
      final client = Supabase.instance.client;
      await client.from('ticket_replies').insert({
        'ticket_id': widget.ticket.id,
        'sender_id': client.auth.currentUser?.id,
        'message': msg,
        'is_admin_reply': false,
      });
      _replyController.clear();
      await _loadReplies();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطأ: $e')));
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(title: Text(widget.ticket.subject)),
      body: Column(
        children: <Widget>[
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: <Widget>[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: scheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(12)),
                  child: Text(widget.ticket.description, style: theme.textTheme.bodyMedium),
                ),
                const SizedBox(height: 24),
                if (_isLoading)
                  const Center(child: CircularProgressIndicator())
                else
                  ..._replies.map((r) => _CompanyReplyBubble(reply: r)),
              ],
            ),
          ),
          if (widget.ticket.status != 'resolved')
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: scheme.surface,
                border: Border(top: BorderSide(color: scheme.outlineVariant)),
              ),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: AppTextField(
                      controller: _replyController,
                      hint: 'اكتب ردك هنا...',
                      enabled: !_isSending,
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: _isSending ? null : _sendReply,
                    icon: _isSending
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.send),
                  )
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _CompanyReplyBubble extends StatelessWidget {
  const _CompanyReplyBubble({required this.reply});
  final CompanyTicketReply reply;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bool isAdmin = reply.isAdminReply;

    return Align(
      alignment: isAdmin ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
        decoration: BoxDecoration(
          color: isAdmin ? scheme.primaryContainer : scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(12),
            topRight: const Radius.circular(12),
            bottomLeft: isAdmin ? const Radius.circular(12) : Radius.zero,
            bottomRight: isAdmin ? Radius.zero : const Radius.circular(12),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            if (isAdmin) ...[
              Text('الدعم الفني', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: scheme.onPrimaryContainer)),
              const SizedBox(height: 4),
            ],
            Text(reply.message, style: TextStyle(color: isAdmin ? scheme.onPrimaryContainer : scheme.onSurface)),
            const SizedBox(height: 4),
            Text(
              DateFormat('HH:mm').format(reply.createdAt),
              style: TextStyle(fontSize: 10, color: (isAdmin ? scheme.onPrimaryContainer : scheme.onSurface).withValues(alpha: 0.6)),
            )
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// New Ticket Dialog
// ============================================================================

class _NewTicketDialog extends ConsumerStatefulWidget {
  const _NewTicketDialog();
  @override
  ConsumerState<_NewTicketDialog> createState() => _NewTicketDialogState();
}

class _NewTicketDialogState extends ConsumerState<_NewTicketDialog> {
  final _subjectCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  bool _isLoading = false;
  String? _error;

  @override
  void dispose() {
    _subjectCtrl.dispose(); _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final subject = _subjectCtrl.text.trim();
    final desc = _descCtrl.text.trim();
    final companyId = ref.read(companyContextProvider).currentCompany?.id;

    if (subject.isEmpty || desc.isEmpty || companyId == null) {
      setState(() => _error = 'الرجاء ملء جميع الحقول');
      return;
    }

    setState(() { _isLoading = true; _error = null; });

    try {
      final client = Supabase.instance.client;
      await client.from('support_tickets').insert({
        'company_id': companyId,
        'user_id': client.auth.currentUser?.id,
        'subject': subject,
        'description': desc,
        'status': 'new',
        'priority': 'medium',
      });
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() { _isLoading = false; _error = 'خطأ: $e'; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('تذكرة دعم جديدة'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppTextField(controller: _subjectCtrl, label: 'موضوع المشكلة'),
            const SizedBox(height: 12),
            AppTextField(controller: _descCtrl, label: 'وصف المشكلة', maxLines: 4),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ]
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: _isLoading ? null : () => Navigator.pop(context), child: const Text('إلغاء')),
        AppButton(label: 'إرسال', isLoading: _isLoading, onPressed: _isLoading ? null : _submit),
      ],
    );
  }
}
