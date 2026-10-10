from django.db import migrations

from apps.common.triggers import append_only


class Migration(migrations.Migration):
    dependencies = [("purchasing", "0003_supplier_returns")]
    operations = [
        *append_only("purchasing_supplierreturn"),
        *append_only("purchasing_supplierreturnline"),
    ]
