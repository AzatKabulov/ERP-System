from django.db import migrations

# A frozen copy of apps.expenses.services.DEFAULT_CATEGORIES: a migration must not change
# meaning when the code later does. A test keeps the two lists equal.
DEFAULT_CATEGORIES = ["Аренда", "Зарплата", "Коммунальные услуги", "Транспорт", "Прочее"]


def add_default_categories(apps, schema_editor):
    """Give every business that existed before expenses the same starting categories a new
    business gets. A business that somehow has the name already keeps its own row."""
    Business = apps.get_model("businesses", "Business")
    ExpenseCategory = apps.get_model("expenses", "ExpenseCategory")
    for business in Business.objects.all():
        for name in DEFAULT_CATEGORIES:
            if not ExpenseCategory.objects.filter(business=business, name__iexact=name).exists():
                ExpenseCategory.objects.create(business=business, name=name)


class Migration(migrations.Migration):
    dependencies = [
        ("businesses", "0005_simplify_sales"),
        ("expenses", "0001_initial"),
    ]
    operations = [migrations.RunPython(add_default_categories, migrations.RunPython.noop)]
