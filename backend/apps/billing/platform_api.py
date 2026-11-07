"""The platform owner's page in the app: every client, their subscriptions, the support desk, the
notices and the packages. The same things the old console offers, behind the ordinary sign-in.

Who may use it: an operator (`User.is_staff`, made with `manage.py create_operator`). They sign in
like anyone else, with one more step: the code from their authenticator app, checked at sign-in
(accounts.views.check_operator_code). A store's staff get 403 on every route here. Every change to a
subscription goes through services.py, which writes the history entry in the same transaction, and
every button shows what it will do (the "review" step) before it does it.
"""

from datetime import timedelta

from django.db import transaction
from django.db.models import Max, Q
from django.shortcuts import get_object_or_404
from django.utils import timezone
from django_otp.plugins.otp_totp.models import TOTPDevice
from rest_framework import serializers
from rest_framework.permissions import BasePermission, IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView

from apps.audit import services as audit
from apps.businesses.models import Membership, Role
from apps.common.errors import ApiError

from . import dashboard, services
from . import forms as console_forms
from .console import ACTIONS
from .models import (
    Announcement,
    Client,
    ClientNote,
    Plan,
    SubscriptionEvent,
    SupportMessage,
    SupportRequest,
)
from .status import ACTIVE, EXPIRING, status_for

MAX_ROWS = 500


class IsPlatformOperator(BasePermission):
    """An operator who has an authenticator. (Sign-in already asked for its code; this is the
    second lock on the door.)"""

    def has_permission(self, request, view):
        user = request.user
        return bool(
            user
            and user.is_authenticated
            and user.is_active
            and user.is_staff
            and TOTPDevice.objects.filter(user=user, confirmed=True).exists()
        )


class OperatorView(APIView):
    permission_classes = [IsAuthenticated, IsPlatformOperator]


# ---------------------------------------------------------------------------------------------
# How a client is described to the app


def _money(value) -> str | None:
    """Amounts travel as exact text ("150.00"), never as floating-point numbers."""
    return None if value is None else str(value)


def _owner_logins(business_ids) -> dict:
    rows = Membership.objects.filter(
        business_id__in=business_ids, role=Role.OWNER, is_active=True
    ).select_related("user")
    return {m.business_id: m.user for m in rows}


def _last_payments(client_ids) -> dict:
    rows = (
        SubscriptionEvent.objects.filter(client_id__in=client_ids, amount__isnull=False)
        .values("client_id")
        .annotate(last=Max("created_at"))
    )
    return {r["client_id"]: r["last"] for r in rows}


def _row(client, status, usage, owner, last_payment) -> dict:
    return {
        "id": str(client.pk),
        "business_id": str(client.business_id),
        "store_name": client.business.name,
        "state": status.state,
        "is_trial": status.is_trial,
        "plan": client.plan.name if client.plan else None,
        "ends_at": status.ends_at,
        "grace_ends_at": status.grace_ends_at,
        "days_left": status.days_left,
        "owner_login": owner.username if owner else "",
        "owner_name": (owner.full_name if owner else "") or client.contact_name,
        "phone": client.contact_phone,
        "last_payment_at": last_payment,
        "last_sign_in": usage["last_sign_in"],
        "staff": usage["staff"],
        "sales_30d": usage["sales_30d"],
    }


def _rows(clients, now) -> list[dict]:
    clients = list(clients)
    ids = [c.pk for c in clients]
    business_ids = [c.business_id for c in clients]
    usage = dashboard.usage(business_ids, now)
    owners = _owner_logins(business_ids)
    paid = _last_payments(ids)
    return [
        _row(
            c,
            status_for(c, c.business, now),
            usage[c.business_id],
            owners.get(c.business_id),
            paid.get(c.pk),
        )
        for c in clients
    ]


def _matches(state, is_trial, wanted) -> bool:
    if not wanted:
        return True
    if wanted == "attention":
        return state in dashboard.ATTENTION
    if wanted == "trial":
        return is_trial and state in (ACTIVE, EXPIRING)
    return wanted == state


def _event(e) -> dict:
    return {
        "id": str(e.pk),
        "kind": e.kind,
        "plan": e.plan.name if e.plan else None,
        "months": e.months,
        "days": e.days,
        "old_until": e.old_until,
        "new_until": e.new_until,
        "amount": _money(e.amount),
        "currency": e.currency,
        "method": e.method,
        "reference": e.reference,
        "note": e.note,
        "by": e.actor.username if e.actor else "",
        "at": e.created_at,
    }


def _detail(client, now=None) -> dict:
    now = now or timezone.now()
    client = Client.objects.select_related("business", "plan").get(pk=client.pk)
    (row,) = _rows([client], now)
    staff = (
        Membership.objects.filter(business=client.business)
        .select_related("user")
        .order_by("role", "user__username")
    )
    return {
        **row,
        "contact": {
            "name": client.contact_name,
            "phone": client.contact_phone,
            "email": client.contact_email,
        },
        "suspended": client.override == Client.Override.SUSPENDED,
        "free": client.override == Client.Override.FREE,
        "paid_until": client.paid_until,
        "events": [_event(e) for e in client.events.select_related("actor", "plan")[:40]],
        "notes": [
            {"id": str(n.pk), "text": n.text, "by": n.author.username, "at": n.created_at}
            for n in client.notes.select_related("author")[:40]
        ],
        "support": [
            {"id": str(t.pk), "subject": t.subject, "status": t.status, "at": t.updated_at}
            for t in SupportRequest.objects.filter(business=client.business)[:10]
        ],
        "people": [
            {
                "username": m.user.username,
                "name": m.user.full_name,
                "role": m.role,
                "active": m.is_active and m.user.is_active,
                "last_sign_in": m.user.last_login,
            }
            for m in staff
        ],
    }


def _plan(p) -> dict:
    return {
        "id": str(p.pk),
        "code": p.code,
        "name": p.name,
        "months": p.months,
        "price": _money(p.price),
        "currency": p.currency,
        "is_active": p.is_active,
    }


def _form_errors(form) -> ApiError:
    return ApiError(
        "validation_error",
        "Some fields are wrong",
        fields={
            name: [{"code": e["code"], "message": e["message"]} for e in errors]
            for name, errors in form.errors.get_json_data().items()
        },
    )


# ---------------------------------------------------------------------------------------------
# Overview and clients


class OverviewView(OperatorView):
    def get(self, request):
        now = timezone.now()
        snap = dashboard.snapshot(now)
        attention = [c for c, _ in snap["attention"]]
        rows = {r["id"]: r for r in _rows(attention, now)}
        payments = SubscriptionEvent.objects.filter(amount__isnull=False).select_related(
            "client__business", "plan"
        )[:8]
        return Response(
            {
                "total": snap["total"],
                "counts": snap["counts"],
                "attention": [rows[str(c.pk)] for c in attention],
                "income_this_month": {
                    currency: _money(total) for currency, total in snap["income_this_month"].items()
                },
                "new_30_days": snap["new_30_days"],
                "lapsed_this_month": snap["lapsed_this_month"],
                "recent_payments": [
                    {
                        "client_id": str(e.client_id),
                        "store_name": e.client.business.name,
                        "amount": _money(e.amount),
                        "currency": e.currency,
                        "method": e.method,
                        "at": e.created_at,
                    }
                    for e in payments
                ],
            }
        )


class ClientListView(OperatorView):
    def get(self, request):
        now = timezone.now()
        wanted = request.query_params.get("state", "")
        query = request.query_params.get("q", "").strip()
        clients = Client.objects.select_related("business", "plan")
        if query:
            clients = clients.filter(
                Q(business__name__icontains=query)
                | Q(contact_name__icontains=query)
                | Q(contact_phone__icontains=query)
                | Q(contact_email__icontains=query)
            )
        picked = [
            c
            for c in clients
            if _matches(
                status_for(c, c.business, now).state,
                c.is_trial,
                wanted,
            )
        ][:MAX_ROWS]
        far = now + timedelta(days=36500)
        rows = _rows(picked, now)
        rows.sort(key=lambda r: (r["ends_at"] or far, r["store_name"].lower()))
        return Response({"results": rows})

    def post(self, request):
        form = console_forms.NewClientForm(request.data)
        if not form.is_valid():
            raise _form_errors(form)
        data = form.cleaned_data
        try:
            client, password = services.provision_client(
                store_name=data["store_name"],
                owner_username=data["owner_login"] or services.suggest_login(data["store_name"]),
                owner_name=data["owner_name"],
                owner_email=data["owner_email"],
                phone=data["phone"],
                language=data["language"],
                plan=data["start"],
                amount=data["amount"],
                currency=data["currency"],
                method=data["method"],
                reference=data["reference"],
                note=data["note"],
                actor=request.user,
            )
        except services.BillingError as exc:
            raise ApiError("billing_error", str(exc), status_code=409) from exc
        owner = Membership.objects.get(business=client.business, role=Role.OWNER).user
        return Response(
            {"client": _detail(client), "login": owner.username, "password": password},
            status=201,
        )


class ContactSerializer(serializers.Serializer):
    name = serializers.CharField(max_length=200, required=False, allow_blank=True)
    phone = serializers.CharField(max_length=60, required=False, allow_blank=True)
    email = serializers.EmailField(required=False, allow_blank=True)


class ClientDetailView(OperatorView):
    def get(self, request, client_id):
        client = get_object_or_404(Client, pk=client_id)
        return Response(_detail(client))

    def patch(self, request, client_id):
        client = get_object_or_404(Client, pk=client_id)
        data = ContactSerializer(data=request.data)
        data.is_valid(raise_exception=True)
        v = data.validated_data
        if "name" in v:
            client.contact_name = v["name"].strip()
        if "phone" in v:
            client.contact_phone = v["phone"].strip()
        if "email" in v:
            client.contact_email = v["email"].strip()
        client.save(update_fields=["contact_name", "contact_phone", "contact_email", "updated_at"])
        return Response(_detail(client))


class NoteSerializer(serializers.Serializer):
    text = serializers.CharField(max_length=2000)


class ClientNoteView(OperatorView):
    def post(self, request, client_id):
        client = get_object_or_404(Client, pk=client_id)
        data = NoteSerializer(data=request.data)
        data.is_valid(raise_exception=True)
        ClientNote.objects.create(
            client=client, author=request.user, text=data.validated_data["text"].strip()
        )
        return Response(_detail(client), status=201)


def _preview(client, action, data) -> dict:
    """The dates a button will change, as data (the app writes the sentence in its language)."""
    if action == "renew":
        return {"new_end": services.preview_months(client, data["plan"].months)}
    if action == "extend":
        return {"new_end": services.preview_days(client, data["days"])}
    if action == "correct":
        return {"new_end": data["new_end"]}
    return {}


class ClientActionView(OperatorView):
    """`step: review` checks the form and says what would happen, changing nothing. `step:
    confirm` does it. A password made by "reset-password" is in the answer once, never again."""

    def post(self, request, client_id, action):
        spec = ACTIONS.get(action)
        if spec is None:
            raise ApiError("not_found", "Unknown action", status_code=404)
        client = get_object_or_404(Client.objects.select_related("business", "plan"), pk=client_id)
        form = spec.form(request.data)
        if not form.is_valid():
            raise _form_errors(form)
        data = form.cleaned_data
        if request.data.get("step") != "confirm":
            return Response(
                {
                    "step": "review",
                    "lines": spec.describe(client, data),
                    "preview": _preview(client, action, data),
                    "old_end": client.paid_until,
                }
            )
        try:
            secret = spec.run(client, data, request.user)
        except services.BillingError as exc:
            raise ApiError("billing_error", str(exc), status_code=409) from exc
        return Response({"step": "done", "secret": secret, "client": _detail(client)})


# ---------------------------------------------------------------------------------------------
# Support desk


def _ticket_row(t) -> dict:
    return {
        "id": str(t.pk),
        "store_name": t.business.name,
        "subject": t.subject,
        "status": t.status,
        "asked_by": t.raised_by.full_name or t.raised_by.username,
        "screen": t.screen,
        "at": t.updated_at,
    }


class SupportListView(OperatorView):
    def get(self, request):
        wanted = request.query_params.get("status", "")
        rows = SupportRequest.objects.select_related("business", "raised_by")
        if wanted:
            rows = rows.filter(status=wanted)
        order = {"open": 0, "answered": 1, "closed": 2}
        tickets = sorted(
            rows[:MAX_ROWS], key=lambda t: (order[t.status], -t.updated_at.timestamp())
        )
        return Response({"results": [_ticket_row(t) for t in tickets]})


def _ticket_detail(ticket) -> dict:
    client = Client.objects.filter(business=ticket.business).first()
    return {
        **_ticket_row(ticket),
        "client_id": str(client.pk) if client else None,
        "app_version": ticket.app_version,
        "messages": [
            {
                "id": str(m.pk),
                "from_store": m.from_store,
                "by": m.author.full_name or m.author.username,
                "text": m.text,
                "at": m.created_at,
            }
            for m in ticket.messages.select_related("author")
        ],
    }


class ReplySerializer(serializers.Serializer):
    text = serializers.CharField(max_length=4000)
    close = serializers.BooleanField(required=False, default=False)


class SupportDetailView(OperatorView):
    def get(self, request, ticket_id):
        ticket = get_object_or_404(
            SupportRequest.objects.select_related("business", "raised_by"), pk=ticket_id
        )
        return Response(_ticket_detail(ticket))


class SupportReplyView(OperatorView):
    def post(self, request, ticket_id):
        data = ReplySerializer(data=request.data)
        data.is_valid(raise_exception=True)
        with transaction.atomic():
            ticket = get_object_or_404(
                SupportRequest.objects.select_for_update().select_related("business", "raised_by"),
                pk=ticket_id,
            )
            SupportMessage.objects.create(
                request=ticket,
                from_store=False,
                author=request.user,
                text=data.validated_data["text"].strip(),
            )
            ticket.status = (
                SupportRequest.Status.CLOSED
                if data.validated_data["close"]
                else SupportRequest.Status.ANSWERED
            )
            ticket.save(update_fields=["status", "updated_at"])
        return Response(_ticket_detail(ticket), status=201)


class SupportCloseView(OperatorView):
    def post(self, request, ticket_id):
        ticket = get_object_or_404(
            SupportRequest.objects.select_related("business", "raised_by"), pk=ticket_id
        )
        ticket.status = SupportRequest.Status.CLOSED
        ticket.save(update_fields=["status", "updated_at"])
        return Response(_ticket_detail(ticket))


# ---------------------------------------------------------------------------------------------
# Notices to every store, and the packages


class AnnouncementSerializer(serializers.ModelSerializer):
    class Meta:
        model = Announcement
        fields = ["id", "message_ru", "message_tk", "starts_at", "ends_at", "is_active"]
        extra_kwargs = {"starts_at": {"required": False}, "message_tk": {"required": False}}

    def validate(self, attrs):
        starts = attrs.get("starts_at") or getattr(self.instance, "starts_at", None)
        ends = attrs.get("ends_at") or getattr(self.instance, "ends_at", None)
        if starts and ends and ends <= starts:
            raise serializers.ValidationError({"ends_at": "The end must be after the start."})
        return attrs


class AnnouncementListView(OperatorView):
    def get(self, request):
        rows = Announcement.objects.all()[:100]
        return Response({"results": AnnouncementSerializer(rows, many=True).data})

    def post(self, request):
        data = AnnouncementSerializer(data=request.data)
        data.is_valid(raise_exception=True)
        item = data.save()
        audit.record("platform.announcement_created", actor=request.user, obj=item)
        return Response(AnnouncementSerializer(item).data, status=201)


class AnnouncementDetailView(OperatorView):
    def patch(self, request, announcement_id):
        item = get_object_or_404(Announcement, pk=announcement_id)
        data = AnnouncementSerializer(item, data=request.data, partial=True)
        data.is_valid(raise_exception=True)
        item = data.save()
        audit.record("platform.announcement_changed", actor=request.user, obj=item)
        return Response(AnnouncementSerializer(item).data)


class PlanUpdateSerializer(serializers.Serializer):
    price = serializers.DecimalField(
        max_digits=12, decimal_places=2, min_value=0, required=False, allow_null=True
    )
    is_active = serializers.BooleanField(required=False)


class PlanListView(OperatorView):
    def get(self, request):
        return Response({"results": [_plan(p) for p in Plan.objects.all()]})


class PlanDetailView(OperatorView):
    def patch(self, request, plan_id):
        plan = get_object_or_404(Plan, pk=plan_id)
        data = PlanUpdateSerializer(data=request.data)
        data.is_valid(raise_exception=True)
        fields = []
        for name, value in data.validated_data.items():
            setattr(plan, name, value)
            fields.append(name)
        if fields:
            plan.save(update_fields=[*fields, "updated_at"])
            audit.record("platform.plan_changed", actor=request.user, obj=plan)
        return Response(_plan(plan))
