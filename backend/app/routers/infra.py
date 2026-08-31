import logging
from typing import Optional

import httpx
from fastapi import APIRouter, Depends, Header, HTTPException

from app import auth, models
from app.config import settings

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/infra", tags=["infra"])

_ERROR_CONTACTO = "No se pudo contactar el monitor de infraestructura"


def _base_url() -> str:
    return settings.monitor_auth_url.rstrip("/")


def _headers(x_infra_token: str = Header(..., alias="X-Infra-Token")) -> dict:
    return {
        "Authorization": f"Bearer {x_infra_token}",
        "Accept": "application/json",
        "Content-Type": "application/json",
    }


def _reenviar(
    metodo: str,
    path: str,
    headers: dict,
    params: Optional[dict] = None,
    json_body: Optional[dict] = None,
) -> dict:
    try:
        respuesta = httpx.request(
            metodo, f"{_base_url()}{path}", headers=headers, params=params, json=json_body, timeout=15
        )
    except Exception:
        # El detalle real (URL interna, timeout, etc.) queda en logs del
        # servidor; al cliente solo le llega un mensaje generico.
        logger.exception("Fallo al contactar el monitor de infraestructura en %s", path)
        raise HTTPException(status_code=502, detail=_ERROR_CONTACTO)
    try:
        return respuesta.json()
    except Exception:
        raise HTTPException(status_code=502, detail="Respuesta invalida del monitor de infraestructura")


def _reenviar_get(path: str, headers: dict, params: Optional[dict] = None) -> dict:
    return _reenviar("GET", path, headers, params=params)


def _reenviar_post(path: str, headers: dict, json_body: dict) -> dict:
    return _reenviar("POST", path, headers, json_body=json_body)


_dep_usuario = Depends(auth.obtener_usuario_actual)
# Acciones destructivas (abortar/cancelar sesiones de produccion) exigen
# admin, no solo estar logueado: cualquier usuario activo obtiene infra_token
# al hacer login, sin distincion de rol.
_dep_admin = Depends(auth.requerir_admin)
_dep_headers = Depends(_headers)


# ---- Netezza ----


@router.get("/netezza/sesiones/data")
def netezza_data(headers: dict = _dep_headers, usuario_actual: models.Usuario = _dep_usuario):
    return _reenviar_get("/netezza/sesiones/data", headers)


@router.post("/netezza/sesiones/abort-txn")
def netezza_abort_txn(
    payload: dict, headers: dict = _dep_headers, usuario_actual: models.Usuario = _dep_admin
):
    return _reenviar_post("/netezza/sesiones/abort-txn", headers, payload)


@router.get("/netezza/sesiones/alert-poll")
def netezza_alert_poll(headers: dict = _dep_headers, usuario_actual: models.Usuario = _dep_usuario):
    return _reenviar_get("/netezza/sesiones/alert-poll", headers)


# ---- PostgreSQL DEV (monpost) ----


@router.get("/monpost/data")
def monpost_data(
    active_only: str = "1", headers: dict = _dep_headers, usuario_actual: models.Usuario = _dep_usuario
):
    return _reenviar_get("/monpost/data", headers, params={"active_only": active_only})


@router.post("/monpost/cancel")
def monpost_cancel(payload: dict, headers: dict = _dep_headers, usuario_actual: models.Usuario = _dep_admin):
    return _reenviar_post("/monpost/cancel", headers, payload)


@router.get("/monpost/alert-poll")
def monpost_alert_poll(headers: dict = _dep_headers, usuario_actual: models.Usuario = _dep_usuario):
    return _reenviar_get("/monpost/alert-poll", headers)


@router.get("/monpost/disk-poll")
def monpost_disk_poll(headers: dict = _dep_headers, usuario_actual: models.Usuario = _dep_usuario):
    return _reenviar_get("/monpost/disk-poll", headers)


# ---- PostgreSQL PROD (postprod) ----


@router.get("/postprod/data")
def postprod_data(
    active_only: str = "1", headers: dict = _dep_headers, usuario_actual: models.Usuario = _dep_usuario
):
    return _reenviar_get("/postprod/data", headers, params={"active_only": active_only})


@router.post("/postprod/cancel")
def postprod_cancel(payload: dict, headers: dict = _dep_headers, usuario_actual: models.Usuario = _dep_admin):
    return _reenviar_post("/postprod/cancel", headers, payload)


@router.get("/postprod/alert-poll")
def postprod_alert_poll(headers: dict = _dep_headers, usuario_actual: models.Usuario = _dep_usuario):
    return _reenviar_get("/postprod/alert-poll", headers)


@router.get("/postprod/disk-poll")
def postprod_disk_poll(headers: dict = _dep_headers, usuario_actual: models.Usuario = _dep_usuario):
    return _reenviar_get("/postprod/disk-poll", headers)


@router.get("/postprod/historial-bloqueos")
def postprod_historial_bloqueos(
    limite: int = 300, headers: dict = _dep_headers, usuario_actual: models.Usuario = _dep_usuario
):
    return _reenviar_get("/postprod/historial-bloqueos", headers, params={"limite": limite})
