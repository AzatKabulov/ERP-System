"""Fixtures shared by the inventory and purchasing tests."""

import uuid
from decimal import Decimal

from apps.businesses.models import Role
from apps.catalog.models import Product, Unit
from apps.catalog.services import rebuild_search_key
from apps.common.testing import client_for, make_business, make_member
from apps.inventory import services
from apps.inventory.models import Condition, MovementType
from apps.purchasing import services as purchasing_services
from apps.sales import services as sales_services
from apps.stockops import services as stockops_services

D = Decimal


def make_product(business, sku="P-1", name="Brake pad", unit=None, price="100.00"):
    unit = (
        unit
        or Unit.objects.get_or_create(
            business=business, name="Piece", defaults={"symbol": "pc", "decimal_places": 0}
        )[0]
    )
    product = Product.objects.create(
        business=business, sku=sku, name=name, unit=unit, price_amount=D(price)
    )
    rebuild_search_key(product)  # the catalog service does this for real products
    return product


class World:
    """Business A (store + warehouse, one user per role) and an unrelated business B."""

    def __init__(self):
        self.a = make_business("Shop A", locations=("A Store", "A Warehouse"))
        self.b = make_business("Shop B", locations=("B Store",))
        self.store, self.warehouse = self.a.locations.order_by("name")
        self.b_store = self.b.locations.get()
        self.users = {
            Role.OWNER: make_member(self.a, Role.OWNER, username="a-owner"),
            Role.MANAGER: make_member(self.a, Role.MANAGER, username="a-manager"),
            Role.SALES: make_member(self.a, Role.SALES, username="a-sales", locations=[self.store]),
            Role.WAREHOUSE: make_member(
                self.a, Role.WAREHOUSE, username="a-warehouse", locations=[self.warehouse]
            ),
        }
        self.b_owner = make_member(self.b, Role.OWNER, username="b-owner")
        self.api = {role: client_for(user) for role, user in self.users.items()}
        self.b_api = client_for(self.b_owner)
        self.unit = Unit.objects.create(
            business=self.a, name="Piece", symbol="pc", decimal_places=0
        )
        self.litre = Unit.objects.create(
            business=self.a, name="Litre", symbol="l", decimal_places=2
        )
        self.pad = make_product(self.a, "BP-1", "Brake pad", self.unit)
        self.oil = make_product(self.a, "OIL-1", "Engine oil", self.litre)
        self.b_product = make_product(self.b, "B-1", "Other shop item")
        self.base = f"/api/v1/businesses/{self.a.pk}"

    @property
    def owner(self):
        return self.users[Role.OWNER]

    def stock(self, product, location, quantity, cost, condition=Condition.SELLABLE):
        """Put goods on the shelf through the ledger service (not through the API)."""
        return services.post(
            self.a,
            self.owner,
            [
                services.Line(
                    product=product,
                    location=location,
                    quantity=D(str(quantity)),
                    unit_cost=D(str(cost)),
                    movement_type=MovementType.ADJUSTMENT_IN,
                    condition=condition,
                )
            ],
            document_type="adjustment",
            document_id=uuid.uuid4(),
            reason="test fixture",
        )

    def remove(self, product, location, quantity, condition=Condition.SELLABLE):
        return services.post(
            self.a,
            self.owner,
            [
                services.Line(
                    product=product,
                    location=location,
                    quantity=-D(str(quantity)),
                    movement_type=MovementType.ADJUSTMENT_OUT,
                    condition=condition,
                )
            ],
            document_type="adjustment",
            document_id=uuid.uuid4(),
            reason="test fixture",
        )


def ledger_differences() -> list[str]:
    """Everything the ledger and the purchasing checks can find wrong, for every business."""
    return (
        services.reconcile()
        + purchasing_services.reconcile()
        + sales_services.reconcile()
        + stockops_services.reconcile()
    )
