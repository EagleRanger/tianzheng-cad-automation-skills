"""Shared errors; no CAD side effects."""


class ClientError(ValueError):
    pass


def check(ok, message):
    if not ok:
        raise ClientError(message)

