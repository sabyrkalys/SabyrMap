"""Фоновый обработчик офлайн-регионов.

Полная реализация (очередь RegionJob, pmtiles extract, сборка MBTiles) —
в фазе 3. Пока это заглушка: контейнер запускается и простаивает, чтобы
топология compose (db, api, worker, martin, nginx) была полной и её можно
было проверить на фазе 1.
"""
import time


def main() -> None:
    print("[worker] запущен (заглушка фазы 1). Ожидание реализации фазы 3.", flush=True)
    while True:
        time.sleep(60)


if __name__ == "__main__":
    main()
