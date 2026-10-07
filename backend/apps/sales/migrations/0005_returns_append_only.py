from django.db import migrations

from apps.common.triggers import append_only


class Migration(migrations.Migration):
    dependencies = [("sales", "0004_returns")]
    operations = [
        *append_only("sales_salereturn"),
        *append_only("sales_salereturnline"),
        *append_only("sales_returninspection"),
    ]
