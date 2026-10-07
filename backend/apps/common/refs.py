"""Small JSON shapes shared by serializers: who did something, and a reference to a record."""


def person(user) -> dict | None:
    """`{id, name}` of a user (the full name when there is one), or None."""
    if user is None:
        return None
    return {"id": str(user.pk), "name": user.full_name or user.username}
