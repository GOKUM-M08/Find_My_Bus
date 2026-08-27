"""
Authentication helpers.

NOTE: the guide's folder structure lists this file ("# Authentication")
but the walkthrough's actual auth flow is Supabase Phone OTP handled
entirely on the Flutter client (see lib/screens/login_screen.dart) —
the FastAPI backend never verifies a token in any of the guide's
endpoints. This stub shows how you'd verify a Supabase-issued JWT on
protected backend routes if you add that later.
"""
import os
from jose import jwt, JWTError
from fastapi import Header, HTTPException

SECRET_KEY = os.getenv("SECRET_KEY", "")


def verify_supabase_token(authorization: str = Header(None)):
    """
    Example dependency for protecting a route:

        @router.get("/protected")
        def protected_route(user=Depends(verify_supabase_token)):
            ...

    Not wired into any route in this guide — added as a starting
    point since none of the FastAPI endpoints here currently check
    who's calling them.
    """
    if not authorization or not authorization.startswith("Bearer "):
        raise HTTPException(status_code=401, detail="Missing auth token")

    token = authorization.split(" ")[1]
    try:
        payload = jwt.decode(token, SECRET_KEY, algorithms=["HS256"],
                              options={"verify_aud": False})
        return payload
    except JWTError:
        raise HTTPException(status_code=401, detail="Invalid or expired token")
