from django.db import migrations, models


class Migration(migrations.Migration):
    dependencies = [("stockops", "0003_intake_append_only")]

    operations = [
        migrations.AddField(
            model_name="stockintakeline",
            name="expiry_date",
            field=models.DateField(null=True, blank=True),
        ),
    ]
