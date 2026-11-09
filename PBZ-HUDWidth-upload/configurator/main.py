# -*- coding: utf-8 -*-
"""PBZ_HUDWidth 配置器（Qt 版）

工作方式：
  1. 拖动滑条 -> 写入 live.lua（临时值）
  2. mod 每 500ms 检测到变化立即应用，游戏内即时可见
  3. 满意后回游戏按 F4，把当前值固化进 config.lua
"""

import json
import math
import os
import re
import sys
import time

from PySide6.QtCore import Qt, QTimer
from PySide6.QtGui import QFont
from PySide6.QtWidgets import (
    QApplication, QCheckBox, QFileDialog, QHBoxLayout, QLabel, QLineEdit,
    QPushButton, QSlider, QVBoxLayout, QWidget,
)

PMIN, PMAX = 10.0, 500.0
DEFAULT_MOD_DIR = r"D:\Steam\steamapps\common\PBZ\platform\steam\ue4ss\Mods\PBZ_HUDWidth"

BG      = "#1e1e1d"
PANEL   = "#262625"
INSET   = "#1a1a19"
TEXT    = "#f1efe8"
MUTED   = "#a8a69e"
DIM     = "#7d7b74"
TRACK   = "#444441"
BORDER  = "#3a3a38"
HP_RED  = "#e24b4a"
SHA_AMB = "#ef9f27"


def app_dir():
    if getattr(sys, "frozen", False):
        return os.path.dirname(sys.executable)
    return os.path.dirname(os.path.abspath(__file__))


SETTINGS_PATH = os.path.join(app_dir(), "configurator_settings.json")


def _steam_game_dirs():
    """列出可能的游戏根目录：常见安装位置 + 解析 Steam 的 libraryfolders.vdf。"""
    seeds = [
        "C:/Program Files (x86)/Steam",
        "C:/Program Files/Steam",
        "D:/Steam", "E:/Steam", "F:/Steam",
        "C:/SteamLibrary", "D:/SteamLibrary",
        "E:/SteamLibrary", "F:/SteamLibrary",
    ]
    cands = []
    for sd in seeds:
        cands.append(os.path.join(sd, "steamapps", "common", "PBZ"))
        vdf = os.path.join(sd, "steamapps", "libraryfolders.vdf")
        if os.path.isfile(vdf):
            try:
                with open(vdf, "r", encoding="utf-8", errors="ignore") as f:
                    txt = f.read()
            except OSError:
                txt = ""
            for m in re.finditer(r'"path"\s+"([^"]+)"', txt):
                lib = m.group(1).replace("\\\\", "/")
                cands.append(os.path.join(lib, "steamapps", "common", "PBZ"))
    seen, out = set(), []
    for p in cands:
        k = p.lower()
        if k not in seen:
            seen.add(k)
            out.append(p)
    return out


def autodetect_mod_dir():
    """在 Steam 库里找已安装的 PBZ_HUDWidth，找不到返回空串。"""
    for game in _steam_game_dirs():
        cand = os.path.join(game, "platform", "steam", "ue4ss", "Mods", "PBZ_HUDWidth")
        if os.path.isdir(cand):
            return cand
    return ""


def default_mod_dir():
    return autodetect_mod_dir() or DEFAULT_MOD_DIR


def pos_to_val(pos):
    return PMIN * (PMAX / PMIN) ** (pos / 1000.0)


def val_to_pos(value):
    value = max(PMIN, min(PMAX, float(value)))
    return int(round(1000.0 * math.log(value / PMIN) / math.log(PMAX / PMIN)))


def fmt(value):
    return ("%.1f" % value).rstrip("0").rstrip(".")


class PercentSlider(QSlider):
    def __init__(self, color):
        super().__init__(Qt.Horizontal)
        self.setRange(0, 1000)
        self.setSingleStep(10)
        self.setPageStep(50)
        self.setFixedHeight(28)
        self.setStyleSheet("""
            QSlider::groove:horizontal {
                height: 5px; background: %(track)s; border-radius: 2px;
            }
            QSlider::sub-page:horizontal {
                background: %(color)s; border-radius: 2px;
            }
            QSlider::handle:horizontal {
                width: 11px; height: 11px; margin: -4px 0;
                border-radius: 5px; background: %(text)s;
            }
            QSlider::handle:horizontal:hover {
                background: #ffffff;
            }
        """ % {"track": TRACK, "color": color, "text": TEXT})

    def value_pct(self):
        return pos_to_val(self.value())

    def set_value_pct(self, value):
        self.blockSignals(True)
        self.setValue(val_to_pos(value))
        self.blockSignals(False)


class App(QWidget):
    def __init__(self):
        super().__init__()
        self.mod_dir = self.load_settings()
        hp, sha, lock, self.active = self.read_config()

        self.setWindowTitle("影之刃零 · HUD 血条长度")
        self.setFixedSize(620, 336)
        self.setStyleSheet(self.window_qss())

        self.syncing = False
        self.push_timer = QTimer(self)
        self.push_timer.setSingleShot(True)
        self.push_timer.setInterval(120)
        self.push_timer.timeout.connect(self.push_live)

        self.build_ui(hp, sha, lock)
        self.update_status("就绪", ok=True)

    # ---------- 样式 ----------

    def window_qss(self):
        return """
            QWidget { background: %(bg)s; color: %(text)s;
                      font-family: 'Microsoft YaHei UI'; font-size: 12px; }
            QLabel#title { font-size: 15px; }
            QLabel#sub, QLabel#hint, QLabel#status { color: %(muted)s; font-size: 11px; }
            QLabel#path { color: %(dim)s; font-size: 11px; }
            QLabel#state { font-size: 15px; font-weight: 700; }
            QLineEdit { background: %(inset)s; color: %(text)s; border: 1px solid %(border)s;
                        border-radius: 4px; padding: 3px 6px; font-family: Consolas; }
            QLineEdit:focus { border-color: %(accent)s; }
            QPushButton { background: %(inset)s; color: %(muted)s; border: 1px solid %(border)s;
                          border-radius: 4px; padding: 4px 12px; }
            QPushButton:hover { color: %(text)s; border-color: %(dim)s; }
            QCheckBox { color: %(muted)s; font-size: 12px; spacing: 8px; }
            QCheckBox::indicator { width: 14px; height: 14px; border-radius: 3px;
                                   border: 1px solid %(border)s; background: %(inset)s; }
            QCheckBox::indicator:checked { background: %(accent)s; border-color: %(accent)s; }
        """ % {"bg": BG, "text": TEXT, "muted": MUTED, "dim": DIM,
               "inset": INSET, "border": BORDER, "accent": HP_RED}

    # ---------- 设置读写 ----------

    def load_settings(self):
        try:
            with open(SETTINGS_PATH, "r", encoding="utf-8") as f:
                return json.load(f).get("mod_dir", default_mod_dir())
        except Exception:
            return DEFAULT_MOD_DIR

    def save_settings(self):
        try:
            with open(SETTINGS_PATH, "w", encoding="utf-8") as f:
                json.dump({"mod_dir": self.mod_dir}, f, ensure_ascii=False, indent=2)
        except Exception:
            pass

    def read_config(self):
        path = os.path.join(self.mod_dir, "config.lua")
        try:
            with open(path, "r", encoding="utf-8", errors="ignore") as f:
                txt = f.read()
        except OSError:
            return 100.0, 100.0, True, False

        def grab(key, default):
            m = re.search(key + r"\s*=\s*([\d.]+)", txt)
            return float(m.group(1)) if m else default

        lock = bool(re.search(r"lockSame\s*=\s*true", txt))
        enabled = bool(re.search(r"\benabled\s*=\s*true", txt))
        return grab("hpPercent", 100.0), grab("shaPercent", 100.0), lock, enabled

    # ---------- 界面 ----------

    def build_ui(self, hp, sha, lock):
        root = QVBoxLayout(self)
        root.setContentsMargins(14, 14, 14, 14)

        panel = QWidget()
        panel.setStyleSheet("background: %s; border: 1px solid %s; border-radius: 10px;"
                            % (PANEL, BORDER))
        root.addWidget(panel)

        box = QVBoxLayout(panel)
        box.setContentsMargins(18, 16, 18, 14)
        box.setSpacing(0)

        head = QHBoxLayout()
        title = QLabel("HUD 血条长度")
        title.setObjectName("title")
        head.addWidget(title)
        head.addStretch(1)
        tag = QLabel("影之刃零")
        tag.setObjectName("hint")
        head.addWidget(tag)
        box.addLayout(head)

        self.state_hint = QLabel("")
        self.state_hint.setObjectName("state")
        self.state_hint.setContentsMargins(0, 4, 0, 10)
        box.addWidget(self.state_hint)

        self.state_btn = QPushButton("对齐标准")
        self.state_btn.setCursor(Qt.PointingHandCursor)
        self.state_btn.clicked.connect(self.on_toggle_state)
        box.addWidget(self.state_btn)

        hint = QLabel("100% = 游戏一周目无饰品满双维长度（任何存档都向它对齐）")
        hint.setObjectName("hint")
        hint.setContentsMargins(0, 10, 0, 0)
        box.addWidget(hint)

        self.hp_slider, self.hp_edit = self.add_row(box, "血条长度", hp, HP_RED, 0)
        self.sha_slider, self.sha_edit = self.add_row(box, "杀气条长度", sha, SHA_AMB, 1)

        self.lock_cb = QCheckBox("锁定两条长度一致")
        self.lock_cb.setChecked(lock)
        self.lock_cb.stateChanged.connect(self.on_lock)
        self.lock_cb.setContentsMargins(0, 14, 0, 0)
        box.addWidget(self.lock_cb)

        kfoot = QLabel("拖动滑条即时生效；灰框已默认关闭。")
        kfoot.setObjectName("hint")
        kfoot.setContentsMargins(0, 12, 0, 0)
        box.addWidget(kfoot)

        box.addStretch(1)

        foot = QHBoxLayout()
        self.path_lbl = QLabel(self.short(self.mod_dir))
        self.path_lbl.setObjectName("path")
        foot.addWidget(self.path_lbl)

        pick = QPushButton("更改目录")
        pick.setCursor(Qt.PointingHandCursor)
        pick.clicked.connect(self.pick_dir)
        foot.addWidget(pick)
        foot.addStretch(1)

        self.status = QLabel("")
        self.status.setObjectName("status")
        foot.addWidget(self.status)
        box.addLayout(foot)

        self.update_state_ui()

    def make_chip(self, key, text):
        chip = QWidget()
        chip.setStyleSheet("background: %s; border: 1px solid %s; border-radius: 6px;"
                           % (INSET, BORDER))
        row = QHBoxLayout(chip)
        row.setContentsMargins(8, 3, 9, 3)
        row.setSpacing(6)
        k = QLabel(key)
        k.setStyleSheet("border: none; background: transparent; color: %s;"
                        "font-weight: 600; font-size: 11px;" % TEXT)
        t = QLabel(text)
        t.setStyleSheet("border: none; background: transparent; color: %s;"
                        "font-size: 11px;" % MUTED)
        row.addWidget(k)
        row.addWidget(t)
        return chip

    def add_row(self, parent, label, value, color, index):
        row = QHBoxLayout()
        row.setContentsMargins(0, 6, 0, 6)

        cap = QLabel(label)
        cap.setFixedWidth(76)
        cap.setStyleSheet("color: %s;" % MUTED)
        row.addWidget(cap)

        slider = PercentSlider(color)
        slider.set_value_pct(value)
        slider.valueChanged.connect(lambda v, i=index: self.on_slide(i))
        row.addWidget(slider, 1)

        edit = QLineEdit(fmt(value))
        edit.setFixedWidth(66)
        edit.setAlignment(Qt.AlignRight)
        edit.returnPressed.connect(lambda i=index: self.on_entry(i))
        edit.editingFinished.connect(lambda i=index: self.on_entry(i))
        row.addWidget(edit)

        unit = QLabel("%")
        unit.setStyleSheet("color: %s; font-size: 11px;" % DIM)
        row.addWidget(unit)

        parent.addLayout(row)
        return slider, edit

    def short(self, path):
        return path if len(path) <= 48 else "…" + path[-47:]

    # ---------- 交互 ----------

    def on_slide(self, index):
        if self.syncing:
            return
        self.syncing = True
        if index == 0:
            value = self.hp_slider.value_pct()
            self.hp_edit.setText(fmt(value))
            if self.lock_cb.isChecked():
                self.sha_slider.set_value_pct(value)
                self.sha_edit.setText(fmt(value))
        else:
            value = self.sha_slider.value_pct()
            self.sha_edit.setText(fmt(value))
            if self.lock_cb.isChecked():
                self.hp_slider.set_value_pct(value)
                self.hp_edit.setText(fmt(value))
        self.syncing = False
        self.push_timer.start()

    def on_entry(self, index):
        if self.syncing:
            return
        edit = self.hp_edit if index == 0 else self.sha_edit
        slider = self.hp_slider if index == 0 else self.sha_slider
        try:
            value = float(edit.text())
        except ValueError:
            value = slider.value_pct()
        value = max(PMIN, min(PMAX, value))
        self.syncing = True
        edit.setText(fmt(value))
        slider.set_value_pct(value)
        if self.lock_cb.isChecked():
            self.hp_slider.set_value_pct(value)
            self.sha_slider.set_value_pct(value)
            self.hp_edit.setText(fmt(value))
            self.sha_edit.setText(fmt(value))
        self.syncing = False
        self.push_timer.start()

    def on_lock(self, *args):
        if self.lock_cb.isChecked():
            value = self.hp_slider.value_pct()
            self.syncing = True
            self.sha_slider.set_value_pct(value)
            self.sha_edit.setText(fmt(value))
            self.syncing = False
        self.push_timer.start()


    def on_toggle_state(self):
        self.active = not self.active
        self.update_state_ui()
        self.push_live()

    def update_state_ui(self):
        if self.active:
            self.state_btn.setText("对齐取消")
            self.state_btn.setStyleSheet(
                "QPushButton { background:#3a2a2a; color:#f1efe8; border:1px solid #5c3a3a;"
                " border-radius:6px; padding:8px 12px; font-size:12px; }"
                "QPushButton:hover { background:#4a3232; }")
            self.state_hint.setText("已启用：两条对齐到标准长度，灰框已隐藏。")
        else:
            self.state_btn.setText("对齐标准")
            self.state_btn.setStyleSheet(
                "QPushButton { background:#2f4a3a; color:#f1efe8; border:1px solid #3f6a52;"
                " border-radius:6px; padding:8px 12px; font-size:12px; }"
                "QPushButton:hover { background:#3a5a46; }")
            self.state_hint.setText("当前未启用，点「对齐标准」开始对齐。")

    def push_live(self):
        hp = self.hp_slider.value_pct()
        sha = hp if self.lock_cb.isChecked() else self.sha_slider.value_pct()
        text = (
            "-- 由 PBZ_HUDWidth 配置器实时写入\n"
            "return {\n"
            "    hpPercent = %.1f,\n"
            "    shaPercent = %.1f,\n"
            "    lockSame = %s,\n"
            "    enabled = %s,\n"
            "}\n" % (hp, sha,
                      "true" if self.lock_cb.isChecked() else "false",
                      "true" if self.active else "false")
        )
        target = os.path.join(self.mod_dir, "live.lua")
        tmp = target + ".tmp"
        try:
            with open(tmp, "w", encoding="utf-8") as f:
                f.write(text)
            os.replace(tmp, target)
        except OSError:
            self.update_status("写入失败，检查目录", ok=False)
            return
        self.update_status("已发送 " + time.strftime("%H:%M:%S"), ok=True)

    def pick_dir(self):
        chosen = QFileDialog.getExistingDirectory(
            self, "选择 PBZ_HUDWidth 文件夹", os.path.dirname(self.mod_dir))
        if not chosen:
            return
        self.mod_dir = chosen
        self.path_lbl.setText(self.short(chosen))
        self.save_settings()
        hp, sha, lock, self.active = self.read_config()
        self.syncing = True
        self.hp_slider.set_value_pct(hp)
        self.sha_slider.set_value_pct(sha)
        self.hp_edit.setText(fmt(hp))
        self.sha_edit.setText(fmt(sha))
        self.lock_cb.setChecked(lock)
        self.syncing = False
        self.update_status("目录已更新", ok=True)

    def update_status(self, text, ok=True):
        self.status.setText(text)
        self.status.setStyleSheet(
            "color: %s; font-size: 11px;" % (DIM if ok else HP_RED))


if __name__ == "__main__":
    QApplication.setHighDpiScaleFactorRoundingPolicy(
        Qt.HighDpiScaleFactorRoundingPolicy.PassThrough)
    app = QApplication(sys.argv)
    app.setFont(QFont("Microsoft YaHei UI", 9))
    window = App()
    window.show()
    sys.exit(app.exec())
