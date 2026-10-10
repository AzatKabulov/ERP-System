import hashlib

from rest_framework.throttling import SimpleRateThrottle


class _HashedIdentityThrottle(SimpleRateThrottle):
    """Throttle per (client address, claimed identity), hashed so cache keys stay safe."""

    field = "username"

    def get_cache_key(self, request, view):
        claimed = (
            str(request.data.get(self.field, "")).strip().lower()
            if hasattr(request.data, "get")
            else ""
        )
        digest = hashlib.sha256(claimed.encode()).hexdigest()[:32]
        return self.cache_format % {
            "scope": self.scope,
            "ident": f"{self.get_ident(request)}:{digest}",
        }


class _IPThrottle(SimpleRateThrottle):
    def get_cache_key(self, request, view):
        return self.cache_format % {"scope": self.scope, "ident": self.get_ident(request)}


class LoginIdentityThrottle(_HashedIdentityThrottle):
    scope = "login_identity"
    field = "username"


class LoginIPThrottle(_IPThrottle):
    scope = "login_ip"


class ResetRequestIPThrottle(_IPThrottle):
    scope = "reset_request_ip"


class ResetRequestIdentityThrottle(_HashedIdentityThrottle):
    scope = "reset_request_identity"
    field = "identifier"


class ResetConfirmIPThrottle(_IPThrottle):
    scope = "reset_confirm_ip"
