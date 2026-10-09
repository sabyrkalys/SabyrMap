import 'package:app/exceptions/serialization_exception.dart';
import 'package:app/landmarks/drafts/metadata_patch.dart';
import 'package:app/landmarks/models/landmark_metadata.dart';
import 'package:app/landmarks/services/metadata_editor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final editor = MetadataEditor(clock: () => DateTime.fromMillisecondsSinceEpoch(1760000000000));
  const source = LandmarkMetadata(entries: {'name': 'A', 'comment': 'c', 'created_at': 1}, version: 5);

  test('set puts keys', () {
    final out = editor.apply(source, const MetadataPatch(set: {'color': 0xFF000000, 'name': 'B'}));
    expect(out.colorValue, 0xFF000000);
    expect(out.name, 'B');
    expect(out.comment, 'c');
  });

  test('remove drops keys', () {
    final out = editor.apply(source, const MetadataPatch(remove: {'comment', 'missing'}));
    expect(out.entries.containsKey('comment'), isFalse);
    expect(out.name, 'A');
  });

  test('remove runs before set', () {
    final out = editor.apply(source, const MetadataPatch(set: {'comment': 'new'}, remove: {'comment'}));
    expect(out.comment, 'new');
  });

  test('null in set removes the key', () {
    final out = editor.apply(source, const MetadataPatch(set: {'comment': null}));
    expect(out.entries.containsKey('comment'), isFalse);
  });

  test('version always grows by one, even for an empty patch', () {
    expect(editor.apply(source, const MetadataPatch()).version, 6);
    expect(editor.apply(const LandmarkMetadata(), const MetadataPatch()).version, 1);
  });

  test('updated_at is now, created_at is kept', () {
    final out = editor.apply(source, const MetadataPatch(set: {'updated_at': 5}));
    expect(out.updatedAtMs, 1760000000000);
    expect(out.createdAtMs, 1);
  });

  test('created_at is set when missing', () {
    final out = editor.apply(const LandmarkMetadata(entries: {'name': 'A'}), const MetadataPatch());
    expect(out.createdAtMs, 1760000000000);
  });

  test('the source is not changed', () {
    editor.apply(source, const MetadataPatch(remove: {'name'}));
    expect(source.name, 'A');
    expect(source.version, 5);
  });

  test('validateEntries rejects values the file cannot hold', () {
    editor.validateEntries(source);
    expect(
      () => editor.validateEntries(LandmarkMetadata(entries: {'when': DateTime(2026)})),
      throwsA(isA<SerializationException>()),
    );
    expect(
      () => editor.validateEntries(const LandmarkMetadata(entries: {'style': {'w': 1}})),
      throwsA(isA<SerializationException>()),
    );
    expect(() => editor.apply(source, const MetadataPatch(set: {'list': [1]})), throwsA(isA<SerializationException>()));
  });
}
