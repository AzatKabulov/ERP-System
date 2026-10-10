from django.http import HttpResponse
from django.shortcuts import get_object_or_404
from django.utils.http import content_disposition_header
from rest_framework.parsers import MultiPartParser
from rest_framework.response import Response

from apps.businesses.access import BusinessAPIView
from apps.common.negotiation import IgnoreClientContentNegotiation
from apps.common.uploads import declared_size_exceeds

from . import services
from .models import Attachment
from .serializers import AttachmentSerializer


class AttachmentCreateView(BusinessAPIView):
    """Upload one file (multipart, field `file`). The type is decided from the file's first
    bytes, not from its name or the declared content type."""

    required_permission = "attachment.upload"
    parser_classes = [MultiPartParser]

    def post(self, request, business_id):
        if declared_size_exceeds(request, services.MAX_BYTES):
            raise services.too_large()
        attachment = services.store_upload(
            request.business, request.user, request.FILES.get("file")
        )
        return Response(AttachmentSerializer(attachment).data, status=201)


class AttachmentDetailView(BusinessAPIView):
    """The file itself. The business comes from the URL and the record must belong to it, so
    another business's file is a 404 even for a user who guessed its id."""

    required_permission = "attachment.view"
    content_negotiation_class = IgnoreClientContentNegotiation

    def get(self, request, business_id, attachment_id):
        attachment = get_object_or_404(Attachment, pk=attachment_id, business=request.business)
        response = HttpResponse(
            services.read_bytes(attachment), content_type=attachment.content_type
        )
        response["Content-Disposition"] = content_disposition_header(False, attachment.name)
        response["X-Content-Type-Options"] = "nosniff"
        response["Cache-Control"] = "private, no-store"
        return response
