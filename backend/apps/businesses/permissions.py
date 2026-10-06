"""Role -> permission matrix. PROVISIONAL (PLAN.md D5): drafted from the PRD's role
descriptions and awaiting the owner's review. Enforced on the server for every request.

Add a permission here when a workflow needs it; a view with no permission is denied."""

from .models import Role

# Permission codes grouped by area. Later phases extend this table.
MATRIX: dict[str, frozenset[str]] = {
    # business and access
    "business.view": frozenset({Role.OWNER, Role.MANAGER, Role.SALES, Role.WAREHOUSE}),
    "business.manage": frozenset({Role.OWNER}),
    "location.view": frozenset({Role.OWNER, Role.MANAGER, Role.SALES, Role.WAREHOUSE}),
    "location.manage": frozenset({Role.OWNER}),
    "staff.view": frozenset({Role.OWNER, Role.MANAGER}),
    "staff.manage": frozenset({Role.OWNER}),
    "exchange_rate.view": frozenset({Role.OWNER, Role.MANAGER, Role.SALES, Role.WAREHOUSE}),
    "exchange_rate.manage": frozenset({Role.OWNER, Role.MANAGER}),
    # catalog
    "catalog.view": frozenset({Role.OWNER, Role.MANAGER, Role.SALES, Role.WAREHOUSE}),
    "catalog.manage": frozenset({Role.OWNER, Role.MANAGER}),
    "catalog.cost.view": frozenset({Role.OWNER, Role.MANAGER}),
    # inventory
    "stock.view": frozenset({Role.OWNER, Role.MANAGER, Role.SALES, Role.WAREHOUSE}),
    "stock.history.view": frozenset({Role.OWNER, Role.MANAGER, Role.WAREHOUSE}),
    "stock.cost.view": frozenset({Role.OWNER, Role.MANAGER}),
    "stock.opening.post": frozenset({Role.OWNER, Role.MANAGER}),
    "stock.adjust": frozenset({Role.OWNER, Role.MANAGER}),
    # purchasing
    "supplier.view": frozenset({Role.OWNER, Role.MANAGER, Role.WAREHOUSE}),
    "supplier.manage": frozenset({Role.OWNER, Role.MANAGER}),
    "purchasing.view": frozenset({Role.OWNER, Role.MANAGER, Role.WAREHOUSE}),
    "purchasing.manage": frozenset({Role.OWNER, Role.MANAGER}),
    "purchasing.receive": frozenset({Role.OWNER, Role.MANAGER, Role.WAREHOUSE}),
    "purchasing.cost.view": frozenset({Role.OWNER, Role.MANAGER}),
    # every member may look up the outcome of their own operations
    "operations.view": frozenset({Role.OWNER, Role.MANAGER, Role.SALES, Role.WAREHOUSE}),
}


def has_permission(role: str, code: str) -> bool:
    return role in MATRIX.get(code, frozenset())


def permissions_for(role: str) -> list[str]:
    return sorted(code for code, roles in MATRIX.items() if role in roles)
