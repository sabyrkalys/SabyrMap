import 'dart:convert';
import 'dart:typed_data';

import 'package:xml/xml.dart';

import 'charset_detector.dart';

/// Обёртки над пакетом `xml` для форматов меток.
abstract final class XmlUtils {
  /// Документ из байтов. Кодировка: [charset], иначе BOM / объявление XML /
  /// автоопределение. Битый XML — [FormatException].
  static XmlDocument parseBytes(Uint8List bytes, {String? charset}) {
    final text = CharsetDetector.decode(bytes, charset: charset ?? declaredEncoding(bytes));
    try {
      return XmlDocument.parse(text.startsWith('﻿') ? text.substring(1) : text);
    } on XmlException catch (e) {
      throw FormatException('Invalid XML: ${e.message}');
    }
  }

  /// Документ в байты UTF-8 с отступами.
  static Uint8List serialize(XmlDocument doc) => utf8.encode(doc.toXmlString(pretty: true, indent: '  '));

  /// Кодировка из объявления XML, если указана и поддерживается.
  static String? declaredEncoding(Uint8List bytes) => CharsetDetector.xmlDeclaredEncoding(bytes);

  /// Прямые дочерние элементы с локальным именем [name] (любое пространство имён).
  static Iterable<XmlElement> children(XmlElement element, String name) =>
      element.childElements.where((e) => e.localName == name);

  /// Первый дочерний элемент с локальным именем [name].
  static XmlElement? child(XmlElement element, String name) => children(element, name).firstOrNull;

  /// Текст первого дочернего [name] без пробелов по краям; пусто — null.
  static String? childText(XmlElement element, String name) {
    final text = child(element, name)?.innerText.trim();
    return text == null || text.isEmpty ? null : text;
  }

  /// Все элементы-потомки с локальным именем [name], в порядке документа.
  static Iterable<XmlElement> descendants(XmlNode node, String name) =>
      node.descendantElements.where((e) => e.localName == name);
}
