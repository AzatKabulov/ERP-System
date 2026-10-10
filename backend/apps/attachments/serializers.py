from rest_framework import serializers

from .models import Attachment


class AttachmentRefSerializer(serializers.ModelSerializer):
    """The short form other records carry (an expense's receipt)."""

    class Meta:
        model = Attachment
        fields = ["id", "name", "content_type", "size"]


class AttachmentSerializer(serializers.ModelSerializer):
    class Meta:
        model = Attachment
        fields = ["id", "name", "content_type", "size", "created_at"]
