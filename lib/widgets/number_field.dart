import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Number entry for one category cell (or the breakfast field).
/// Mirrors the original's dual mode: a tap-to-pick quick list
/// (`.custom-opts`, default ON) or a plain numeric field when the
/// "નંબર પસંદગી (ડ્રોપડાઉન)" switch is OFF.
///
/// Uses a local, self-contained value so callers should give it a
/// fresh `key` (e.g. keyed by class+date+category) whenever the
/// underlying row changes, rather than trying to mutate it externally.
class QuickNumberField extends StatefulWidget {
  final String label;
  final int initialValue;
  final int max;
  final bool quickPickMode;
  final bool enabled;
  final ValueChanged<int> onChanged;

  const QuickNumberField({
    super.key,
    this.label = '',
    required this.initialValue,
    required this.max,
    required this.quickPickMode,
    this.enabled = true,
    required this.onChanged,
  });

  @override
  State<QuickNumberField> createState() => _QuickNumberFieldState();
}

class _QuickNumberFieldState extends State<QuickNumberField> {
  late int _value;
  late TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _value = widget.initialValue;
    _controller = TextEditingController(text: _value == 0 ? '' : '$_value');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _isOver => _value > widget.max;

  void _setValue(int v) {
    setState(() {
      _value = v;
      _controller.text = v == 0 ? '' : '$v';
    });
    widget.onChanged(v);
  }

  Future<void> _openPicker() async {
    final picked = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 14),
                  decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(4)),
                ),
                if (widget.label.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Text(widget.label, style: guFont(fontSize: 14, fontWeight: FontWeight.w800)),
                  ),
                Flexible(
                  child: SingleChildScrollView(
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: List.generate(widget.max + 1, (i) {
                        final selected = i == _value;
                        return InkWell(
                          borderRadius: BorderRadius.circular(8),
                          onTap: () => Navigator.pop(ctx, i),
                          child: Container(
                            width: 52,
                            height: 44,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: selected ? const Color(0xFFDBEAFE) : Colors.white,
                              border: Border.all(color: selected ? AppColors.navyLight : AppColors.border),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text('$i', style: guFont(fontSize: 16, fontWeight: FontWeight.w700)),
                          ),
                        );
                      }),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (picked != null) _setValue(picked);
  }

  @override
  Widget build(BuildContext context) {
    final borderColor = _isOver ? AppColors.rose : AppColors.border;
    final fillColor = !widget.enabled
        ? const Color(0xFFE9EDF3)
        : (_isOver ? AppColors.roseLight : AppColors.slateLight);

    final Widget field = widget.quickPickMode
        ? InkWell(
            borderRadius: BorderRadius.circular(AppRadius.sm),
            onTap: widget.enabled ? _openPicker : null,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
              decoration: BoxDecoration(
                color: fillColor,
                border: Border.all(color: borderColor, width: 1.5),
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: Text(
                '$_value',
                textAlign: TextAlign.center,
                style: guFont(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: widget.enabled ? AppColors.navy : AppColors.slate),
              ),
            ),
          )
        : TextField(
            controller: _controller,
            enabled: widget.enabled,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            style: guFont(fontSize: 18, fontWeight: FontWeight.w900),
            decoration: InputDecoration(
              filled: true,
              fillColor: fillColor,
              hintText: '0',
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.sm),
                borderSide: BorderSide(color: borderColor, width: 1.5),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.sm),
                borderSide: BorderSide(color: borderColor, width: 1.5),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.sm),
                borderSide: const BorderSide(color: AppColors.navyLight, width: 1.5),
              ),
            ),
            onChanged: (t) {
              final v = int.tryParse(t) ?? 0;
              setState(() => _value = v);
              widget.onChanged(v);
            },
          );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.label.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 5),
            child: Text(
              widget.label,
              textAlign: TextAlign.center,
              style: guFont(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.slate, letterSpacing: 0.5),
            ),
          ),
        field,
        Padding(
          padding: const EdgeInsets.only(top: 3),
          child: Text(
            _isOver ? 'મહત્તમ ${widget.max} ઓળંગાય છે' : 'મહત્તમ ${widget.max}',
            textAlign: TextAlign.center,
            style: guFont(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: _isOver ? AppColors.rose : const Color(0xFF94A3B8),
            ),
          ),
        ),
      ],
    );
  }
}
