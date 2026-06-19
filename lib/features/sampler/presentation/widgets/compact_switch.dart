import 'package:flutter/material.dart';

/// Interrupteur Material 3 réduit pour les listes denses (paramètres, etc.).
class CompactSwitch extends StatelessWidget {
  const CompactSwitch({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;

  static const _width = 46.0;
  static const _height = 28.0;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _width,
      height: _height,
      child: FittedBox(
        fit: BoxFit.contain,
        child: Switch(
          value: value,
          onChanged: onChanged,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ),
    );
  }
}

/// Tuile de paramètre avec un [CompactSwitch] à droite.
class CompactSwitchListTile extends StatelessWidget {
  const CompactSwitchListTile({
    super.key,
    required this.title,
    this.subtitle,
    required this.value,
    required this.onChanged,
    this.contentPadding = EdgeInsets.zero,
  });

  final Widget title;
  final Widget? subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final EdgeInsetsGeometry contentPadding;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: contentPadding,
      title: title,
      subtitle: subtitle,
      trailing: CompactSwitch(value: value, onChanged: onChanged),
    );
  }
}
