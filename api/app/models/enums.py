import enum


class Role(str, enum.Enum):
    OWNER = "owner"
    ADMIN = "admin"
    MEMBER = "member"
    VIEWER = "viewer"


class ResourceType(str, enum.Enum):
    WAYPOINT = "waypoint"
    TRACK = "track"


class ShareScope(str, enum.Enum):
    USER = "user"
    ORGANIZATION = "organization"


class Permission(str, enum.Enum):
    VIEW = "view"
    EDIT = "edit"
