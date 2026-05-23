import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/theme.dart';
import '../../../data/remote/api_logger.dart';

// ─── Entry point ──────────────────────────────────────────────────────────────

class ApiLogSheet extends StatefulWidget {
  final ApiCallLogger logger;

  const ApiLogSheet({super.key, required this.logger});

  static Future<void> show(BuildContext context, ApiCallLogger logger) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ApiLogSheet(logger: logger),
    );
  }

  @override
  State<ApiLogSheet> createState() => _ApiLogSheetState();
}

class _ApiLogSheetState extends State<ApiLogSheet> {
  // Which record indices are expanded
  final Set<int> _expanded = {};

  @override
  Widget build(BuildContext context) {
    final records = widget.logger.records.reversed.toList();

    return Container(
      height: MediaQuery.of(context).size.height * 0.93,
      decoration: const BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          _DragHandle(),
          _SheetHeader(
            count: records.length,
            onClear: () {
              widget.logger.clear();
              setState(() => _expanded.clear());
            },
          ),
          const Divider(color: AppColors.divider, height: 1),
          Expanded(
            child: records.isEmpty
                ? _EmptyState()
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                    itemCount: records.length,
                    itemBuilder: (ctx, i) {
                      final record = records[i];
                      final isExpanded = _expanded.contains(i);
                      return _ApiCallCard(
                        record: record,
                        isExpanded: isExpanded,
                        onToggle: () => setState(() {
                          if (isExpanded) {
                            _expanded.remove(i);
                          } else {
                            _expanded.add(i);
                          }
                        }),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

// ─── Sub-widgets ──────────────────────────────────────────────────────────────

class _DragHandle extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 4),
      child: Container(
        width: 40,
        height: 4,
        decoration: BoxDecoration(
          color: AppColors.divider,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }
}

class _SheetHeader extends StatelessWidget {
  final int count;
  final VoidCallback onClear;

  const _SheetHeader({required this.count, required this.onClear});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 12, 12),
      child: Row(
        children: [
          const Icon(Icons.terminal_rounded,
              color: AppColors.accent, size: 20),
          const SizedBox(width: 10),
          const Text(
            'API Logs',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 17,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: 8),
          if (count > 0)
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.accent.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$count',
                style: const TextStyle(
                  color: AppColors.accent,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          const Spacer(),
          if (count > 0)
            TextButton.icon(
              onPressed: onClear,
              style: TextButton.styleFrom(
                foregroundColor: AppColors.textSecondary,
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              ),
              icon: const Icon(Icons.delete_sweep_outlined, size: 16),
              label: const Text('Clear', style: TextStyle(fontSize: 13)),
            ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.cloud_off_outlined,
              color: AppColors.textSecondary.withValues(alpha: 0.4), size: 48),
          const SizedBox(height: 16),
          const Text(
            'No API calls recorded yet.',
            style:
                TextStyle(color: AppColors.textSecondary, fontSize: 14),
          ),
          const SizedBox(height: 6),
          const Text(
            'Pull to refresh the dashboard to see calls here.',
            style:
                TextStyle(color: AppColors.textSecondary, fontSize: 12),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

// ─── Individual call card ─────────────────────────────────────────────────────

class _ApiCallCard extends StatelessWidget {
  final ApiCallRecord record;
  final bool isExpanded;
  final VoidCallback onToggle;

  const _ApiCallCard({
    required this.record,
    required this.isExpanded,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: record.isError
              ? AppColors.red.withValues(alpha: 0.3)
              : AppColors.divider,
        ),
      ),
      child: Column(
        children: [
          _CardHeader(
            record: record,
            isExpanded: isExpanded,
            onToggle: onToggle,
          ),
          if (isExpanded) ...[
            const Divider(color: AppColors.divider, height: 1),
            _CardBody(record: record),
          ],
        ],
      ),
    );
  }
}

class _CardHeader extends StatelessWidget {
  final ApiCallRecord record;
  final bool isExpanded;
  final VoidCallback onToggle;

  const _CardHeader({
    required this.record,
    required this.isExpanded,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final statusColor =
        record.isError ? AppColors.red : AppColors.green;

    final time = record.timestamp;
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final timeStr =
        '${time.day} ${months[time.month - 1]} ${time.year}  '
        '${time.hour.toString().padLeft(2, '0')}:'
        '${time.minute.toString().padLeft(2, '0')}:'
        '${time.second.toString().padLeft(2, '0')}.'
        '${time.millisecond.toString().padLeft(3, '0')}';

    return InkWell(
      onTap: onToggle,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            // Status dot
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: statusColor,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: statusColor.withValues(alpha: 0.5),
                    blurRadius: 6,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            // Call name
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    record.name,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    timeStr,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            // Status code badge
            if (record.statusCode != null) ...[
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '${record.statusCode}',
                  style: TextStyle(
                    color: statusColor,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
              const SizedBox(width: 8),
            ],
            // Chevron
            AnimatedRotation(
              turns: isExpanded ? 0.5 : 0,
              duration: const Duration(milliseconds: 200),
              child: const Icon(Icons.keyboard_arrow_down_rounded,
                  color: AppColors.textSecondary, size: 20),
            ),
          ],
        ),
      ),
    );
  }
}

class _CardBody extends StatelessWidget {
  final ApiCallRecord record;

  const _CardBody({required this.record});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // URL
          _UrlRow(url: record.url),
          const SizedBox(height: 14),

          // Request body
          if (record.requestBody != null &&
              record.requestBody!.isNotEmpty) ...[
            _JsonSection(
              label: 'REQUEST',
              json: record.prettyRequest,
            ),
            const SizedBox(height: 12),
          ],

          // Response body
          _JsonSection(
            label: 'RESPONSE',
            json: record.prettyResponse,
            isError: record.isError && record.responseBody == null,
          ),
        ],
      ),
    );
  }
}

class _UrlRow extends StatelessWidget {
  final String url;

  const _UrlRow({required this.url});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: AppColors.accent.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(4),
          ),
          child: const Text(
            'POST',
            style: TextStyle(
              color: AppColors.accent,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              fontFamily: 'monospace',
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            url,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 11,
              fontFamily: 'monospace',
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        GestureDetector(
          onTap: () {
            Clipboard.setData(ClipboardData(text: url));
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('URL copied'),
                duration: Duration(seconds: 1),
                behavior: SnackBarBehavior.floating,
              ),
            );
          },
          child: const Padding(
            padding: EdgeInsets.only(left: 6),
            child: Icon(Icons.copy_rounded,
                color: AppColors.textSecondary, size: 14),
          ),
        ),
      ],
    );
  }
}

class _JsonSection extends StatelessWidget {
  final String label;
  final String json;
  final bool isError;

  const _JsonSection({
    required this.label,
    required this.json,
    this.isError = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section label + copy
        Row(
          children: [
            Text(
              label,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
              ),
            ),
            const Spacer(),
            GestureDetector(
              onTap: () {
                Clipboard.setData(ClipboardData(text: json));
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('$label copied to clipboard'),
                    duration: const Duration(seconds: 1),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              },
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  Icon(Icons.copy_rounded,
                      color: AppColors.textSecondary, size: 12),
                  SizedBox(width: 4),
                  Text(
                    'Copy',
                    style: TextStyle(
                        color: AppColors.textSecondary, fontSize: 11),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        // JSON block
        Container(
          width: double.infinity,
          constraints: const BoxConstraints(maxHeight: 320),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF0D1220),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isError
                  ? AppColors.red.withValues(alpha: 0.2)
                  : AppColors.divider.withValues(alpha: 0.6),
            ),
          ),
          child: SingleChildScrollView(
            child: SelectableText.rich(
              TextSpan(
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                  height: 1.55,
                  color: AppColors.textSecondary,
                ),
                children: _highlightJson(json),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ─── JSON syntax highlighter ──────────────────────────────────────────────────

const _keyColor = Color(0xFF7DD3FC);       // sky blue  — keys
const _stringColor = Color(0xFF86EFAC);    // green     — string values
const _numberColor = Color(0xFFFBBF24);    // amber     — numbers
const _boolColor = Color(0xFFC084FC);      // purple    — true / false / null
const _bracketColor = Color(0xFFFBD38D);   // soft gold — {} []
const _punctColor = Color(0xFF4B5563);     // dim gray  — : ,

List<TextSpan> _highlightJson(String json) {
  final spans = <TextSpan>[];
  int i = 0;

  while (i < json.length) {
    final ch = json[i];

    // ── Whitespace ────────────────────────────────
    if (ch == ' ' || ch == '\t' || ch == '\n' || ch == '\r') {
      spans.add(TextSpan(text: ch));
      i++;
      continue;
    }

    // ── String ────────────────────────────────────
    if (ch == '"') {
      final start = i;
      i++; // opening quote
      while (i < json.length) {
        if (json[i] == '\\' && i + 1 < json.length) {
          i += 2; // skip escape sequence
        } else if (json[i] == '"') {
          i++; // closing quote
          break;
        } else {
          i++;
        }
      }
      final token = json.substring(start, i);
      // Look ahead: key if next non-space is ':'
      int j = i;
      while (j < json.length && (json[j] == ' ' || json[j] == '\t')) {
        j++;
      }
      final isKey = j < json.length && json[j] == ':';
      spans.add(TextSpan(
        text: token,
        style: TextStyle(color: isKey ? _keyColor : _stringColor),
      ));
      continue;
    }

    // ── Number ────────────────────────────────────
    if (ch == '-' ||
        (ch.codeUnitAt(0) >= 0x30 && ch.codeUnitAt(0) <= 0x39)) {
      final start = i;
      while (i < json.length &&
          '0123456789.-+eE'.contains(json[i])) {
        i++;
      }
      spans.add(TextSpan(
        text: json.substring(start, i),
        style: const TextStyle(color: _numberColor),
      ));
      continue;
    }

    // ── true ──────────────────────────────────────
    if (i + 4 <= json.length && json.substring(i, i + 4) == 'true') {
      spans.add(const TextSpan(
          text: 'true', style: TextStyle(color: _boolColor)));
      i += 4;
      continue;
    }

    // ── false ─────────────────────────────────────
    if (i + 5 <= json.length && json.substring(i, i + 5) == 'false') {
      spans.add(const TextSpan(
          text: 'false', style: TextStyle(color: _boolColor)));
      i += 5;
      continue;
    }

    // ── null ──────────────────────────────────────
    if (i + 4 <= json.length && json.substring(i, i + 4) == 'null') {
      spans.add(const TextSpan(
          text: 'null', style: TextStyle(color: _boolColor)));
      i += 4;
      continue;
    }

    // ── Brackets ──────────────────────────────────
    if (ch == '{' || ch == '}' || ch == '[' || ch == ']') {
      spans.add(TextSpan(
          text: ch, style: const TextStyle(color: _bracketColor)));
      i++;
      continue;
    }

    // ── Punctuation ───────────────────────────────
    if (ch == ':' || ch == ',') {
      spans.add(TextSpan(
          text: ch, style: const TextStyle(color: _punctColor)));
      i++;
      continue;
    }

    // ── Fallback ──────────────────────────────────
    spans.add(TextSpan(text: ch));
    i++;
  }

  return spans;
}
