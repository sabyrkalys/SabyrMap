import 'package:flutter/material.dart';

/// Раздел «Онлайн-метки» пока не сделан.
abstract final class OnlineMarksPlaceholder {
  static const String message = 'Раздел в разработке';

  static void show(BuildContext context) =>
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text(message)));
}
