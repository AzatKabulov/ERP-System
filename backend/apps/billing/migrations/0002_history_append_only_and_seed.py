from django.db import migrations

from apps.common.triggers import append_only

PLANS = [
    ("monthly", "1 месяц", 1, 10),
    ("quarterly", "3 месяца", 3, 20),
    ("yearly", "1 год", 12, 30),
    ("custom", "Свой срок (дни)", None, 90),
]


def seed(apps, schema_editor):
    Plan = apps.get_model("billing", "Plan")
    for code, name, months, order in PLANS:
        Plan.objects.get_or_create(
            code=code, defaults={"name": name, "months": months, "sort_order": order}
        )
    # Stores that existed before billing was introduced keep working: free access, which we can
    # turn into a normal subscription from the console whenever they start paying.
    Business = apps.get_model("businesses", "Business")
    Client = apps.get_model("billing", "Client")
    for business in Business.objects.all():
        Client.objects.get_or_create(business=business, defaults={"override": "free"})


class Migration(migrations.Migration):
    dependencies = [
        ("billing", "0001_initial"),
        ("businesses", "0005_simplify_sales"),
    ]

    operations = [
        migrations.RunPython(seed, migrations.RunPython.noop),
        *append_only("billing_subscriptionevent"),
        *append_only("billing_clientnote"),
        *append_only("billing_supportmessage"),
    ]
