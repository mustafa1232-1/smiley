import 'package:flutter/material.dart';

import '../../core/secure_stores.dart';
import 'gate_validator.dart';

class DateGateScreen extends StatefulWidget {
  const DateGateScreen({
    required this.store,
    required this.validator,
    required this.onUnlocked,
    super.key,
  });

  final GateStore store;
  final GateValidator validator;
  final VoidCallback onUnlocked;

  @override
  State<DateGateScreen> createState() => _DateGateScreenState();
}

class _DateGateScreenState extends State<DateGateScreen> {
  DateTime _displayedDate = DateTime(2026, 8);
  bool _saving = false;

  Future<void> _select(DateTime date) async {
    setState(() => _displayedDate = date);
    if (!widget.validator.accepts(date) || _saving) return;

    setState(() => _saving = true);
    await widget.store.markUnlocked();
    if (!mounted) return;
    widget.onUnlocked();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: constraints.maxHeight - 48,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Icon(
                      Icons.favorite_rounded,
                      color: scheme.primary,
                      size: 40,
                    ),
                    const SizedBox(height: 18),
                    Text(
                      'Smiley',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.displaySmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'اختر تاريخ البداية',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 28),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: scheme.surface,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: scheme.outlineVariant),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: CalendarDatePicker(
                          initialDate: _displayedDate,
                          firstDate: DateTime(2000),
                          lastDate: DateTime(2100),
                          onDateChanged: _select,
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    AnimatedOpacity(
                      opacity: _saving ? 1 : 0,
                      duration: const Duration(milliseconds: 180),
                      child: const Center(child: CircularProgressIndicator()),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
