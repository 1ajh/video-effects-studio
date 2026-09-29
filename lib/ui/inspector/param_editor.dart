import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/effects/effect.dart';
import '../../core/ffmpeg/blocks.dart';
import '../theme.dart';

/// Editor for one effect parameter.
class ParamEditor extends StatelessWidget {
  const ParamEditor({super.key, required this.param, required this.value, required this.onChanged});

  final EffectParam param;
  final Object? value;
  final ValueChanged<Object?> onChanged;

  @override
  Widget build(BuildContext context) {
    final v = param.sanitize(value);
    final isDefault = v == param.defaultValue;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(param.label, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
              ),
              if (!isDefault)
                InkWell(
                  borderRadius: BorderRadius.circular(4),
                  onTap: () => onChanged(param.defaultValue),
                  child: const Padding(
                    padding: EdgeInsets.all(2),
                    child: Tooltip(
                      message: 'Reset',
                      child: Icon(Icons.restart_alt, size: 14, color: AppColors.faint),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          switch (param.type) {
            ParamType.integer ||
            ParamType.decimal => _NumberEditor(param: param, value: v as num, onChanged: onChanged),
            ParamType.boolean => _ToggleEditor(param: param, value: v as bool, onChanged: onChanged),
            ParamType.choice => _ChoiceEditor(param: param, value: v as String, onChanged: onChanged),
            ParamType.text => _TextEditor(param: param, value: v as String, onChanged: onChanged),
          },
          if (param.hint != null) ...[
            const SizedBox(height: 4),
            Text(param.hint!, style: const TextStyle(fontSize: 11, color: AppColors.faint)),
          ],
        ],
      ),
    );
  }
}

class _NumberEditor extends StatefulWidget {
  const _NumberEditor({required this.param, required this.value, required this.onChanged});
  final EffectParam param;
  final num value;
  final ValueChanged<Object?> onChanged;

  @override
  State<_NumberEditor> createState() => _NumberEditorState();
}

class _NumberEditorState extends State<_NumberEditor> {
  late final TextEditingController _field = TextEditingController(text: _format(widget.value));
  final _focus = FocusNode();

  bool get _isInt => widget.param.type == ParamType.integer;

  String _format(num v) => _isInt ? '${v.round()}' : fmt(double.parse(v.toStringAsFixed(3)));

  @override
  void didUpdateWidget(covariant _NumberEditor old) {
    super.didUpdateWidget(old);
    if (!_focus.hasFocus && _format(widget.value) != _field.text) _field.text = _format(widget.value);
  }

  @override
  void dispose() {
    _field.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _commitText() {
    final parsed = num.tryParse(_field.text.trim());
    if (parsed == null) {
      _field.text = _format(widget.value);
      return;
    }
    widget.onChanged(widget.param.sanitize(parsed));
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.param;
    final min = p.min!.toDouble(), max = p.max!.toDouble();
    final step = (p.step ?? (_isInt ? 1 : (max - min) / 100)).toDouble();
    final divisions = ((max - min) / step).round();
    return Row(
      children: [
        Expanded(
          child: Slider(
            value: widget.value.toDouble().clamp(min, max),
            min: min,
            max: max,
            divisions: divisions > 0 && divisions <= 2000 ? divisions : null,
            onChanged: (x) {
              final snapped = _isInt
                  ? x.round()
                  : double.parse((((x - min) / step).round() * step + min).toStringAsFixed(4));
              widget.onChanged(snapped);
              if (!_focus.hasFocus) _field.text = _format(snapped);
            },
          ),
        ),
        SizedBox(
          width: 74,
          child: TextField(
            controller: _field,
            focusNode: _focus,
            textAlign: TextAlign.right,
            style: const TextStyle(fontSize: 12.5, fontFeatures: [FontFeature.tabularFigures()]),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[-0-9.]'))],
            decoration: InputDecoration(
              suffixText: p.unit,
              suffixStyle: const TextStyle(fontSize: 11, color: AppColors.faint),
              contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            ),
            onSubmitted: (_) => _commitText(),
            onTapOutside: (_) {
              if (_focus.hasFocus) {
                _commitText();
                _focus.unfocus();
              }
            },
          ),
        ),
      ],
    );
  }
}

class _ToggleEditor extends StatelessWidget {
  const _ToggleEditor({required this.param, required this.value, required this.onChanged});
  final EffectParam param;
  final bool value;
  final ValueChanged<Object?> onChanged;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Switch(value: value, onChanged: onChanged),
      const SizedBox(width: 8),
      Text(value ? 'On' : 'Off', style: const TextStyle(fontSize: 12, color: AppColors.muted)),
    ],
  );
}

class _ChoiceEditor extends StatelessWidget {
  const _ChoiceEditor({required this.param, required this.value, required this.onChanged});
  final EffectParam param;
  final String value;
  final ValueChanged<Object?> onChanged;

  @override
  Widget build(BuildContext context) {
    final options = param.options!;
    if (options.length <= 4 && options.every((o) => o.length <= 11)) {
      return SizedBox(
        width: double.infinity,
        child: SegmentedButton<String>(
          showSelectedIcon: false,
          segments: [for (final o in options) ButtonSegment(value: o, label: Text(o))],
          selected: {value},
          onSelectionChanged: (s) => onChanged(s.first),
        ),
      );
    }
    return DropdownButtonFormField<String>(
      initialValue: value,
      isExpanded: true,
      dropdownColor: AppColors.surface,
      borderRadius: BorderRadius.circular(10),
      style: const TextStyle(fontSize: 13, color: AppColors.text, fontFamily: 'Inter'),
      items: [for (final o in options) DropdownMenuItem(value: o, child: Text(o))],
      onChanged: (v) => v == null ? null : onChanged(v),
    );
  }
}

class _TextEditor extends StatefulWidget {
  const _TextEditor({required this.param, required this.value, required this.onChanged});
  final EffectParam param;
  final String value;
  final ValueChanged<Object?> onChanged;

  @override
  State<_TextEditor> createState() => _TextEditorState();
}

class _TextEditorState extends State<_TextEditor> {
  // Kept for the widget's lifetime so typing never loses the cursor.
  late final TextEditingController _c = TextEditingController(text: widget.value);

  @override
  void didUpdateWidget(covariant _TextEditor old) {
    super.didUpdateWidget(old);
    if (widget.value != _c.text) {
      _c.value = TextEditingValue(
        text: widget.value,
        selection: TextSelection.collapsed(offset: widget.value.length),
      );
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextField(
    controller: _c,
    style: const TextStyle(fontSize: 13, fontFamily: 'monospace'),
    onChanged: widget.onChanged,
  );
}
