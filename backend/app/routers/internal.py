from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from app import auth, schemas
from app.database import get_db
from app.services.solicitudes import aprobar_solicitud_registro

router = APIRouter(prefix="/internal", tags=["internal"])


@router.post(
    "/solicitudes-registro/{solicitud_id}/aprobar",
    response_model=schemas.UsuarioOut,
    dependencies=[Depends(auth.verificar_internal_key)],
)
def aprobar_solicitud_registro_interno(solicitud_id: int, db: Session = Depends(get_db)):
    """Igual que /admin/solicitudes-registro/{id}/aprobar, pero pensado para
    que lo llame el backend de op_prod (server-a-server, con clave interna en
    vez de un JWT de admin humano) cuando resuelve la solicitud reflejada en
    su propio panel de Usuarios."""
    return aprobar_solicitud_registro(db, solicitud_id)
