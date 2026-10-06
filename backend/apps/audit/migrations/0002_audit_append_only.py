from django.db import migrations

from apps.common.triggers import append_only


class Migration(migrations.Migration):
    dependencies = [("audit", "0001_initial")]
    operations = append_only("audit_auditevent")
