from django.db import migrations

from apps.common.triggers import append_only


class Migration(migrations.Migration):
    dependencies = [("sales", "0001_initial")]
    operations = [
        *append_only("sales_sale"),
        *append_only("sales_saleline"),
        *append_only("sales_salepayment"),
    ]
