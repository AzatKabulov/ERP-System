"""The forms behind the console's buttons. Each one that changes a subscription is shown twice:
filled in, then as a plain sentence of what is about to happen, before anything is saved."""

from django import forms

from apps.accounts.models import USERNAME_VALIDATOR, User

from .models import Plan, SubscriptionEvent

METHODS = [("", "—"), *SubscriptionEvent.Method.choices]


class PaymentFields(forms.Form):
    amount = forms.DecimalField(
        required=False,
        min_value=0,
        decimal_places=2,
        max_digits=12,
        help_text="What the client paid, if anything. Leave empty if nothing was paid.",
    )
    currency = forms.CharField(required=False, max_length=3, initial="TMT")
    method = forms.ChoiceField(required=False, choices=METHODS, initial="cash")
    reference = forms.CharField(
        required=False,
        max_length=120,
        help_text='A receipt number or a short remark: "receipt 17".',
    )


class RenewForm(PaymentFields):
    plan = forms.ModelChoiceField(
        queryset=Plan.objects.none(),
        empty_label=None,
        help_text="Time is added after the current end date.",
    )
    note = forms.CharField(required=False, widget=forms.Textarea(attrs={"rows": 2}))

    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self.fields["plan"].queryset = Plan.objects.filter(is_active=True, months__isnull=False)
        self.order_fields(["plan", "amount", "currency", "method", "reference", "note"])


class ExtendForm(PaymentFields):
    days = forms.IntegerField(min_value=1, max_value=3650)
    note = forms.CharField(
        widget=forms.Textarea(attrs={"rows": 2}),
        help_text='Why: "will pay next week", "paid for 45 days". Required.',
    )
    field_order = ["days", "note", "amount", "currency", "method", "reference"]


class CorrectForm(forms.Form):
    new_end = forms.DateField(
        widget=forms.DateInput(attrs={"type": "date"}),
        help_text="The last day the store may use it.",
    )
    note = forms.CharField(
        widget=forms.Textarea(attrs={"rows": 2}), help_text="What was wrong. Required."
    )


class ReasonForm(forms.Form):
    note = forms.CharField(widget=forms.Textarea(attrs={"rows": 2}), help_text="Required.")


class OptionalReasonForm(forms.Form):
    note = forms.CharField(required=False, widget=forms.Textarea(attrs={"rows": 2}))


class ConfirmForm(forms.Form):
    pass


class NoteForm(forms.Form):
    text = forms.CharField(widget=forms.Textarea(attrs={"rows": 2}))


class ReplyForm(forms.Form):
    text = forms.CharField(widget=forms.Textarea(attrs={"rows": 4}))
    close = forms.BooleanField(required=False, label="Close the request after answering")


class NewClientForm(PaymentFields):
    store_name = forms.CharField(max_length=200)
    owner_name = forms.CharField(max_length=200, required=False)
    owner_login = forms.CharField(
        max_length=64,
        required=False,
        help_text="Leave empty to make one from the store name. The owner can't change it.",
    )
    owner_email = forms.EmailField(
        required=False, help_text="Optional. Needed only to email password codes."
    )
    phone = forms.CharField(max_length=60, required=False)
    language = forms.ChoiceField(choices=[("ru", "Русский"), ("tk", "Türkmençe")], initial="ru")
    start = forms.ModelChoiceField(
        queryset=Plan.objects.none(),
        required=False,
        empty_label="Free trial",
        help_text="A free trial, or a package the client has just paid for.",
    )
    note = forms.CharField(required=False, widget=forms.Textarea(attrs={"rows": 2}))

    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self.fields["start"].queryset = Plan.objects.filter(is_active=True, months__isnull=False)

    def clean_owner_login(self):
        value = self.cleaned_data["owner_login"].strip().lower()
        if not value:
            return value
        try:
            USERNAME_VALIDATOR(value)
        except Exception as exc:
            raise forms.ValidationError(
                "Use 3-64 lowercase letters, digits, dots, dashes or underscores."
            ) from exc
        if User.objects.filter(username=value).exists():
            raise forms.ValidationError("This login is taken.")
        return value
