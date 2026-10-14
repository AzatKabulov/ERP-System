from django.db import migrations

from apps.common.triggers import append_only


class Migration(migrations.Migration):
    dependencies = [("sales", "0006_cost_known_and_corrections")]
    operations = [*append_only("sales_costcorrection")]
