from django.core.management.base import BaseCommand, CommandError

from apps.businesses.models import Business
from apps.inventory import services


class Command(BaseCommand):
    help = (
        "Check that stock balances, movements and FIFO cost layers agree (and, where present, "
        "that purchase-order receipts, sales and transfers match their stock movements). "
        "Exits non-zero if any difference is found."
    )

    def add_arguments(self, parser):
        parser.add_argument("--business", help="Business id; default: all businesses")

    def handle(self, *args, **opts):
        business = None
        if opts["business"]:
            try:
                business = Business.objects.get(pk=opts["business"])
            except (Business.DoesNotExist, ValueError) as exc:
                raise CommandError("Unknown business") from exc
        differences = services.reconcile(business)
        for name in ("purchasing", "sales", "stockops"):
            try:
                module = __import__(f"apps.{name}.services", fromlist=["reconcile"])
            except ImportError:  # app not installed
                continue
            differences += module.reconcile(business)
        if differences:
            for line in differences:
                self.stderr.write(line)
            raise CommandError(f"{len(differences)} difference(s) found")
        self.stdout.write("Ledger is consistent.")
