"""Recovery emails in the user's language. Turkmen wording is provisional and needs
review by a fluent speaker (PLAN.md D14)."""

from django.conf import settings
from django.core.mail import send_mail

_TEXT = {
    "ru": {
        "reset": (
            "Код восстановления пароля",
            "Здравствуйте, {name}!\n\n"
            "Ваш одноразовый код для восстановления пароля: {code}\n"
            "Код действует {minutes} минут и подходит только для одного использования.\n\n"
            "Если вы не запрашивали восстановление, просто проигнорируйте это письмо.",
        ),
        "welcome": (
            "Ваш аккаунт создан",
            "Здравствуйте, {name}!\n\n"
            "Для вас создан аккаунт в системе «{business}». Логин: {username}\n"
            "Чтобы задать пароль, откройте приложение, выберите «Забыли пароль?» "
            "и введите этот одноразовый код: {code}\n"
            "Код действует {minutes} минут.",
        ),
    },
    "tk": {
        "reset": (
            "Paroly dikeltmek kody",
            "Salam, {name}!\n\n"
            "Parolyňyzy dikeltmek üçin bir gezeklik kodyňyz: {code}\n"
            "Kod {minutes} minut dowamynda dogry bolup, diňe bir gezek ulanylýar.\n\n"
            "Eger siz dikeltmegi soramadyk bolsaňyz, bu haty äsgermezlik ediň.",
        ),
        "welcome": (
            "Hasabyňyz döredildi",
            "Salam, {name}!\n\n"
            "«{business}» ulgamynda siziň üçin hasap döredildi. Login: {username}\n"
            "Paroly bellemek üçin programmany açyň, «Paroly ýatdan çykardyňyzmy?» saýlaň "
            "we şu bir gezeklik kody giriziň: {code}\n"
            "Kod {minutes} minut dowamynda dogry bolýar.",
        ),
    },
}


def send_code_email(user, kind: str, code: str, minutes: int, business_name: str = "") -> None:
    language = user.preferred_language if user.preferred_language in _TEXT else "ru"
    subject, body = _TEXT[language][kind]
    send_mail(
        subject,
        body.format(
            name=user.get_full_name(),
            code=code,
            minutes=minutes,
            username=user.username,
            business=business_name,
        ),
        settings.DEFAULT_FROM_EMAIL,
        [user.email],
        fail_silently=False,
    )
