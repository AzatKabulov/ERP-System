from rest_framework import serializers

from apps.common.refs import person

from .models import AuditEvent


class AuditEventSerializer(serializers.ModelSerializer):
    """One entry of the activity history. The request id stays internal."""

    actor = serializers.SerializerMethodField()

    class Meta:
        model = AuditEvent
        fields = ["id", "action", "object_type", "object_id", "actor", "created_at", "metadata"]
        read_only_fields = fields

    def get_actor(self, event) -> dict | None:
        return person(event.actor)
