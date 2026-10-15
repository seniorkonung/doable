#!/usr/bin/env python3
"""Проверка переноса Split screen → телефон на AOSP-эмуляторе API 36.

Запуск: python3 tool/check_android_display_transfer.py --serial emulator-5554
Нужны Python 3, adb и готовый debug APK. Используйте тестовый эмулятор:
сценарий переустанавливает APK без удаления данных и открывает каталог.
Размер, плотность и настройки поворота восстанавливаются даже при отказе.
Дампы Android, семантика и снимки экрана сохраняются вне репозитория.
"""

import argparse
import json
import re
import shlex
import signal
import subprocess
import tempfile
import time
import xml.etree.ElementTree as ET
from pathlib import Path

PACKAGE = "software.doable.doable"


def require(condition, message):
    if not condition:
        raise AssertionError(message)


def eventually(observe, description):
    deadline = time.monotonic() + 30
    while True:
        try:
            return observe()
        except AssertionError as error:
            if time.monotonic() >= deadline:
                raise AssertionError(f"{description}: {error}") from error
            time.sleep(0.5)


class Device:
    def __init__(self, serial, evidence):
        self.serial = serial
        self.evidence = evidence

    def adb(self, *args, binary=False):
        result = subprocess.run(
            ["adb", "-s", self.serial, *args],
            capture_output=True, text=not binary, timeout=45, check=True,
        )
        return result.stdout if binary else result.stdout.strip()

    def shell(self, *args):
        return self.adb("shell", shlex.join(args))

    def ui(self):
        self.shell("uiautomator", "dump", "/data/local/tmp/doable-transfer.xml")
        xml = self.shell("cat", "/data/local/tmp/doable-transfer.xml")
        (self.evidence / "last-ui.xml").write_text(xml)
        return list(ET.fromstring(xml).iter("node"))

    def tap(self, predicate):
        def locate():
            nodes = [node for node in self.ui() if predicate(node.attrib)]
            require(len(nodes) == 1, f"Ожидался один элемент, найдено {len(nodes)}")
            return nodes[0].attrib
        node = eventually(locate, "Элемент интерфейса не найден")
        left, top, right, bottom = map(int, re.findall(r"\d+", node["bounds"]))
        require(right > left and bottom > top, f"Элемент вне окна: {node}")
        self.shell("input", "tap", str((left + right) // 2), str((top + bottom) // 2))

    def tap_label(self, *labels):
        self.tap(lambda a: a.get("content-desc", "").split("\n")[0] in labels
                 or a.get("text") in labels)

    def launcher(self):
        self.shell("am", "start", "-W", "-a", "android.intent.action.MAIN",
                   "-c", "android.intent.category.LAUNCHER", "-n", f"{PACKAGE}/.MainActivity")

    def capture(self, name):
        for service in ("activity activities", "window windows", "activity recents"):
            text = self.shell("dumpsys", *service.split())
            (self.evidence / f"{name}-{service.replace(' ', '-')}.txt").write_text(text)
        self.ui()
        (self.evidence / f"{name}-ui.xml").write_bytes((self.evidence / "last-ui.xml").read_bytes())
        (self.evidence / f"{name}.png").write_bytes(self.adb("exec-out", "screencap", "-p", binary=True))


def activity_blocks(dump):
    return re.findall(
        r"\* Hist\s+#\d+: ActivityRecord\{([^\n]+)\}\n(.*?)"
        r"(?=\n\s*\* (?:Hist|Task)|\Z)", dump, re.S,
    )


def host_state(device, host):
    dump = device.shell("dumpsys", "activity", "activities")
    matches = [(record, body) for record, body in activity_blocks(dump)
               if f"{PACKAGE}/.{host} " in record and "mVisible=true" in body]
    require(len(matches) == 1, f"Нет единственной видимой {host}")
    record, body = matches[0]
    task_id = re.search(r" t(\d+)", record).group(1)
    task = re.search(rf"(?m)^.*\* Task\{{[^\n]+ #{task_id} [^\n]+", dump).group(0)
    config = re.search(r"CurrentConfiguration=([^\n]+)", body).group(1)
    state = {
        "host": host,
        "mode": re.search(r" mode=([\w-]+)", task).group(1),
        "multi_window": "mLastReportedMultiWindowMode=true" in body,
        "bounds": list(map(int, re.search(r"mBounds=Rect\((\d+), (\d+) - (\d+), (\d+)\)", config).groups())),
        "display": list(map(int, re.search(r"mMaxBounds=Rect\((\d+), (\d+) - (\d+), (\d+)\)", config).groups())),
        "density": int(re.search(r" (\d+)dpi ", config).group(1)),
        "portrait": " port " in config,
        "resumed": "state=RESUMED" in body,
    }
    return state


def split_state(device):
    state = host_state(device, "LargeDisplayActivity")
    require(state["mode"] == "multi-window" and state["multi_window"],
            f"Исходный Split screen приложения не подтверждён: {state}")
    require(state["display"] == [0, 0, 600, 900] and state["density"] == 160,
            f"Исходный полный дисплей не равен 600×900 dp: {state}")
    require(state["bounds"] != state["display"], "Приложение ещё занимает весь дисплей")
    blocks = activity_blocks(device.shell("dumpsys", "activity", "activities"))
    require(any("com.android.settings/" in record and "mVisible=true" in body
                and "mLastReportedMultiWindowMode=true" in body for record, body in blocks),
            "Settings не наблюдается рядом в multi-window")
    return state


def phone_state(device):
    state = host_state(device, "PhoneActivity")
    require(state["mode"] == "fullscreen" and not state["multi_window"],
            f"PhoneActivity осталась в разделённом экране: {state}")
    require(state["portrait"] and state["resumed"] and state["bounds"] == [0, 0, 390, 844],
            f"Нет полного портретного окна: {state}")
    require(state["display"] == state["bounds"] and state["density"] == 160,
            f"Конечный полный дисплей не равен 390×844 dp: {state}")
    windows = device.shell("dumpsys", "window", "windows")
    window = re.search(rf"Window #\d+ Window\{{[^\n]+{re.escape(PACKAGE)}\.PhoneActivity\}}:(.*?)"
                       r"(?=\n  Window #|\Z)", windows, re.S)
    require(window is not None, "Нет окна PhoneActivity")
    body = window.group(1)
    require("isVisible=true" in body and "mHasSurface=true" in body, "Окно ещё не показано")
    frame = re.search(r"Frames:.*? frame=\[(\d+),(\d+)\]\[(\d+),(\d+)\]", body)
    require(frame is not None, "Не найдены фактические границы окна")
    state["frame"] = list(map(int, frame.groups()))
    require(state["frame"] == [0, 0, 390, 844], f"Окно обрезано: {state}")
    return state


def save_settings(device):
    saved = {}
    for key in ("size", "density"):
        output = device.shell("wm", key)
        override = re.search(r"Override " + key + r": (\S+)", output)
        saved[key] = override.group(1) if override else "reset"
    for key in ("accelerometer_rotation", "user_rotation"):
        saved[key] = device.shell("settings", "get", "system", key)
    return saved


def restore_settings(device, saved):
    failures = []
    commands = [["wm", "size", saved["size"]], ["wm", "density", saved["density"]]]
    for key in ("user_rotation", "accelerometer_rotation"):
        commands.append(["settings", "delete", "system", key] if saved[key] == "null"
                        else ["settings", "put", "system", key, saved[key]])
    for command in commands:
        try:
            device.shell(*command)
        except (subprocess.SubprocessError, OSError) as error:
            failures.append(str(error))
    require(not failures, f"Не удалось восстановить параметры: {failures}")
    actual = save_settings(device)
    require(actual == saved, f"Параметры не восстановлены: {actual}, ожидалось {saved}")
    print(f"Параметры эмулятора восстановлены: {actual}", flush=True)


def catalog_state(device):
    labels = [node.attrib.get("content-desc", "") for node in device.ui()
              if node.attrib.get("package") == PACKAGE]

    def one(predicate, description):
        values = [label for label in labels if predicate(label)]
        require(len(values) == 1, f"{description}: найдено {values}")
        return values[0]

    require(any(label in ("Свернуть календарь", "Collapse calendar") for label in labels),
            "Раскрытый календарь не сохранился")
    return {
        "date": one(lambda label: re.fullmatch(r"\d{1,2} [^\n]+ \d{4}", label), "Выбранная дата"),
        "month": one(lambda label: re.fullmatch(r"[^\d\n,]+ \d{4}", label), "Месяц просмотра"),
        "filter": one(lambda label: label.startswith(("Выполнение\n", "Completion\n")), "Фильтр"),
        "total": one(lambda label: label.startswith(("Всего дневных выборов:", "Total daily choices:")), "Количество"),
    }


def catalog_result(device):
    # На узком экране строка выдачи находится ниже фильтра: читаем её прокруткой.
    for attempt in range(5):
        nodes = device.ui()
        labels = [node.attrib.get("content-desc", "") for node in nodes]
        result = next((label for label in labels if label.startswith(("Выбор № 1.", "Choice #1."))
                       or label in ("Дневных выборов по фильтрам нет.",
                                    "No daily choices match the filters.")), None)
        if result is not None and attempt == 0:
            return result
        areas = [node.attrib for node in nodes if node.attrib.get("scrollable") == "true"
                 and node.attrib.get("package") == PACKAGE
                 and node.attrib.get("class") == "android.widget.ScrollView"]
        require(len(areas) == 1, f"Не найдена единственная прокрутка выдачи: {areas}")
        left, top, right, bottom = map(int, re.findall(r"\d+", areas[0]["bounds"]))
        x = str((left + right) // 2)
        if result is not None:
            if attempt:
                device.shell("input", "swipe", x, str(top + 10), x, str(bottom - 10), "100")
                eventually(lambda: catalog_state(device), "Не удалось вернуть начало списка")
            return result
        device.shell("input", "swipe", x, str(bottom - 10), x, str(top + 10), "350")
    raise AssertionError("Не найдены ни первая строка выдачи, ни пустое состояние")


def prepare_catalog(device):
    device.tap_label("Дневные выборы", "Daily choices")
    def choose_day():
        days = [node.attrib for node in device.ui()
                if node.attrib.get("package") == PACKAGE
                and node.attrib.get("clickable") == "true"
                and node.attrib.get("selected") != "true"
                and re.search(r"\d{4}", node.attrib.get("content-desc", ""))]
        require(bool(days), "Нет другого дня в недельной строке")
        marked = [day for day in days if "невыполненный" in day["content-desc"]
                  or "incomplete" in day["content-desc"].lower()]
        return (marked or days)[0]["content-desc"]
    day = eventually(choose_day, "Не удалось выбрать другой день")
    device.tap_label(day)
    device.tap_label("Выполнение", "Completion")
    device.tap_label("Не выполненные", "Not completed")
    device.tap_label("Развернуть календарь", "Expand calendar")
    device.tap_label("Следующий месяц", "Next month")
    state = eventually(lambda: catalog_state(device), "Каталог не подготовлен")
    require("Не выполненные" in state["filter"] or "Not completed" in state["filter"], "Фильтр не применён")
    return state


def check_recents(device):
    dump = device.shell("dumpsys", "activity", "recents")
    cards = [line for line in dump.splitlines() if re.search(r"\* Recent #\d+: Task\{", line)
             and PACKAGE in line]
    require(len(cards) == 1, f"Ожидалась одна карточка приложения: {cards}")
    return len(cards)


def interrupted(_signum, _frame):
    raise KeyboardInterrupt("Проверка прервана")


def main():
    signal.signal(signal.SIGTERM, interrupted)
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--serial", required=True, help="Серийный номер тестового AOSP-эмулятора API 36")
    parser.add_argument("--apk", type=Path, default=Path("build/app/outputs/flutter-apk/app-debug.apk"))
    args = parser.parse_args()
    require(args.apk.is_file(), f"Сначала соберите debug APK: {args.apk}")
    evidence = Path(tempfile.mkdtemp(prefix="doable-display-transfer-"))
    print(f"Наблюдения Android: {evidence}", flush=True)
    device = Device(args.serial, evidence)
    require(device.shell("getprop", "ro.kernel.qemu") == "1", "Нужен тестовый эмулятор")
    require(device.shell("getprop", "ro.build.version.sdk") == "36", "Нужен Android API 36")
    require(device.shell("getprop", "sys.boot_completed") == "1", "Эмулятор ещё загружается")

    for key in ("force_resizable_activities", "enable_non_resizable_multi_window"):
        require(device.shell("settings", "get", "global", key) in ("0", "null"),
                f"Отключите обходную настройку {key} перед проверкой")
    saved = save_settings(device)
    (evidence / "settings-before.json").write_text(json.dumps(saved))
    try:
        device.shell("settings", "put", "system", "accelerometer_rotation", "0")
        device.shell("settings", "put", "system", "user_rotation", "0")
        device.shell("wm", "density", "160")
        device.shell("wm", "size", "600x900")
        device.adb("install", "-r", str(args.apk.resolve()))
        device.shell("am", "force-stop", PACKAGE)
        device.shell("input", "keyevent", "KEYCODE_WAKEUP")
        device.shell("wm", "dismiss-keyguard")
        device.shell("input", "keyevent", "KEYCODE_HOME")
        device.shell("am", "start", "-W", "-a", "android.settings.SETTINGS")
        device.launcher()
        eventually(lambda: host_state(device, "LargeDisplayActivity"), "Нет большого хоста")
        before = prepare_catalog(device)
        before["result"] = catalog_result(device)
        pid = device.shell("pidof", PACKAGE)
        require(bool(pid), "Процесс приложения не найден")
        device.capture("before-split")
        print(f"Каталог до переноса: {json.dumps(before, ensure_ascii=False)}; PID={pid}", flush=True)

        device.shell("input", "keyevent", "KEYCODE_APP_SWITCH")
        device.tap(lambda a: a.get("resource-id") == "com.android.launcher3:id/action_split")
        device.tap(lambda a: a.get("resource-id") == "com.android.launcher3:id/snapshot"
                   and a.get("content-desc") in ("Settings", "Настройки"))
        split = eventually(lambda: split_state(device), "Обычный Split screen не установлен")
        device.capture("split")
        print(f"Split screen подтверждён, Settings виден рядом: {split}", flush=True)

        device.shell("wm", "size", "390x844")
        after = eventually(lambda: phone_state(device), "Перенос не дал полноэкранный телефон")
        require(device.shell("pidof", PACKAGE) == pid, "Процесс перезапущен при переносе")
        current = eventually(lambda: catalog_state(device), "Каталог после переноса недоступен")
        current["result"] = catalog_result(device)
        require(current == before, f"Состояние каталога потеряно: {current}, ожидалось {before}")
        device.capture("phone")
        eventually(lambda: check_recents(device), "После переноса остались лишние карточки")
        print(f"Телефонное окно: {after}; PID={pid}; каталог сохранён", flush=True)

        device.shell("input", "keyevent", "KEYCODE_HOME")
        device.launcher()
        eventually(lambda: phone_state(device), "Launcher не вернул PhoneActivity")
        current = eventually(lambda: catalog_state(device), "Launcher не вернул каталог")
        current["result"] = catalog_result(device)
        require(current == before, f"Launcher потерял сессию: {current}")
        require(device.shell("pidof", PACKAGE) == pid, "Launcher перезапустил процесс")
        cards = eventually(lambda: check_recents(device), "Launcher добавил карточку приложения")
        device.capture("launcher")
        print(f"Launcher вернул ту же сессию; карточек приложения: {cards}", flush=True)
    except BaseException:
        try:
            device.capture("failure")
        except Exception as error:
            print(f"Не удалось снять все наблюдения отказа: {error}", flush=True)
        raise
    finally:
        restore_settings(device, saved)
    print("Проверка переноса Split screen → телефон пройдена", flush=True)


if __name__ == "__main__":
    main()
