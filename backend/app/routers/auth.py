from fastapi import APIRouter, Depends, HTTPException
from fastapi.security import OAuth2PasswordRequestForm
from sqlalchemy.orm import Session

from app import auth, models, schemas
from app.database import get_db
from app.services.fcm import enviar_alerta_push

router = APIRouter(prefix="/auth", tags=["auth"])


@router.post("/register", response_model=schemas.UsuarioOut)
def registrar(usuario_in: schemas.UsuarioCreate, db: Session = Depends(get_db)):
    existente = db.query(models.Usuario).filter(models.Usuario.username == usuario_in.username).first()
    if existente:
        raise HTTPException(status_code=400, detail="El usuario ya esta registrado")

    usuario = models.Usuario(
        username=usuario_in.username,
        email=usuario_in.email,
        password_hash=auth.hashear_password(usuario_in.password),
        nombre=usuario_in.nombre,
        activo=True,
    )
    db.add(usuario)
    db.commit()
    db.refresh(usuario)
    return usuario


@router.post("/login", response_model=schemas.Token)
def login(form_data: OAuth2PasswordRequestForm = Depends(), db: Session = Depends(get_db)):
    usuario = auth.autenticar_usuario(form_data.username, form_data.password, db)
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
    # Token del monitor OP (Netezza/Postgres): mismo AD, se pide aparte para no
    # atar el login de la app a que el modulo de infraestructura este disponible.
    infra_token = auth.autenticar_contra_monitor(form_data.username, form_data.password)
    return schemas.Token(access_token=access_token, infra_token=infra_token)


@router.post("/configurar-password", response_model=schemas.Token)
def configurar_password(payload: schemas.ConfigurarPasswordIn, db: Session = Depends(get_db)):
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
    return schemas.Token(access_token=access_token)


@router.post("/login/google", response_model=schemas.Token)
def login_con_google(payload: schemas.GoogleLoginIn, db: Session = Depends(get_db)):
    try:
        usuario = auth.autenticar_con_google(payload.id_token, db)
    except auth.AccesoGoogleNoConcedido as exc:
        raise HTTPException(status_code=403, detail=exc.mensaje)

    if not usuario:
        raise HTTPException(status_code=401, detail="Token de Google invalido")

    access_token = auth.crear_access_token(data={"sub": usuario.username})
    return schemas.Token(access_token=access_token)


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
    except Exception as exc:
        raise HTTPException(status_code=502, detail=f"No se pudo enviar el push: {exc}")

    return {"ok": True, "message_id": message_id}
