from django.db import migrations

from apps.common.triggers import append_only


class Migration(migrations.Migration):
    dependencies = [("stockops", "0002_intake")]
    operations = [
        *append_only("stockops_stockintake"),
        *append_only("stockops_stockintakeline"),
    ]
