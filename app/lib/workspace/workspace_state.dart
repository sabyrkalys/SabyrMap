import 'workspace.dart';

/// Рабочие пространства и активное.
class WorkspaceState {
  const WorkspaceState({this.workspaces = const [], this.activeId});

  final List<Workspace> workspaces;
  final String? activeId;

  Workspace? get active => workspaces.where((w) => w.id == activeId).firstOrNull;
}
