from django.db import migrations, models


class Migration(migrations.Migration):
    dependencies = [("inventory", "0008_layer_cost_known")]

    operations = [
        migrations.AddField(
            model_name="costlayer",
            name="expiry_date",
            field=models.DateField(null=True, blank=True),
        ),
        migrations.AddIndex(
            model_name="costlayer",
            index=models.Index(
                fields=["business", "expiry_date"],
                condition=models.Q(quantity_remaining__gt=0, expiry_date__isnull=False),
                name="inventory_live_expiry",
            ),
        ),
    ]
