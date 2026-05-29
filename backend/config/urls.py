from django.contrib import admin
from django.urls import include, path

urlpatterns = [
    path('admin/', admin.site.urls),

    # ── API NESJAcademy ────────────────────────────────────────────────────
    path('api/auth/',        include('applications.utilisateurs.urls')),
    path('api/planning/',    include('applications.planning.urls')),
    path('api/diagnostic/',  include('applications.diagnostic.urls')),
    path('api/ia/',          include('applications.ia.urls')),
]
