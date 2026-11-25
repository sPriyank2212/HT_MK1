"""Golden Sample Learning wizard — turn auto-scan results into a netlist."""

from __future__ import annotations

import os
from datetime import datetime
from pathlib import Path

from PyQt6.QtCore import Qt
from PyQt6.QtWidgets import (
    QWizard, QWizardPage, QVBoxLayout, QHBoxLayout,
    QLabel, QTreeWidget, QTreeWidgetItem, QLineEdit,
    QPushButton, QFileDialog, QMessageBox, QCheckBox,
    QInputDialog,
)

from core.netlist import Net, NetPin, Netlist, save_netlist, validate_netlist


class GoldenSampleWizard(QWizard):
    """Wizard that reviews auto-scan discovered pairs and saves a netlist."""

    def __init__(self, parent=None, pairs: list[tuple[int, int]] | None = None,
                 harness_id: str = ""):
        super().__init__(parent)
        self._pairs = list(pairs or [])
        self._harness_id = harness_id
        self.setWindowTitle("Golden Sample Learning")
        self.setMinimumSize(640, 520)

        self.addPage(WarningPage())
        self.addPage(ReviewPage(self._pairs))
        self.addPage(SavePage())

        self.button(QWizard.WizardButton.FinishButton).clicked.connect(self._on_finish)

    def _on_finish(self) -> None:
        review_page = self.page(1)
        save_page = self.page(2)
        pairs = review_page.selected_pairs()
        net_name_prefix = save_page.net_name_prefix()
        path = save_page.save_path()
        if not path:
            return

        nets = []
        for i, (pa, pb) in enumerate(pairs, start=1):
            nets.append(Net(
                name=f"{net_name_prefix}{i}",
                pins=[NetPin(pa, f"A{pa}"), NetPin(pb, f"B{pb}")],
                source="Side A",
                destination="Side B",
            ))

        netlist = Netlist(nets=nets, harness_id=self._harness_id, path=path)
        errors = validate_netlist(netlist)
        if errors:
            QMessageBox.warning(self, "Validation Failed", "\n".join(errors))
            return
        try:
            save_netlist(netlist, path)
            self._saved_path = path
        except OSError as exc:
            QMessageBox.critical(self, "Save Error", str(exc))

    def saved_path(self) -> str:
        return getattr(self, "_saved_path", "")


class WarningPage(QWizardPage):
    def __init__(self, parent=None):
        super().__init__(parent)
        self.setTitle("Golden Sample Learning")
        self.setSubTitle("Create a netlist from a known-good harness")

        layout = QVBoxLayout(self)
        layout.addWidget(QLabel(
            "This wizard helps you create a netlist from a harness that is known to be "
            "correctly wired.\n\n"
            "1. Connect the known-good harness to Side A and Side B.\n"
            "2. Run Auto-Scan from the main window.\n"
            "3. Return here to review the discovered connections and save them as a netlist.\n\n"
            "The resulting netlist can then be used to test all subsequent harnesses of the same type."
        ))
        self._chk_understand = QCheckBox("I understand this creates a reference netlist from one sample.")
        layout.addWidget(self._chk_understand)
        layout.addStretch()
        self.registerField("understand*", self._chk_understand)


class ReviewPage(QWizardPage):
    def __init__(self, pairs: list[tuple[int, int]], parent=None):
        super().__init__(parent)
        self._pairs = pairs
        self.setTitle("Review Discovered Connections")
        self.setSubTitle(f"{len(pairs)} connection(s) found. Rename nets and exclude any unwanted pairs.")

        layout = QVBoxLayout(self)
        self._tree = QTreeWidget()
        self._tree.setHeaderLabels(["Include", "Net Name", "Side A", "Side B"])
        self._tree.setColumnWidth(0, 60)
        self._tree.setColumnWidth(1, 200)
        layout.addWidget(self._tree)

        btn_layout = QHBoxLayout()
        self._btn_rename = QPushButton("Rename Selected")
        self._btn_exclude_all = QPushButton("Exclude All")
        self._btn_include_all = QPushButton("Include All")
        btn_layout.addWidget(self._btn_rename)
        btn_layout.addWidget(self._btn_include_all)
        btn_layout.addWidget(self._btn_exclude_all)
        btn_layout.addStretch()
        layout.addLayout(btn_layout)

        self._btn_rename.clicked.connect(self._on_rename)
        self._btn_exclude_all.clicked.connect(lambda: self._set_all(False))
        self._btn_include_all.clicked.connect(lambda: self._set_all(True))

        self._populate()

    def _populate(self) -> None:
        self._tree.clear()
        for i, (pa, pb) in enumerate(self._pairs, start=1):
            item = QTreeWidgetItem()
            item.setFlags(item.flags() | Qt.ItemFlag.ItemIsUserCheckable)
            item.setCheckState(0, Qt.CheckState.Checked)
            item.setText(1, f"WIRE_{i}")
            item.setText(2, str(pa))
            item.setText(3, str(pb))
            self._tree.addTopLevelItem(item)

    def _on_rename(self) -> None:
        item = self._tree.currentItem()
        if not item:
            return
        text, ok = QInputDialog.getText(self, "Rename Net", "Net name:", text=item.text(1))
        if ok and text.strip():
            item.setText(1, text.strip())

    def _set_all(self, include: bool) -> None:
        state = Qt.CheckState.Checked if include else Qt.CheckState.Unchecked
        for i in range(self._tree.topLevelItemCount()):
            self._tree.topLevelItem(i).setCheckState(0, state)

    def selected_pairs(self) -> list[tuple[int, int]]:
        result = []
        for i in range(self._tree.topLevelItemCount()):
            item = self._tree.topLevelItem(i)
            if item.checkState(0) == Qt.CheckState.Checked:
                result.append((int(item.text(2)), int(item.text(3))))
        return result


class SavePage(QWizardPage):
    def __init__(self, parent=None):
        super().__init__(parent)
        self.setTitle("Save Netlist")
        self.setSubTitle("Choose a filename and net naming prefix")

        layout = QVBoxLayout(self)

        form = QHBoxLayout()
        form.addWidget(QLabel("Net name prefix:"))
        self._edit_prefix = QLineEdit("WIRE_")
        form.addWidget(self._edit_prefix)
        layout.addLayout(form)

        file_row = QHBoxLayout()
        self._edit_path = QLineEdit()
        self._edit_path.setReadOnly(True)
        self._btn_browse = QPushButton("Browse…")
        file_row.addWidget(QLabel("Save to:"))
        file_row.addWidget(self._edit_path, 1)
        file_row.addWidget(self._btn_browse)
        layout.addLayout(file_row)

        self._btn_browse.clicked.connect(self._on_browse)
        self._edit_path.setText(self._default_path())

        layout.addStretch()

    def _default_path(self) -> str:
        from core import paths
        nets_dir = paths.netlists_dir()
        os.makedirs(nets_dir, exist_ok=True)
        ts = datetime.now().strftime("%Y%m%d")
        return os.path.abspath(os.path.join(nets_dir, f"golden_{ts}.json"))

    def _on_browse(self) -> None:
        path, _ = QFileDialog.getSaveFileName(
            self, "Save Golden Sample Netlist", self._edit_path.text(),
            "JSON (*.json);;All files (*)"
        )
        if path:
            if not path.lower().endswith(".json"):
                path += ".json"
            self._edit_path.setText(path)

    def net_name_prefix(self) -> str:
        return self._edit_prefix.text().strip() or "WIRE_"

    def save_path(self) -> str:
        return self._edit_path.text().strip()
