from django.db import migrations

from apps.common.triggers import append_only


class Migration(migrations.Migration):
    dependencies = [("businesses", "0002_exchange_rate")]
    operations = append_only("businesses_exchangerate")
