import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:car_workshop/core/constants/app_constants.dart';
import 'package:car_workshop/data/local/database.dart';
import 'package:car_workshop/presentation/providers/providers.dart';
import 'package:car_workshop/presentation/theme/app_theme.dart';

final _currencyFmt = NumberFormat.currency(symbol: '\$', decimalDigits: 2);

class BillingScreen extends ConsumerStatefulWidget {
  const BillingScreen({super.key, required this.jobCardId});
  final String jobCardId;

  @override
  ConsumerState<BillingScreen> createState() => _BillingScreenState();
}

class _BillingScreenState extends ConsumerState<BillingScreen> {
  double _discountPct = 0;
  double _taxPct      = 0;
  bool _generating    = false;

  final List<_ExtraLine> _extras = [];

  @override
  Widget build(BuildContext context) {
    final tasksAsync = ref.watch(tasksForJobCardProvider(widget.jobCardId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Billing'),
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.receipt_outlined, color: Colors.white),
            label: const Text('Generate', style: TextStyle(color: Colors.white)),
            onPressed: _generating ? null : _generate,
          ),
        ],
      ),

      body: tasksAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error:   (e, _) => Center(child: Text('Error: $e')),
        data:    (tasks) {
          final completed = tasks.where((t) => t.status == 'completed').toList();
          return _BillingBody(
            completedTasks: completed,
            extras:         _extras,
            discountPct:    _discountPct,
            taxPct:         _taxPct,
            onDiscountChanged: (v) => setState(() => _discountPct = v),
            onTaxChanged:      (v) => setState(() => _taxPct      = v),
            onAddExtra:        ()  => _addExtraLine(),
            onRemoveExtra:     (i) => setState(() => _extras.removeAt(i)),
          );
        },
      ),
    );
  }

  void _addExtraLine() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _AddExtraLineSheet(
        onAdd: (line) => setState(() => _extras.add(line)),
      ),
    );
  }

  Future<void> _generate() async {
    setState(() => _generating = true);
    try {
      final api  = ref.read(apiClientProvider);
      final user = ref.read(currentUserProvider)!;

      await api.generateInvoice({
        'jobCardId':            widget.jobCardId,
        'customerId':           '', // should be fetched from job card
        'autoPopulateFromTasks': true,
        'additionalItems':      _extras.map((e) => e.toJson()).toList(),
        'discountPct':          _discountPct,
        'taxPct':               _taxPct,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Invoice generated successfully'),
              backgroundColor: AppColors.secondary),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'),
              backgroundColor: AppColors.warning),
        );
      }
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }
}

// ─────────────────────────────────────────────
// Billing body layout
// ─────────────────────────────────────────────

class _BillingBody extends StatelessWidget {
  const _BillingBody({
    required this.completedTasks,
    required this.extras,
    required this.discountPct,
    required this.taxPct,
    required this.onDiscountChanged,
    required this.onTaxChanged,
    required this.onAddExtra,
    required this.onRemoveExtra,
  });

  final List<TasksTableData> completedTasks;
  final List<_ExtraLine> extras;
  final double discountPct, taxPct;
  final ValueChanged<double> onDiscountChanged, onTaxChanged;
  final VoidCallback onAddExtra;
  final ValueChanged<int> onRemoveExtra;

  double get _laborSubtotal => completedTasks.fold(0.0, (sum, t) {
    final hours = t.actualHours ?? t.estimatedHours ?? 0;
    final rate  = t.laborRate ?? 0;
    return sum + hours * rate;
  });

  double get _extrasSubtotal =>
      extras.fold(0.0, (sum, e) => sum + e.quantity * e.unitPrice);

  double get _subtotal => _laborSubtotal + _extrasSubtotal;
  double get _discountAmount => _subtotal * discountPct / 100;
  double get _taxAmount => (_subtotal - _discountAmount) * taxPct / 100;
  double get _total => _subtotal - _discountAmount + _taxAmount;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [

        // ── Labor lines ─────────────────────────────────────────
        const _SectionTitle(title: 'Labor (Completed Tasks)'),
        const SizedBox(height: 8),

        if (completedTasks.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text('No completed tasks yet.',
                style: TextStyle(color: AppColors.textSecondary)),
          )
        else
          ...completedTasks.map((t) {
            final hours = t.actualHours ?? t.estimatedHours ?? 0;
            final rate  = t.laborRate ?? 0;
            return _LineItemRow(
              description: t.title,
              quantity:    hours,
              unit:        'h',
              unitPrice:   rate,
            );
          }),

        const SizedBox(height: 16),

        // ── Extras / spare parts ──────────────────────────────
        Row(
          children: [
            const _SectionTitle(title: 'Parts & Extras'),
            const Spacer(),
            TextButton.icon(
              onPressed: onAddExtra,
              icon:  const Icon(Icons.add, size: 16),
              label: const Text('Add Line'),
            ),
          ],
        ),
        const SizedBox(height: 8),

        if (extras.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text('No extra items.',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
          )
        else
          ...extras.asMap().entries.map((entry) => _LineItemRow(
            description: entry.value.description,
            quantity:    entry.value.quantity,
            unit:        entry.value.unit,
            unitPrice:   entry.value.unitPrice,
            onDelete:    () => onRemoveExtra(entry.key),
          )),

        const Divider(height: 32),

        // ── Discount & tax sliders ────────────────────────────
        const _SectionTitle(title: 'Discount & Tax'),
        const SizedBox(height: 12),

        _SliderRow(
          label:     'Discount',
          value:     discountPct,
          color:     AppColors.statusInProgress,
          onChanged: onDiscountChanged,
        ),
        const SizedBox(height: 8),
        _SliderRow(
          label:     'Tax',
          value:     taxPct,
          color:     AppColors.primary,
          onChanged: onTaxChanged,
        ),

        const Divider(height: 32),

        // ── Totals ────────────────────────────────────────────
        _TotalRow(label: 'Subtotal',  value: _subtotal),
        if (discountPct > 0)
          _TotalRow(label: 'Discount (${discountPct.toStringAsFixed(0)}%)',
              value: -_discountAmount, color: AppColors.secondary),
        if (taxPct > 0)
          _TotalRow(label: 'Tax (${taxPct.toStringAsFixed(0)}%)',
              value: _taxAmount, color: AppColors.textSecondary),
        const Divider(height: 16),
        _TotalRow(
          label: 'TOTAL',
          value: _total,
          isTotal: true,
          color: AppColors.primary,
        ),

        const SizedBox(height: 24),
      ],
    );
  }
}

// ─────────────────────────────────────────────
// Sub-widgets
// ─────────────────────────────────────────────

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(title,
        style: const TextStyle(
            fontSize: 13, fontWeight: FontWeight.w700,
            color: AppColors.textSecondary, letterSpacing: 0.3));
  }
}

class _LineItemRow extends StatelessWidget {
  const _LineItemRow({
    required this.description,
    required this.quantity,
    required this.unit,
    required this.unitPrice,
    this.onDelete,
  });

  final String description, unit;
  final double quantity, unitPrice;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          if (onDelete != null)
            GestureDetector(
              onTap: onDelete,
              child: const Icon(Icons.remove_circle_outline,
                  size: 18, color: AppColors.warning),
            ),
          if (onDelete != null) const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(description,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                Text('$quantity $unit × ${_currencyFmt.format(unitPrice)}',
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.textSecondary)),
              ],
            ),
          ),
          Text(_currencyFmt.format(quantity * unitPrice),
              style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _SliderRow extends StatelessWidget {
  const _SliderRow({
    required this.label, required this.value,
    required this.color, required this.onChanged,
  });
  final String label;
  final double value;
  final Color color;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 70,
          child: Text('$label\n${value.toStringAsFixed(0)}%',
              style: const TextStyle(fontSize: 12)),
        ),
        Expanded(
          child: Slider(
            value: value,
            min:   0,
            max:   30,
            divisions: 30,
            activeColor: color,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}

class _TotalRow extends StatelessWidget {
  const _TotalRow({
    required this.label, required this.value,
    this.isTotal = false, this.color,
  });
  final String label;
  final double value;
  final bool isTotal;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Text(label,
              style: TextStyle(
                  fontWeight: isTotal ? FontWeight.bold : FontWeight.normal,
                  fontSize: isTotal ? 16 : 14,
                  color: color ?? AppColors.textPrimary)),
          const Spacer(),
          Text(
            value < 0
                ? '-${_currencyFmt.format(value.abs())}'
                : _currencyFmt.format(value),
            style: TextStyle(
                fontWeight: isTotal ? FontWeight.bold : FontWeight.w600,
                fontSize: isTotal ? 18 : 14,
                color: color ?? AppColors.textPrimary),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Add extra line sheet
// ─────────────────────────────────────────────

class _ExtraLine {
  const _ExtraLine({
    required this.description, required this.quantity,
    required this.unitPrice, required this.itemType, this.unit = 'pcs',
  });
  final String description, itemType, unit;
  final double quantity, unitPrice;

  Map<String, dynamic> toJson() => {
    'itemType':    itemType,
    'description': description,
    'quantity':    quantity,
    'unitPrice':   unitPrice,
  };
}

class _AddExtraLineSheet extends StatefulWidget {
  const _AddExtraLineSheet({required this.onAdd});
  final ValueChanged<_ExtraLine> onAdd;

  @override
  State<_AddExtraLineSheet> createState() => _AddExtraLineSheetState();
}

class _AddExtraLineSheetState extends State<_AddExtraLineSheet> {
  final _descCtrl  = TextEditingController();
  final _qtyCtrl   = TextEditingController(text: '1');
  final _priceCtrl = TextEditingController();
  String _itemType = 'part';

  @override
  void dispose() {
    _descCtrl.dispose();
    _qtyCtrl.dispose();
    _priceCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Add Line Item',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),

            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'part', label: Text('Spare Part')),
                ButtonSegment(value: 'misc', label: Text('Misc')),
              ],
              selected: {_itemType},
              onSelectionChanged: (s) => setState(() => _itemType = s.first),
            ),
            const SizedBox(height: 14),

            TextField(
              controller: _descCtrl,
              decoration: const InputDecoration(labelText: 'Description *'),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _qtyCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Qty'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _priceCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Unit Price'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () {
                if (_descCtrl.text.trim().isEmpty) return;
                widget.onAdd(_ExtraLine(
                  description: _descCtrl.text.trim(),
                  quantity:    double.tryParse(_qtyCtrl.text) ?? 1,
                  unitPrice:   double.tryParse(_priceCtrl.text) ?? 0,
                  itemType:    _itemType,
                ));
                Navigator.pop(context);
              },
              child: const Text('Add to Invoice'),
            ),
          ],
        ),
      ),
    );
  }
}
