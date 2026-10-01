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
    if (options.length > 30) return _SearchableChoice(param: param, value: value, onChanged: onChanged);
    return DropdownButtonFormField<String>(
      initialValue: value,
      isExpanded: true,
      dropdownColor: AppColors.surface,
      borderRadius: BorderRadius.circular(10),
      style: const TextStyle(fontSize: 13, color: AppColors.text, fontFamily: 'Inter'),
      items: [
        for (final o in options)
          DropdownMenuItem(
            value: o,
            child: Text(o, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: (v) => v == null ? null : onChanged(v),
    );
  }
}

/// A long list of choices (the Sparta Sequencer's patterns): the current one
/// as a button that opens a searchable list.
class _SearchableChoice extends StatelessWidget {
  const _SearchableChoice({required this.param, required this.value, required this.onChanged});
  final EffectParam param;
  final String value;
  final ValueChanged<Object?> onChanged;

  Future<void> _pick(BuildContext context) async {
    final picked = await showDialog<String>(
      context: context,
      builder: (_) => _ChoiceSearchDialog(title: param.label, options: param.options!, value: value),
    );
    if (picked != null) onChanged(picked);
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => _pick(context),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(value, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13)),
            ),
            const Icon(Icons.search, size: 16, color: AppColors.muted),
          ],
        ),
      ),
    );
  }
}

class _ChoiceSearchDialog extends StatefulWidget {
  const _ChoiceSearchDialog({required this.title, required this.options, required this.value});
  final String title;
  final List<String> options;
  final String value;

  @override
  State<_ChoiceSearchDialog> createState() => _ChoiceSearchDialogState();
}

class _ChoiceSearchDialogState extends State<_ChoiceSearchDialog> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final words = _query.toLowerCase().split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
    final list = [
      for (final o in widget.options)
        if (words.every((w) => o.toLowerCase().contains(w))) o,
    ];
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 520,
        height: 480,
        child: Column(
          children: [
            TextField(
              autofocus: true,
              decoration: const InputDecoration(
                isDense: true,
                prefixIcon: Icon(Icons.search, size: 18),
                hintText: 'Search',
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
            const SizedBox(height: 6),
            Expanded(
              child: ListView.builder(
                itemCount: list.length,
                itemBuilder: (context, i) => ListTile(
                  dense: true,
                  selected: list[i] == widget.value,
                  leading: Icon(
                    list[i] == widget.value ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                    size: 18,
                  ),
                  title: Text(list[i]),
                  onTap: () => Navigator.pop(context, list[i]),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel'))],
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
