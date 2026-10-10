import 'package:flutter/material.dart';

/// Цвета шторок-меню проводника.
abstract final class SheetMenuColors {
  static const Color text = Color(0xFF212121);
  static const Color secondary = Color(0xFF757575);
  static const Color accent = Color(0xFF00A38E);
  static const Color clipboard = Color(0xFF9C27B0);
  static const Color edit = Color(0xFFD32F2F);
  static const Color divider = Color(0xFFBDBDBD);
}

/// Пункт шторки-меню: иконка 24 в поле 32, отступ 16, подпись 16.
class SheetMenuItem extends StatelessWidget {
  const SheetMenuItem({
    super.key,
    required this.icon,
    required this.color,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(8),
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          SizedBox(width: 32, child: Icon(icon, size: 24, color: color)),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontSize: 16, color: SheetMenuColors.text),
            ),
          ),
        ],
      ),
    ),
  );
}

/// Линия с подписью раздела: «— БУФЕР ОБМЕНА ——».
class SheetMenuSection extends StatelessWidget {
  const SheetMenuSection(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Row(
      children: [
        const SizedBox(
          width: 24,
          child: Divider(color: SheetMenuColors.divider, height: 1),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Text(
            label.toUpperCase(),
            style: const TextStyle(
              fontSize: 12,
              color: SheetMenuColors.secondary,
              letterSpacing: 0.5,
            ),
          ),
        ),
        const Expanded(
          child: Divider(color: SheetMenuColors.divider, height: 1),
        ),
      ],
    ),
  );
}

/// Кнопка «ОТМЕНА» справа внизу шторки.
class SheetMenuCancel extends StatelessWidget {
  const SheetMenuCancel({super.key, this.buttonKey, required this.onPressed});

  /// Ключ самой кнопки (ключ виджета — у строки на всю ширину).
  final Key? buttonKey;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Align(
      alignment: Alignment.centerRight,
      child: TextButton(
        key: buttonKey,
        onPressed: onPressed,
        style: TextButton.styleFrom(foregroundColor: SheetMenuColors.accent),
        child: const Text(
          'ОТМЕНА',
          style: TextStyle(fontWeight: FontWeight.w600, letterSpacing: 0.5),
        ),
      ),
    ),
  );
}

/// Белая шторка со скруглением сверху: заголовок 22 и пункты.
class SheetMenu extends StatelessWidget {
  const SheetMenu({super.key, required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Material(
    // Material, а не цветной Container: иначе волна нажатия пунктов не видна.
    color: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    child: SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w500,
                  color: SheetMenuColors.text,
                ),
              ),
            ),
            ...children,
          ],
        ),
      ),
    ),
  );
}
