"""The owner console: our own back office, on its own address, for the people who run this
system (never for a store). It is a separate admin site that shows only the platform tables:
clients and their subscriptions, support requests, announcements, packages. A store's sales,
customers and stock are not registered here, so they cannot be browsed from it.

Signing in needs the operator's password and a code from their authenticator app."""

from dataclasses import dataclass
from datetime import timedelta
from typing import Any

from django import forms
from django.contrib import admin, messages
from django.core.cache import cache
from django.db.models import Count, Max, OuterRef, Subquery
from django.shortcuts import get_object_or_404, redirect
from django.template.response import TemplateResponse
from django.urls import path, reverse
from django.utils import timezone
from django.utils.html import format_html
from django_otp import devices_for_user
from django_otp.admin import OTPAdminAuthenticationForm, OTPAdminSite

from apps.businesses.models import Membership, Role
from apps.sales.models import Sale

from . import dashboard, services
from . import forms as console_forms
from .models import (
    Announcement,
    Client,
    ClientNote,
    Plan,
    SubscriptionEvent,
    SupportMessage,
    SupportRequest,
)
from .status import (
    ACTIVE,
    EXPIRING,
    FREE,
    GRACE,
    READ_ONLY,
    SUSPENDED,
    status_for,
)

LOGIN_TRIES_PER_MINUTE = 8

_STATE_LOOK = {
    ACTIVE: ("#1a7f4b", "Active"),
    EXPIRING: ("#b26a00", "Ending soon"),
    GRACE: ("#c0392b", "Grace days"),
    READ_ONLY: ("#7a1f1f", "Read-only"),
    SUSPENDED: ("#555", "Suspended"),
    FREE: ("#1740ff", "Free access"),
}


def state_badge(client: Client, now=None):
    status = status_for(client, client.business, now)
    colour, label = _STATE_LOOK[status.state]
    if status.is_trial and status.state in (ACTIVE, EXPIRING):
        label = f"Trial · {label.lower()}"
    left = ""
    if status.days_left is not None and status.state not in (FREE, SUSPENDED):
        left = (
            f" · {status.days_left} d"
            if status.days_left >= 0
            else f" · ended {-status.days_left} d ago"
        )
    return format_html(
        '<b style="color:#fff;background:{};padding:2px 8px;border-radius:10px;'
        'white-space:nowrap">{}{}</b>',
        colour,
        label,
        left,
    )


class ConsoleLoginForm(OTPAdminAuthenticationForm):
    """The password step, then the code from the operator's authenticator app.

    The library makes a person choose which device the code is from, so the first try with a
    right password always failed with "Please select a device". An operator has one
    authenticator: use it without asking. The code is still checked against a device that belongs
    to this person only, with the library's own lock-out after repeated wrong codes."""

    def _chosen_device(self, user):
        device = super()._chosen_device(user)
        if device is None:
            own = list(devices_for_user(user))
            if len(own) == 1:
                device = own[0]
        return device


class ConsoleSite(OTPAdminSite):
    login_form = ConsoleLoginForm
    site_header = "Owner console"
    site_title = "Owner console"
    index_title = "Clients and subscriptions"
    index_template = "console/index.html"

    def login(self, request, extra_context=None):
        """A few tries a minute per address: the password and the code are both needed, but
        guessing them should still be slow."""
        if request.method == "POST":
            forwarded = request.META.get("HTTP_X_FORWARDED_FOR", "").split(",")[-1].strip()
            key = f"console-login:{forwarded or request.META.get('REMOTE_ADDR', '')}"
            cache.add(key, 0, 60)
            if cache.incr(key) > LOGIN_TRIES_PER_MINUTE:
                return TemplateResponse(
                    request,
                    "console/too_many.html",
                    {**self.each_context(request), "title": "Too many attempts"},
                    status=429,
                )
        return super().login(request, extra_context)

    def index(self, request, extra_context=None):
        extra = {"snapshot": dashboard.snapshot(), "look": _STATE_LOOK, **(extra_context or {})}
        return super().index(request, extra)


console_site = ConsoleSite(name="console")


# ----------------------------------------------------------------------------------------------
# What each button does. One table: the form it shows, the sentence of what is about to happen,
# and the service call that does it.


@dataclass(frozen=True)
class Action:
    title: str
    form: type[forms.Form]
    describe: Any  # (client, data) -> list[str]
    run: Any  # (client, data, actor) -> str | None   (a secret to show once, or None)
    danger: bool = False
    button: str = "Confirm"


def _fmt(moment) -> str:
    return (
        moment.astimezone(timezone.get_current_timezone()).strftime("%d %b %Y") if moment else "—"
    )


def _payment(data) -> dict:
    return {
        "amount": data.get("amount"),
        "currency": data.get("currency", ""),
        "method": data.get("method", ""),
        "reference": data.get("reference", ""),
    }


def _money(data, plan=None) -> str:
    amount = data.get("amount") if data.get("amount") is not None else getattr(plan, "price", None)
    if amount is None:
        return "No payment will be recorded."
    currency = data.get("currency") or getattr(plan, "currency", "")
    return f"Payment recorded: {amount} {currency} {data.get('method') or ''}".strip() + "."


def _end(date) -> str:
    return date.strftime("%d %b %Y")


def describe_renew(client, data):
    plan = data["plan"]
    new = services.preview_months(client, plan.months)
    return [
        f"Add {plan.name} to {client.business.name}.",
        f"Now ends: {_fmt(client.paid_until)} → will end: {_end(new)}.",
        _money(data, plan),
    ]


def run_renew(client, data, actor):
    plan = data["plan"]
    payment = _payment(data)
    if payment["amount"] is None:  # the package's own price unless the operator typed another
        payment.pop("amount")
        payment.pop("currency")
    services.renew(client, plan, actor, note=data["note"], **payment)


def describe_extend(client, data):
    new = services.preview_days(client, data["days"])
    return [
        f"Add {data['days']} days to {client.business.name}: {data['note']}",
        f"Now ends: {_fmt(client.paid_until)} → will end: {_end(new)}.",
        _money(data),
    ]


def run_extend(client, data, actor):
    services.extend_days(client, data["days"], actor, note=data["note"], **_payment(data))


def describe_correct(client, data):
    return [
        f"Set the end date of {client.business.name} to {_end(data['new_end'])}.",
        f"It was {_fmt(client.paid_until)}. This is for fixing a mistake.",
    ]


def run_correct(client, data, actor):
    services.correct_end(client, data["new_end"], actor, note=data["note"])


ACTIONS: dict[str, Action] = {
    "renew": Action("Add a package", console_forms.RenewForm, describe_renew, run_renew),
    "extend": Action("Add custom days", console_forms.ExtendForm, describe_extend, run_extend),
    "correct": Action(
        "Correct the end date",
        console_forms.CorrectForm,
        describe_correct,
        run_correct,
        danger=True,
    ),
    "suspend": Action(
        "Suspend",
        console_forms.ReasonForm,
        lambda c, d: [
            f"{c.business.name} will be cut off immediately: nobody there can open anything.",
            f"Paid time is kept. Reason: {d['note']}",
        ],
        lambda c, d, a: services.suspend(c, a, note=d["note"]) and None,
        danger=True,
        button="Suspend now",
    ),
    "resume": Action(
        "Resume",
        console_forms.OptionalReasonForm,
        lambda c, d: [f"{c.business.name} goes back to its normal subscription state."],
        lambda c, d, a: services.resume(c, a, note=d["note"]) and None,
    ),
    "free-on": Action(
        "Give free access",
        console_forms.ReasonForm,
        lambda c, d: [
            f"{c.business.name} will never expire, whatever was paid. Reason: {d['note']}"
        ],
        lambda c, d, a: services.set_free(c, True, a, note=d["note"]) and None,
    ),
    "free-off": Action(
        "End free access",
        console_forms.ReasonForm,
        lambda c, d: [
            f"{c.business.name} returns to its paid time (ends {_fmt(c.paid_until)}). "
            f"Reason: {d['note']}"
        ],
        lambda c, d, a: services.set_free(c, False, a, note=d["note"]) and None,
    ),
    "reset-password": Action(
        "Reset the owner's password",
        console_forms.ConfirmForm,
        lambda c, d: [
            f"A new temporary password will be made for the owner of {c.business.name}.",
            "Everyone signed in as the owner is signed out. You will see the password once.",
        ],
        lambda c, d, a: services.reset_owner_password(c, a),
        danger=True,
        button="Reset password",
    ),
}


# ----------------------------------------------------------------------------------------------


class StateFilter(admin.SimpleListFilter):
    title = "state"
    parameter_name = "state"

    def lookups(self, request, model_admin):
        return [
            ("attention", "Needs attention"),
            (ACTIVE, "Active"),
            (EXPIRING, "Ending soon"),
            (GRACE, "In grace days"),
            (READ_ONLY, "Read-only"),
            (SUSPENDED, "Suspended"),
            (FREE, "Free access"),
            ("trial", "On free trial"),
        ]

    def queryset(self, request, queryset):
        wanted = self.value()
        if not wanted:
            return queryset
        now = timezone.now()
        ids = []
        for client in queryset.select_related("business"):
            status = status_for(client, client.business, now)
            if (
                (wanted == "attention" and status.state in dashboard.ATTENTION)
                or (wanted == "trial" and status.is_trial and status.state in (ACTIVE, EXPIRING))
                or wanted == status.state
            ):
                ids.append(client.pk)
        return queryset.filter(pk__in=ids)


@admin.register(Client, site=console_site)
class ClientAdmin(admin.ModelAdmin):
    list_display = (
        "store",
        "state",
        "plan",
        "ends",
        "last_payment",
        "last_sign_in",
        "sales_30d",
        "who",
    )
    list_filter = (StateFilter,)
    search_fields = ("business__name", "contact_name", "contact_phone", "contact_email")
    list_select_related = ("business", "plan")
    ordering = ("paid_until",)
    list_per_page = 50

    def has_delete_permission(self, request, obj=None):
        return False

    def get_queryset(self, request):
        last_payment = (
            SubscriptionEvent.objects.filter(client=OuterRef("pk"), amount__isnull=False)
            .order_by("-created_at")
            .values("created_at")[:1]
        )
        sales = (
            Sale.objects.filter(
                business=OuterRef("business"), created_at__gte=timezone.now() - timedelta(days=30)
            )
            .values("business")
            .annotate(n=Count("id"))
            .values("n")
        )
        return (
            super()
            .get_queryset(request)
            .annotate(
                _last_payment=Subquery(last_payment),
                _sales=Subquery(sales),
                _last_sign_in=Max("business__memberships__user__last_login"),
            )
        )

    @admin.display(description="Store", ordering="business__name")
    def store(self, obj):
        return format_html(
            '<a href="{}"><b>{}</b></a>',
            reverse("console:billing_client_change", args=[obj.pk]),
            obj.business.name,
        )

    @admin.display(description="State", ordering="paid_until")
    def state(self, obj):
        return state_badge(obj)

    @admin.display(description="Ends", ordering="paid_until")
    def ends(self, obj):
        return _fmt(obj.paid_until)

    @admin.display(description="Last payment", ordering="_last_payment")
    def last_payment(self, obj):
        return _fmt(obj._last_payment)

    @admin.display(description="Last sign-in", ordering="_last_sign_in")
    def last_sign_in(self, obj):
        return _fmt(obj._last_sign_in)

    @admin.display(description="Sales (30 d)", ordering="_sales")
    def sales_30d(self, obj):
        return obj._sales or 0

    @admin.display(description="Contact")
    def who(self, obj):
        return " · ".join(x for x in (obj.contact_name, obj.contact_phone) if x) or "—"

    # -- pages -------------------------------------------------------------------------------

    def get_urls(self):
        wrap = self.admin_site.admin_view
        return [
            path(
                "<uuid:pk>/do/<slug:action>/",
                wrap(self.action_view),
                name="billing_client_action",
            ),
            *super().get_urls(),
        ]

    def add_view(self, request, form_url="", extra_context=None):
        form = console_forms.NewClientForm(request.POST or None)
        if request.method == "POST" and form.is_valid():
            data = form.cleaned_data
            try:
                client, password = services.provision_client(
                    store_name=data["store_name"],
                    owner_username=data["owner_login"]
                    or services.suggest_login(data["store_name"]),
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
                form.add_error(None, str(exc))
            else:
                owner = Membership.objects.get(business=client.business, role=Role.OWNER).user
                return TemplateResponse(
                    request,
                    "console/client_created.html",
                    {
                        **self.admin_site.each_context(request),
                        "title": "Client created",
                        "client": client,
                        "login": owner.username,
                        "password": password,
                        "app_url": request.build_absolute_uri("/"),
                    },
                )
        return TemplateResponse(
            request,
            "console/new_client.html",
            {**self.admin_site.each_context(request), "title": "New client", "form": form},
        )

    def change_view(self, request, object_id, form_url="", extra_context=None):
        client = get_object_or_404(Client.objects.select_related("business", "plan"), pk=object_id)
        contact = _ContactForm(request.POST or None, instance=client, prefix="contact")
        note = console_forms.NoteForm(request.POST or None, prefix="note")
        if request.method == "POST":
            which = request.POST.get("which")
            if which == "contact" and contact.is_valid():
                contact.save()
                messages.success(request, "Contact details saved.")
                return redirect(request.path)
            if which == "note" and note.is_valid():
                ClientNote.objects.create(
                    client=client, author=request.user, text=note.cleaned_data["text"].strip()
                )
                messages.success(request, "Note added.")
                return redirect(request.path)
        now = timezone.now()
        stats = dashboard.usage([client.business_id], now)[client.business_id]
        staff = (
            Membership.objects.filter(business=client.business)
            .select_related("user")
            .order_by("role", "user__username")
        )
        context = {
            **self.admin_site.each_context(request),
            "title": client.business.name,
            "client": client,
            "badge": state_badge(client, now),
            "status": status_for(client, client.business, now),
            "contact_form": contact,
            "note_form": note,
            "events": client.events.select_related("actor", "plan")[:40],
            "notes": client.notes.select_related("author")[:40],
            "requests": SupportRequest.objects.filter(business=client.business)[:10],
            "staff": staff,
            "stats": stats,
            "actions": [(key, spec) for key, spec in ACTIONS.items()],
            "suspended": client.override == Client.Override.SUSPENDED,
            "free": client.override == Client.Override.FREE,
        }
        return TemplateResponse(request, "console/client_detail.html", context)

    def action_view(self, request, pk, action):
        if action not in ACTIONS:
            return redirect("console:billing_client_changelist")
        client = get_object_or_404(Client.objects.select_related("business", "plan"), pk=pk)
        spec = ACTIONS[action]
        form = spec.form(request.POST or None)
        context = {
            **self.admin_site.each_context(request),
            "title": f"{spec.title}: {client.business.name}",
            "client": client,
            "spec": spec,
            "action": action,
        }
        if request.method == "POST" and form.is_valid():
            if request.POST.get("step") == "confirm":
                try:
                    secret = spec.run(client, form.cleaned_data, request.user)
                except services.BillingError as exc:
                    form.add_error(None, str(exc))
                else:
                    if secret:
                        return TemplateResponse(
                            request,
                            "console/secret.html",
                            {**context, "secret": secret, "title": spec.title},
                        )
                    messages.success(request, f"Done: {spec.title.lower()}.")
                    return redirect("console:billing_client_change", client.pk)
            else:
                try:
                    lines = spec.describe(client, form.cleaned_data)
                except Exception as exc:  # a preview must never crash the page
                    form.add_error(None, f"Cannot preview: {exc}")
                else:
                    return TemplateResponse(
                        request, "console/review.html", {**context, "form": form, "lines": lines}
                    )
        return TemplateResponse(request, "console/action.html", {**context, "form": form})


class _ContactForm(forms.ModelForm):
    class Meta:
        model = Client
        fields = ["contact_name", "contact_phone", "contact_email"]


@admin.register(SupportRequest, site=console_site)
class SupportRequestAdmin(admin.ModelAdmin):
    list_display = ("subject", "store", "state", "asked_by", "updated_at", "screen")
    list_filter = ("status",)
    search_fields = ("subject", "business__name")
    list_select_related = ("business", "raised_by")
    ordering = ("status", "-updated_at")

    def has_add_permission(self, request):
        return False

    def has_delete_permission(self, request, obj=None):
        return False

    @admin.display(description="Store", ordering="business__name")
    def store(self, obj):
        return obj.business.name

    @admin.display(description="State", ordering="status")
    def state(self, obj):
        colour = {"open": "#c0392b", "answered": "#1a7f4b", "closed": "#777"}[obj.status]
        return format_html('<b style="color:{}">{}</b>', colour, obj.get_status_display())

    @admin.display(description="Asked by")
    def asked_by(self, obj):
        return obj.raised_by.get_full_name()

    def change_view(self, request, object_id, form_url="", extra_context=None):
        ticket = get_object_or_404(
            SupportRequest.objects.select_related("business", "raised_by"), pk=object_id
        )
        form = console_forms.ReplyForm(request.POST or None)
        if request.method == "POST" and form.is_valid():
            SupportMessage.objects.create(
                request=ticket,
                from_store=False,
                author=request.user,
                text=form.cleaned_data["text"].strip(),
            )
            ticket.status = (
                SupportRequest.Status.CLOSED
                if form.cleaned_data["close"]
                else SupportRequest.Status.ANSWERED
            )
            ticket.save(update_fields=["status", "updated_at"])
            messages.success(request, "Reply sent.")
            return redirect("console:billing_supportrequest_changelist")
        if request.method == "POST" and request.POST.get("which") == "close":
            ticket.status = SupportRequest.Status.CLOSED
            ticket.save(update_fields=["status", "updated_at"])
            return redirect("console:billing_supportrequest_changelist")
        client = Client.objects.filter(business=ticket.business).first()
        return TemplateResponse(
            request,
            "console/support_detail.html",
            {
                **self.admin_site.each_context(request),
                "title": ticket.subject,
                "ticket": ticket,
                "client": client,
                "messages_list": ticket.messages.select_related("author"),
                "form": form,
            },
        )


@admin.register(Plan, site=console_site)
class PlanAdmin(admin.ModelAdmin):
    list_display = ("name", "code", "months", "price", "currency", "is_active")
    list_editable = ("price", "is_active")
    readonly_fields = ("code", "months")

    def has_delete_permission(self, request, obj=None):
        return False

    def has_add_permission(self, request):
        return False


@admin.register(Announcement, site=console_site)
class AnnouncementAdmin(admin.ModelAdmin):
    list_display = ("message_ru", "starts_at", "ends_at", "is_active")
    list_editable = ("is_active",)


@admin.register(SubscriptionEvent, site=console_site)
class HistoryAdmin(admin.ModelAdmin):
    """Every payment and every change, across all clients. Read-only: history is never edited."""

    list_display = (
        "created_at",
        "client",
        "kind",
        "amount",
        "currency",
        "method",
        "reference",
        "actor",
    )
    list_filter = ("kind", "method", "currency")
    search_fields = ("client__business__name", "reference", "note")
    list_select_related = ("client__business", "actor")
    date_hierarchy = "created_at"

    def has_add_permission(self, request):
        return False

    def has_change_permission(self, request, obj=None):
        return False

    def has_delete_permission(self, request, obj=None):
        return False
