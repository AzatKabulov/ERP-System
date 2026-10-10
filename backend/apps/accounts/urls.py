from django.urls import path

from . import views

urlpatterns = [
    path("auth/login/", views.LoginView.as_view(), name="auth-login"),
    path("auth/refresh/", views.RefreshView.as_view(), name="auth-refresh"),
    path("auth/logout/", views.LogoutView.as_view(), name="auth-logout"),
    path("auth/password/change/", views.PasswordChangeView.as_view(), name="auth-password-change"),
    path(
        "auth/password/reset/request/",
        views.PasswordResetRequestView.as_view(),
        name="auth-reset-request",
    ),
    path(
        "auth/password/reset/confirm/",
        views.PasswordResetConfirmView.as_view(),
        name="auth-reset-confirm",
    ),
]
