import 'package:flutter/material.dart';

const Color _background = Color(0xFFEEEEEE);
const Color _foreground = Color(0xFF333333);

/// A 48×48 grey square with an icon (flag, palette, pencil), or [child]
/// in its place (the chosen waypoint icon).
class ActionButton extends StatelessWidget {
  const ActionButton({super.key, required this.icon, required this.onTap, this.iconColor = _foreground, this.child});

  final IconData icon;
  final VoidCallback onTap;
  final Color iconColor;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: _background,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: SizedBox(
          width: 48,
          height: 48,
          child: Center(child: child ?? Icon(icon, size: 24, color: iconColor)),
        ),
      ),
    );
  }
}

/// The wide grey «ЕЩЁ...» button that fills the rest of the row.
class WideActionButton extends StatelessWidget {
  const WideActionButton({super.key, required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: _background,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: SizedBox(
          height: 48,
          child: Center(
            child: Text(label, style: const TextStyle(fontSize: 15, color: Color(0xFF212121))),
          ),
        ),
      ),
    );
  }
}
