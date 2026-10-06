"""PostgreSQL triggers that make history tables append-only (no UPDATE, no DELETE)."""

from django.db import migrations

_FUNCTION = """
CREATE OR REPLACE FUNCTION erp_forbid_change() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    RAISE EXCEPTION 'table % is append-only', TG_TABLE_NAME USING ERRCODE = '55000';
END;
$$;
"""


def append_only(table: str) -> list[migrations.RunSQL]:
    """Migration operations that forbid UPDATE and DELETE on `table`."""
    return [
        migrations.RunSQL(
            sql=[
                _FUNCTION,
                f"CREATE TRIGGER {table}_append_only BEFORE UPDATE OR DELETE ON {table} "
                "FOR EACH ROW EXECUTE FUNCTION erp_forbid_change();",
            ],
            reverse_sql=[f"DROP TRIGGER IF EXISTS {table}_append_only ON {table};"],
        )
    ]
