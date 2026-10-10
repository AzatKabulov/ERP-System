from django.db import migrations

from apps.common.triggers import append_only


class Migration(migrations.Migration):
    dependencies = [("purchasing", "0001_initial")]
    operations = [
        *append_only("purchasing_delivery"),
        *append_only("purchasing_deliveryline"),
    ]
