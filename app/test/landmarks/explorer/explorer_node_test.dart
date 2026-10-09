import 'package:app/landmarks/explorer/explorer_node.dart';
import 'package:app/landmarks/models/landmark_type.dart';
import 'package:flutter_test/flutter_test.dart';

import 'explorer_fixture.dart';

void main() {
  test('folder node', () {
    const node = ExplorerFolderNode(path: '/a/trips', name: 'trips');
    expect(node.path, '/a/trips');
    expect(node.name, 'trips');
    expect(node.childCount, ExplorerFolderNode.unknownCount);
    expect(const ExplorerFolderNode(path: '/a', name: 'a', childCount: 3).childCount, 3);
  });

  test('item node takes path and name from the item', () {
    final i = item('Bunker', type: LandmarkType.waypoint);
    final node = ExplorerItemNode(i);
    expect(node.path, i.path);
    expect(node.name, 'Bunker');
    expect(node.item, i);
    expect(node, ExplorerItemNode(i));
  });

  test('the sealed hierarchy is matched exhaustively', () {
    String describe(ExplorerNode node) => switch (node) {
      ExplorerFolderNode(:final name) => 'folder $name',
      ExplorerItemNode(:final item) => 'item ${item.type.extension}',
    };
    expect(describe(const ExplorerFolderNode(path: '/a', name: 'a')), 'folder a');
    expect(describe(ExplorerItemNode(item('t'))), 'item trk');
  });
}
