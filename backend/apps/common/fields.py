from rest_framework import serializers


class BusinessScopedField(serializers.PrimaryKeyRelatedField):
    """A reference that only accepts records belonging to the request's business, so a
    client can never point a record at another business's data. The serializer context
    must carry `business`."""

    def get_queryset(self):
        return super().get_queryset().filter(business=self.context["business"])
