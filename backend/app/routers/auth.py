import logging

from fastapi import APIRouter, Depends, HTTPException, Request
from fastapi.security import OAuth2PasswordRequestForm
from sqlalchemy.orm import Session

from app import auth, models, schemas
from app.database import get_db
from app.rate_limit import limiter
from app.services.fcm import enviar_alerta_push

logger = logging.getLogger(__name__)
router = APIRouter(prefix="/auth", tags=["auth"])


@router.post("/register", response_model=schemas.MensajeOut)
@limiter.limit("5/minute")
def registrar(request: Request, usuario_in: schemas.UsuarioCreate, db: Session = Depends(get_db)):
    """No crea la cuenta directo (eso dejaba entrar a cualquiera sin ningun
    control): queda como solicitud pendiente, igual que el acceso via Google,
    hasta que un administrador la apruebe desde /admin/solicitudes-registro."""

    existente_usuario = (
        db.query(models.Usuario).filter(models.Usuario.username == usuario_in.username).first()
    )
    if existente_usuario:
        raise HTTPException(status_code=400, detail="El usuario ya esta registrado")

    existente_solicitud = (
        db.query(models.SolicitudRegistro)
        .filter(
            models.SolicitudRegistro.username == usuario_in.username,
            models.SolicitudRegistro.estado == "pendiente",
        )
        .first()
    )
    if existente_solicitud:
        raise HTTPException(status_code=400, detail="Ya existe una solicitud pendiente para ese usuario")

    solicitud = models.SolicitudRegistro(
        username=usuario_in.username,
        email=usuario_in.email,
        nombre=usuario_in.nombre,
        password_hash=auth.hashear_password(usuario_in.password),
    )
    db.add(solicitud)
    db.commit()
    return schemas.MensajeOut(
        ok=True,
        mensaje="Tu solicitud fue enviada. Un administrador debe aprobarla antes de que puedas ingresar.",
    )


@router.post("/login", response_model=schemas.Token)
@limiter.limit("10/minute")
def login(request: Request, form_data: OAuth2PasswordRequestForm = Depends(), db: Session = Depends(get_db)):
    usuario, infra_token = auth.autenticar_usuario(form_data.username, form_data.password, db)
    if not usuario:
        cuenta = auth.buscar_usuario_por_identificador(form_data.username, db)
        if cuenta is not None and cuenta.activo and not cuenta.password_hash:
            raise HTTPException(
                status_code=401,
                detail={
                    "codigo": "sin_password",
                    "mensaje": (
                        "Tu cuenta todavia no tiene una contrasena configurada para la app. "
                        "Usa 'Olvide mi contrasena' e ingresa tu contrasena habitual (AD) para crearla."
                    ),
                },
            )
        raise HTTPException(status_code=401, detail="Usuario o contrasena incorrectos")

    access_token = auth.crear_access_token(data={"sub": usuario.username})
    refresh_token = auth.crear_refresh_token(usuario.username)
    # infra_token ya viene del mismo intento contra el monitor que valido la
    # password (ver auth.autenticar_usuario): si el usuario se autentico por
    # el fallback local (password_hash propio, sin pasar por el monitor),
    # infra_token queda en None -no hay sesion de monitor equivalente.
    return schemas.Token(access_token=access_token, refresh_token=refresh_token, infra_token=infra_token)


@router.post("/configurar-password", response_model=schemas.Token)
@limiter.limit("5/minute")
def configurar_password(request: Request, payload: schemas.ConfigurarPasswordIn, db: Session = Depends(get_db)):
    usuario = auth.configurar_password_local(
        payload.username,
        payload.password_actual,
        payload.correo_verificacion,
        payload.password_nueva,
        db,
    )
    if not usuario:
        raise HTTPException(status_code=401, detail="Usuario o contrasena actual incorrectos")

    access_token = auth.crear_access_token(data={"sub": usuario.username})
    refresh_token = auth.crear_refresh_token(usuario.username)
    return schemas.Token(access_token=access_token, refresh_token=refresh_token)


@router.post("/login/google", response_model=schemas.Token)
@limiter.limit("10/minute")
def login_con_google(request: Request, payload: schemas.GoogleLoginIn, db: Session = Depends(get_db)):
    try:
        usuario = auth.autenticar_con_google(payload.id_token, db)
    except auth.AccesoGoogleNoConcedido as exc:
        raise HTTPException(status_code=403, detail=exc.mensaje)

    if not usuario:
        raise HTTPException(status_code=401, detail="Token de Google invalido")

    access_token = auth.crear_access_token(data={"sub": usuario.username})
    refresh_token = auth.crear_refresh_token(usuario.username)
    return schemas.Token(access_token=access_token, refresh_token=refresh_token)


@router.post("/refresh", response_model=schemas.Token)
@limiter.limit("20/minute")
def refrescar_token(request: Request, payload: schemas.RefreshIn, db: Session = Depends(get_db)):
    """Cambia un refresh_token todavia valido por un access_token nuevo, sin
    pedir credenciales de nuevo. Tambien rota el refresh_token (ventana
    deslizante): mientras el usuario abra la app dentro de los 30 dias, la
    sesion nunca vence de verdad."""

    usuario = auth.verificar_refresh_token(payload.refresh_token, db)
    if usuario is None:
        raise HTTPException(status_code=401, detail="Sesion vencida, volve a iniciar sesion")

    access_token = auth.crear_access_token(data={"sub": usuario.username})
    nuevo_refresh_token = auth.crear_refresh_token(usuario.username)
    return schemas.Token(access_token=access_token, refresh_token=nuevo_refresh_token)


@router.post("/vincular-google", response_model=schemas.UsuarioOut)
def vincular_google(
    payload: schemas.VincularGoogleIn,
    usuario_actual: models.Usuario = Depends(auth.obtener_usuario_actual),
    db: Session = Depends(get_db),
):
    try:
        usuario = auth.vincular_cuenta_google(usuario_actual, payload.id_token, db)
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc))
    return usuario


@router.post("/desvincular-google", response_model=schemas.UsuarioOut)
def desvincular_google(
    usuario_actual: models.Usuario = Depends(auth.obtener_usuario_actual),
    db: Session = Depends(get_db),
):
    usuario_actual.email_google = None
    db.commit()
    db.refresh(usuario_actual)
    return usuario_actual


@router.get("/me", response_model=schemas.UsuarioOut)
def obtener_perfil(
    usuario_actual: models.Usuario = Depends(auth.obtener_usuario_actual),
    db: Session = Depends(get_db),
):
    return schemas.UsuarioOut(
        id=usuario_actual.id,
        username=usuario_actual.username,
        nombre=usuario_actual.nombre,
        email=usuario_actual.email,
        email_google=usuario_actual.email_google,
        activo=usuario_actual.activo,
        es_admin=auth.es_administrador(usuario_actual, db),
    )


@router.post("/me/fcm-token")
def guardar_fcm_token(
    payload: schemas.FcmTokenIn,
    usuario_actual: models.Usuario = Depends(auth.obtener_usuario_actual),
    db: Session = Depends(get_db),
):
    fila = db.query(models.UsuarioFcmToken).filter(models.UsuarioFcmToken.usuario_id == usuario_actual.id).first()
    if fila:
        fila.fcm_token = payload.fcm_token
    else:
        fila = models.UsuarioFcmToken(usuario_id=usuario_actual.id, fcm_token=payload.fcm_token)
        db.add(fila)
    db.commit()
    return {"ok": True}


@router.delete("/me/fcm-token")
def eliminar_fcm_token(
    usuario_actual: models.Usuario = Depends(auth.obtener_usuario_actual),
    db: Session = Depends(get_db),
):
    """Usado cuando el usuario desactiva las notificaciones desde Ajustes: se
    borra el token para que el poller ni intente mandarle push a este
    dispositivo (no alcanza con ignorarlo del lado del cliente)."""

    db.query(models.UsuarioFcmToken).filter(
        models.UsuarioFcmToken.usuario_id == usuario_actual.id
    ).delete()
    db.commit()
    return {"ok": True}


@router.post("/me/probar-alerta")
def probar_alerta(
    usuario_actual: models.Usuario = Depends(auth.obtener_usuario_actual),
    db: Session = Depends(get_db),
):
    """Manda una push de prueba al token FCM de este dispositivo, sin esperar
    a que falle un proceso real. A diferencia del poller, no traga la
    excepcion: si algo esta mal (credenciales, token invalido, etc.) el
    detalle real se lo devuelve a la app en vez de quedar solo en logs."""

    fila = (
        db.query(models.UsuarioFcmToken)
        .filter(models.UsuarioFcmToken.usuario_id == usuario_actual.id)
        .first()
    )
    if fila is None:
        raise HTTPException(
            status_code=400,
            detail="Este dispositivo todavia no registro un token de notificaciones "
            "(abri la app y volve a intentar en un rato).",
        )

    try:
        message_id = enviar_alerta_push(
            fila.fcm_token,
            titulo="Prueba de alarma",
            cuerpo="Si escuchaste esto, la alerta critica esta funcionando.",
            critica=True,
        )
    except Exception:
        logger.exception("Fallo al enviar push de prueba a usuario %s", usuario_actual.username)
        raise HTTPException(status_code=502, detail="No se pudo enviar el push de prueba")

    return {"ok": True, "message_id": message_id}
