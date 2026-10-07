from django.db import migrations

from apps.common.triggers import append_only


class Migration(migrations.Migration):
    dependencies = [("warranties", "0001_initial")]
    operations = [*append_only("warranties_warrantyevent")]
