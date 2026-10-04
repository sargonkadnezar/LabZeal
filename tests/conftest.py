"""pytest-Konfiguration fuer die LabZeal-Tests."""


def pytest_configure(config):
    config.addinivalue_line(
        "markers", "network: benoetigt Netzwerkzugriff (Kapeli-API)")
