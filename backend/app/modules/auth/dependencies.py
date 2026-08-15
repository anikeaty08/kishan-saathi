"""Authentication lifecycle dependencies."""

from typing import cast

from fastapi import Request

from app.integrations.auth.accounts import AccountAuthProvider


def get_account_auth_provider(request: Request) -> AccountAuthProvider:
    return cast(AccountAuthProvider, request.app.state.account_auth_provider)
