from rest_framework.negotiation import BaseContentNegotiation


class IgnoreClientContentNegotiation(BaseContentNegotiation):
    """For endpoints that answer with a file (a PDF) instead of JSON: never refuse a request
    just because its Accept header asks for something other than the API's JSON renderer."""

    def select_parser(self, request, parsers):
        return parsers[0]

    def select_renderer(self, request, renderers, format_suffix=None):
        return renderers[0], renderers[0].media_type
