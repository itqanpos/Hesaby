// lib/features/admin/presentation/pages/tabs/admin_support_tab.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../../shared/widgets/app_empty.dart';
import '../../../../../shared/widgets/app_error.dart';
import '../../../../../shared/widgets/app_loader.dart';
import '../../../../../shared/widgets/app_text_field.dart';

// ============================================================================
// Models
// ============================================================================

class SupportTicket {
  const SupportTicket({
    required this.id,
    required this.subject,
    required this.description,
    required this.status,
    required this.priority,
    required this.createdAt,
    this.companyName,
  });

  final String id;
  final String subject;
  final String description;
  final String status;
  final String priority;
  final DateTime createdAt;
  final String? companyName;

  factory SupportTicket.fromMap(Map<String, dynamic> map) {
    String? compName;
    if (map['companies'] != null && map['companies'] is Map) {
      compName = (map['companies'] as Map)['name'] as String?;
    }

    return SupportTicket(
      id: map['id'] as String,
      subject: map['subject'] as String? ?? 'بدون عنوان',
      description: map['description'] as String? ?? '',
      status: map['status'] as String? ?? 'new',
      priority: map['priority'] as String? ?? 'medium',
      createdAt: _parseDate(map['created_at']),
      companyName: compName,
    );
  }

  static DateTime _parseDate(Object? value) {
    if (value is DateTime) return value.toLocal();
    if (value is String) {
      DateTime? parsed = DateTime.tryParse(value);
      if (parsed != null) return parsed.toLocal();
      try {
        String normalized = value.trim();
        if (normalized.contains(' ')) normalized = normalized.replaceFirst(' ', 'T');
        if (normalized.endsWith('+00')) normalized = normalized.replaceAll('+00', 'Z');
        parsed = DateTime.tryParse(normalized);
        if (parsed != null) return parsed.toLocal();
      } catch (_) {}
    }
    return DateTime.now();
  }

  String get statusLabel {
    switch (status) {
      case 'new': return 'جديدة';
      case 'in_progress': return 'قيد المعالجة';
      case 'resolved': return 'تم الحل';
      default: return status;
    }
  }

  String get priorityLabel {
    switch (priority) {
      case 'high': return 'عالية';
      case 'medium': return 'متوسطة';
      case 'low': return 'منخفضة';
      default: return priority;
    }
  }
}

class TicketReply {
  const TicketReply({
    required this.id,
    required this.message,
    required this.isAdminReply,
    required this.createdAt,
  });

  final String id;
  final String message;
  final bool isAdminReply;
  final DateTime createdAt;

  factory TicketReply.fromMap(Map<String, dynamic> map) {
    return TicketReply(
      id: map['id'] as String,
      message: map['message'] as String? ?? '',
      isAdminReply: map['is_admin_reply'] as bool? ?? false,
      createdAt: SupportTicket._parseDate(map['created_at']),
    );
  }
}

// ============================================================================
// Providers
// ============================================================================

final ticketsProvider = FutureProvider.autoDispose<List<SupportTicket>>((ref) async {
  final client = Supabase.instance.client;
  final response = await client
      .from('support_tickets')
      .select('*, companies(name)')
      .order('created_at', ascending: false);

  final List<dynamic> data = response as List<dynamic>;
  // ⬇️ إصلاح: استخدام whereType كما يطلب الـ Linter
  return data
      .whereType<Map<String, dynamic>>()
      .map((e) => SupportTicket.fromMap(e))
      .toList();
});

// ============================================================================
// UI
// ============================================================================

class AdminSupportTab extends ConsumerWidget {
  const AdminSupportTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncTickets = ref.watch(ticketsProvider);

    return asyncTickets.when(
      loading: () => const AppLoader(),
      error: (Object error, StackTrace _) => AppErrorView(
        title: 'تعذّر تحميل التذاكر',
        message: 'حدث خطأ: $error',
        retryLabel: 'إعادة المحاولة',
        onRetry: () => ref.invalidate(ticketsProvider),
      ),
      data: (List<SupportTicket> tickets) {
        if (tickets.isEmpty) {
          return const AppEmptyView(
            icon: Icons.support_agent,
            title: 'لا توجد تذاكر دعم',
            message: 'لم يتم استلام أي طلبات دعم حتى الآن.',
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: tickets.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            final ticket = tickets[index];
            return _TicketCard(ticket: ticket);
          },
        );
      },
    );
  }
}

class _TicketCard extends StatelessWidget {
  const _TicketCard({required this.ticket});
  final SupportTicket ticket;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final (Color statusColor, Color statusFg) = _getStatusColor(ticket.status, scheme);

    return InkWell(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => _TicketDetailPage(ticketId: ticket.id, initialTicket: ticket),
        ),
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
                  child: Text(
                    ticket.subject,
                    style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(color: statusColor, borderRadius: BorderRadius.circular(6)),
                  child: Text(
                    ticket.statusLabel,
                    style: TextStyle(color: statusFg, fontSize: 10, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              ticket.description,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 8),
            Row(
              children: <Widget>[
                Icon(Icons.business, size: 14, color: scheme.outline),
                const SizedBox(width: 4),
                Text(ticket.companyName ?? 'شركة غير معروفة', style: theme.textTheme.labelSmall),
                const Spacer(),
                Text(
                  DateFormat('yyyy/MM/dd HH:mm').format(ticket.createdAt),
                  style: theme.textTheme.labelSmall?.copyWith(color: scheme.outline),
                ),
              ],
            )
          ],
        ),
      ),
    );
  }

  static (Color, Color) _getStatusColor(String status, ColorScheme scheme) {
    switch (status) {
      case 'new': return (scheme.errorContainer, scheme.onErrorContainer);
      case 'in_progress': return (const Color(0xFFFFECB3), const Color(0xFF8D6E00));
      case 'resolved': return (const Color(0xFFC8E6C9), const Color(0xFF1B5E20));
      default: return (scheme.surfaceContainerHighest, scheme.onSurfaceVariant);
    }
  }
}

// ============================================================================
// Ticket Detail Page
// ============================================================================

class _TicketDetailPage extends ConsumerStatefulWidget {
  final String ticketId;
  final SupportTicket initialTicket;
  const _TicketDetailPage({required this.ticketId, required this.initialTicket});

  @override
  ConsumerState<_TicketDetailPage> createState() => _TicketDetailPageState();
}

class _TicketDetailPageState extends ConsumerState<_TicketDetailPage> {
  final TextEditingController _replyController = TextEditingController();
  bool _isSending = false;
  String _currentStatus = 'new';
  List<TicketReply> _replies = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _currentStatus = widget.initialTicket.status;
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
          .eq('ticket_id', widget.ticketId)
          .order('created_at', ascending: true);
      if (mounted) {
        setState(() {
          final List<dynamic> data = response as List<dynamic>;
          // ⬇️ إصلاح: استخدام whereType كما يطلب الـ Linter
          _replies = data
              .whereType<Map<String, dynamic>>()
              .map((e) => TicketReply.fromMap(e))
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
        'ticket_id': widget.ticketId,
        'sender_id': client.auth.currentUser?.id,
        'message': msg,
        'is_admin_reply': true,
      });
      _replyController.clear();
      await _loadReplies();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطأ: $e')));
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  Future<void> _updateStatus(String newStatus) async {
    try {
      await Supabase.instance.client.from('support_tickets').update({'status': newStatus}).eq('id', widget.ticketId);
      if (!mounted) return;
      setState(() => _currentStatus = newStatus);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم تحديث الحالة')));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطأ: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final ticket = widget.initialTicket;

    return Scaffold(
      appBar: AppBar(
        title: Text(ticket.subject),
        actions: <Widget>[
          PopupMenuButton<String>(
            onSelected: _updateStatus,
            itemBuilder: (context) => const <PopupMenuEntry<String>>[
              PopupMenuItem<String>(value: 'new', child: Text('جديدة')),
              PopupMenuItem<String>(value: 'in_progress', child: Text('قيد المعالجة')),
              PopupMenuItem<String>(value: 'resolved', child: Text('تم الحل')),
            ],
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(color: scheme.primaryContainer, borderRadius: BorderRadius.circular(8)),
              alignment: Alignment.center,
              child: Text(
                _currentStatus == 'new' ? 'جديدة' : _currentStatus == 'in_progress' ? 'قيد المعالجة' : 'تم الحل',
                style: TextStyle(color: scheme.onPrimaryContainer, fontWeight: FontWeight.bold),
              ),
            ),
          )
        ],
      ),
      body: Column(
        children: <Widget>[
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: <Widget>[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: scheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(12)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(ticket.description, style: theme.textTheme.bodyMedium),
                      const SizedBox(height: 8),
                      Text('بواسطة: ${ticket.companyName ?? "شركة"}', style: theme.textTheme.labelSmall),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                if (_isLoading)
                  const Center(child: CircularProgressIndicator())
                else
                  ..._replies.map((r) => _ReplyBubble(reply: r)),
              ],
            ),
          ),
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
          )
        ],
      ),
    );
  }
}

class _ReplyBubble extends StatelessWidget {
  const _ReplyBubble({required this.reply});
  final TicketReply reply;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bool isAdmin = reply.isAdminReply;

    return Align(
      alignment: isAdmin ? Alignment.centerLeft : Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
        decoration: BoxDecoration(
          color: isAdmin ? scheme.primaryContainer : scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(12),
            topRight: const Radius.circular(12),
            bottomLeft: isAdmin ? Radius.zero : const Radius.circular(12),
            bottomRight: isAdmin ? const Radius.circular(12) : Radius.zero,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              reply.message,
              style: TextStyle(color: isAdmin ? scheme.onPrimaryContainer : scheme.onSurface),
            ),
            const SizedBox(height: 4),
            Text(
              DateFormat('HH:mm').format(reply.createdAt),
              style: TextStyle(
                fontSize: 10,
                color: (isAdmin ? scheme.onPrimaryContainer : scheme.onSurface).withValues(alpha: 0.6),
              ),
            )
          ],
        ),
      ),
    );
  }
}
