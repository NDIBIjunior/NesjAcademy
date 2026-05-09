from django.urls import path

from .views import VueObjectifsEleve

urlpatterns = [
    path("objectifs/", VueObjectifsEleve.as_view(), name="planning-objectifs"),
]