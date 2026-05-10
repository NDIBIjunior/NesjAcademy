from django.urls import path

from .views import VueDisponibilite, VueObjectifsEleve

urlpatterns = [
    path("objectifs/",      VueObjectifsEleve.as_view(), name="planning-objectifs"),
    path("disponibilite/",  VueDisponibilite.as_view(),  name="planning-disponibilite"),
]