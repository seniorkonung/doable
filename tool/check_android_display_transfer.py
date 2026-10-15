#!/usr/bin/env python3
"""Проверка холодного Split screen, переноса в телефон и жеста «Назад» на API 36.

Запуск: python3 tool/check_android_display_transfer.py --serial emulator-5554
Нужны Python 3, adb и готовый debug APK. Используйте тестовый эмулятор:
сценарий переустанавливает APK без удаления данных, открывает каталог
и создаёт намерения. Нужна включённая жестовая навигация (navigation_mode=2).
Размер, плотность и настройки поворота восстанавливаются даже при отказе.
Дампы Android, семантика и снимки экрана сохраняются вне репозитория.
"""

import argparse
import hashlib
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

    def ui(self, all_windows=False):
        self.shell("uiautomator", "dump", *(["--windows"] if all_windows else []),
                   "/data/local/tmp/doable-transfer.xml")
        xml = self.shell("cat", "/data/local/tmp/doable-transfer.xml")
        (self.evidence / "last-ui.xml").write_text(xml)
        return list(ET.fromstring(xml).iter("node"))

    def tap(self, predicate, long_press=False):
        def locate():
            nodes = [node for node in self.ui() if predicate(node.attrib)]
            require(len(nodes) == 1, f"Ожидался один элемент, найдено {len(nodes)}")
            return nodes[0].attrib
        node = eventually(locate, "Элемент интерфейса не найден")
        left, top, right, bottom = map(int, re.findall(r"\d+", node["bounds"]))
        require(right > left and bottom > top, f"Элемент вне окна: {node}")
        x, y = str((left + right) // 2), str((top + bottom) // 2)
        if long_press:
            self.shell("input", "swipe", x, y, x, y, "800")
        else:
            self.shell("input", "tap", x, y)

    def tap_label(self, *labels):
        self.tap(lambda a: a.get("content-desc", "").split("\n")[0] in labels
                 or a.get("text") in labels)

    def launcher(self):
        self.shell("am", "start", "-W", "-a", "android.intent.action.MAIN",
                   "-c", "android.intent.category.LAUNCHER", "-n", f"{PACKAGE}/.MainActivity")

    def back_gesture(self):
        require(self.shell("settings", "get", "secure", "navigation_mode") == "2",
                "Системный жест требует navigation_mode=2")
        size = re.search(r"(?:Override|Physical) size: (\d+)x(\d+)$", self.shell("wm", "size"))
        require(size is not None, "Размер дисплея не найден")
        width, height = map(int, size.groups())
        self.shell("input", "swipe", "1", str(height // 2), str(width * 3 // 4),
                   str(height // 2), "500")

    def capture(self, name, all_windows=False):
        for service in ("activity activities", "window windows", "activity recents"):
            text = self.shell("dumpsys", *service.split())
            (self.evidence / f"{name}-{service.replace(' ', '-')}.txt").write_text(text)
        self.ui(all_windows)
        (self.evidence / f"{name}-ui.xml").write_bytes((self.evidence / "last-ui.xml").read_bytes())
        (self.evidence / f"{name}.png").write_bytes(self.adb("exec-out", "screencap", "-p", binary=True))


def activity_blocks(dump):
    return re.findall(
        r"\* Hist\s+#\d+: ActivityRecord\{([^\n]+)\}\n(.*?)"
        r"(?=\n\s*\* (?:Hist|Task)|\Z)", dump, re.S,
    )


def host_state(device, host, package=PACKAGE):
    dump = device.shell("dumpsys", "activity", "activities")
    matches = [(record, body) for record, body in activity_blocks(dump)
               if f"{package}/.{host} " in record and "mVisible=true" in body]
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


def window_frame(device, component):
    windows = device.shell("dumpsys", "window", "windows")
    window = re.search(rf"Window #\d+ Window\{{[^\n]+{re.escape(component)}\}}:(.*?)"
                       r"(?=\n  Window #|\Z)", windows, re.S)
    require(window is not None, f"Нет окна {component}")
    body = window.group(1)
    require("isVisible=true" in body and "mHasSurface=true" in body, "Окно ещё не показано")
    frame = re.search(r"Frames:.*? frame=\[(\d+),(\d+)\]\[(\d+),(\d+)\]", body)
    require(frame is not None, "Не найдены фактические границы окна")
    return list(map(int, frame.groups()))


def phone_state(device):
    state = host_state(device, "PhoneActivity")
    require(state["mode"] == "fullscreen" and not state["multi_window"],
            f"PhoneActivity осталась в разделённом экране: {state}")
    require(state["portrait"] and state["resumed"] and state["bounds"] == [0, 0, 390, 844],
            f"Нет полного портретного окна: {state}")
    require(state["display"] == state["bounds"] and state["density"] == 160,
            f"Конечный полный дисплей не равен 390×844 dp: {state}")
    state["frame"] = window_frame(device, f"{PACKAGE}/{PACKAGE}.PhoneActivity")
    require(state["frame"] == [0, 0, 390, 844], f"Окно обрезано: {state}")
    return state


def cold_precondition(device):
    process_dump = device.shell("ps", "-A", "-o", "NAME")
    (device.evidence / "cold-processes-before.txt").write_text(process_dump)
    processes = process_dump.splitlines()
    require(not any(name == PACKAGE or name.startswith(PACKAGE + ":") for name in processes),
            "Перед холодным выбором уже существует процесс приложения")
    for service in ("activities", "recents"):
        dump = device.shell("dumpsys", "activity", service)
        require(not any(PACKAGE in line for line in dump.splitlines()
                        if re.search(r"\* (?:Task\{|Recent #\d+: Task\{|Hist\s+#)", line)),
                f"Перед холодным выбором уже существует task приложения: {service}")
    return {"process": False, "task": False}


def cold_split_state(device):
    state = split_state(device)
    settings = host_state(device, "homepage.SettingsHomepageActivity", "com.android.settings")
    require(state["resumed"] and settings["mode"] == "multi-window" and settings["multi_window"],
            f"Оба приложения должны оставаться в Split screen: {state}, {settings}")
    left, top, right, bottom = state["bounds"]
    require(left == 0 and right == 600 and bottom == 900 and abs(top - 450) <= 24,
            f"Холодный вход потерял выбранную нижнюю половину: {state}")
    require(settings["bounds"][:2] == [0, 0] and settings["bounds"][2] == 600
            and abs(settings["bounds"][3] - 450) <= 24
            and settings["bounds"][3] <= top, f"Settings потерял верхнюю половину: {settings}")
    for current, component in ((state, f"{PACKAGE}/{PACKAGE}.LargeDisplayActivity"),
                               (settings, "com.android.settings/com.android.settings.homepage.SettingsHomepageActivity")):
        current["frame"] = window_frame(device, component)
        require(current["frame"] == current["bounds"], f"Границы окна расходятся с task: {current}")
    nodes = device.ui(all_windows=True)
    for package in (PACKAGE, "com.android.settings"):
        require(any(node.attrib.get("package") == package
                    and (node.attrib.get("text") or node.attrib.get("content-desc"))
                    for node in nodes), f"Нет видимого содержимого {package}")
    return {"app": state, "settings": settings}


def check_cold_split(device):
    device.shell("am", "force-stop", PACKAGE)
    recents = device.shell("dumpsys", "activity", "recents")
    for line in recents.splitlines():
        if re.search(r"\* Recent #\d+: Task\{", line) and PACKAGE in line:
            device.shell("am", "stack", "remove", re.search(r" #(\d+) ", line).group(1))
    eventually(lambda: cold_precondition(device), "Не установлен холодный вход")
    device.shell("input", "keyevent", "KEYCODE_HOME")
    device.shell("am", "start", "-W", "-a", "android.settings.SETTINGS")
    settings = eventually(
        lambda: host_state(device, "homepage.SettingsHomepageActivity", "com.android.settings"),
        "Settings не открыт перед холодным Split screen")
    require(settings["display"] == [0, 0, 600, 900] and settings["density"] == 160,
            f"Полный дисплей перед выбором не равен 600×900 dp: {settings}")
    device.shell("input", "keyevent", "KEYCODE_HOME")
    device.ui()
    device.shell("input", "swipe", "300", "820", "300", "200", "400")
    device.tap(lambda a: a.get("resource-id") == "com.android.launcher3:id/icon"
               and a.get("text") in ("Settings", "Настройки"), long_press=True)
    device.tap_label("Split screen", "Разделить экран")
    def selection():
        nodes = device.ui()
        require(any(node.attrib.get("resource-id") == "com.android.launcher3:id/split_instructions_text"
                    for node in nodes), "Система не ожидает выбора второй стороны Split screen")
        require(any(node.attrib.get("content-desc") in ("Settings", "Настройки")
                    and node.attrib.get("resource-id") == ""
                    and list(map(int, re.findall(r"\d+", node.attrib["bounds"])))[3] < 450
                    for node in nodes), "Settings не выбран верхней стороной")
    eventually(selection, "Предусловие выбора второй стороны не установлено")
    device.capture("cold-selection", all_windows=True)
    precondition = cold_precondition(device)
    print(f"Холодный вход перед выбором второй стороны: {precondition}", flush=True)
    device.tap(lambda a: a.get("resource-id") == "com.android.launcher3:id/icon"
               and a.get("text") == "doable")
    state = eventually(lambda: cold_split_state(device), "Холодный Split screen не сохранил размещение")
    device.capture("cold-split", all_windows=True)
    print(f"Холодный вход сохранил нижнюю половину, Settings виден сверху: {state}", flush=True)


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


def shown(device, *labels):
    actual = {node.attrib.get(key, "") for node in device.ui()
              if node.attrib.get("package") == PACKAGE for key in ("text", "content-desc")}
    require(any(label in actual for label in labels), f"Экран не показывает {labels}")


def home_state(device, host):
    state = host_state(device, host)
    require(state["resumed"], f"{host} не активна: {state}")
    shown(device, "Сводка периода", "Period summary")
    return state


def prepare_draft(device, title):
    device.tap(lambda a: a.get("content-desc", "").startswith(("Быстрое создание", "Quick creation")),
               long_press=True)
    device.tap_label("Новое намерение", "New intention")
    device.tap(lambda a: a.get("content-desc", "").startswith(("Быстрое создание", "Quick creation")))
    device.tap(lambda a: a.get("class") == "android.widget.EditText"
               and a.get("package") == PACKAGE and a.get("enabled") == "true"
               and a.get("hint") in ("Название", "Title"))
    device.shell("input", "text", title)
    device.back_gesture()
    eventually(lambda: keyboard_hidden(device), "Клавиатура не скрылась")
    shown(device, title)


def keyboard_hidden(device):
    require("mInputShown=false" in device.shell("dumpsys", "input_method"),
            "Клавиатура должна быть скрыта перед проверкой закрытия")


def prepare_details(device, title):
    prepare_draft(device, title)
    device.tap_label("Сохранить", "Save")
    eventually(lambda: shown(device, "Подробности намерения", "Intention details"),
               "Подробности не открылись над Главной")
    shown(device, title)


def check_back_navigation(device):
    title = f"BackGesture{time.time_ns()}"
    device.shell("am", "force-stop", PACKAGE)
    device.launcher()
    eventually(lambda: home_state(device, "PhoneActivity"), "Контроль: Главная не открылась")
    prepare_details(device, title)
    device.capture("back-control-details")
    device.back_gesture()
    eventually(lambda: home_state(device, "PhoneActivity"), "Контроль: жест не вернул Главную")
    device.capture("back-control-home")
    print("Контроль без переноса: первый жест с подробностей вернул Главную", flush=True)

    for screen in ("details", "draft"):
        device.shell("wm", "size", "600x900")
        device.shell("am", "force-stop", PACKAGE)
        device.launcher()
        eventually(lambda: home_state(device, "LargeDisplayActivity"), "Нет Главной большого хоста")
        current_title = f"{title}-{screen}"
        if screen == "details":
            prepare_details(device, current_title)
        else:
            prepare_draft(device, current_title)
        pid = device.shell("pidof", PACKAGE)
        device.capture(f"back-{screen}-before")
        device.shell("wm", "size", "390x844")
        eventually(lambda: phone_state(device), "Нет PhoneActivity после переноса")
        require(device.shell("pidof", PACKAGE) == pid, "Перенос перезапустил процесс")
        shown(device, current_title)
        keyboard_hidden(device)
        device.capture(f"back-{screen}-transferred")
        device.back_gesture()
        if screen == "details":
            eventually(lambda: home_state(device, "PhoneActivity"), "Первый жест закрыл хост вместо подробностей")
            print("После переноса: первый жест с подробностей вернул Главную; PhoneActivity активна", flush=True)
        else:
            eventually(lambda: shown(device, "Сбросить черновик?", "Discard the draft?"),
                       "Жест обошёл подтверждение закрытия черновика")
            device.capture("back-draft-confirmation")
            device.tap_label("Продолжить ввод", "Keep editing")
            shown(device, current_title)
            phone_state(device)
            print("После переноса: жест запросил подтверждение; продолжение сохранило черновик", flush=True)
            # Продолжение возвращает фокус и клавиатуру; завершаем форму её командой.
            device.tap(lambda a: a.get("class") == "android.widget.Button"
                       and a.get("content-desc") in ("Закрыть форму", "Close the form"))
            eventually(lambda: shown(device, "Сбросить черновик?", "Discard the draft?"), "Нет подтверждения сброса")
            device.tap_label("Сбросить", "Discard")
            eventually(lambda: home_state(device, "PhoneActivity"), "Сброс не вернул Главную")
        device.capture(f"back-{screen}-home")
        device.back_gesture()
        def exited():
            dump = device.shell("dumpsys", "activity", "activities")
            require(not any(f"{PACKAGE}/" in record and "state=RESUMED" in body
                            for record, body in activity_blocks(dump)), "Главная перехватила выход")
            require(any(node.attrib.get("package") == "com.android.launcher3" for node in device.ui()),
                    "Жест не показал launcher")
        eventually(exited, "Жест с Главной не вышел из приложения")
        device.capture(f"back-{screen}-exit")
        print("Главная после переноса: системный жест вышел в launcher", flush=True)


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
    digest = hashlib.sha256()
    with args.apk.open("rb") as apk:
        for chunk in iter(lambda: apk.read(1024 * 1024), b""):
            digest.update(chunk)
    print(f"APK: {args.apk.resolve()}; SHA-256={digest.hexdigest()}", flush=True)
    print(f"Android: {device.shell('getprop', 'ro.build.fingerprint')}", flush=True)
    require(device.shell("getprop", "ro.kernel.qemu") == "1", "Нужен тестовый эмулятор")
    require(device.shell("getprop", "ro.build.version.sdk") == "36", "Нужен Android API 36")
    require(device.shell("getprop", "sys.boot_completed") == "1", "Эмулятор ещё загружается")
    require(device.shell("settings", "get", "secure", "navigation_mode") == "2",
            "Включите жестовую навигацию: нужен navigation_mode=2")

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
        check_cold_split(device)
        device.shell("am", "force-stop", PACKAGE)
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
        check_back_navigation(device)
    except BaseException:
        try:
            device.capture("failure")
        except Exception as error:
            print(f"Не удалось снять все наблюдения отказа: {error}", flush=True)
        raise
    finally:
        restore_settings(device, saved)
    print("Проверки холодного Split screen, переноса в телефон и жестов пройдены", flush=True)


if __name__ == "__main__":
    main()
