"""Netlist Editor dialog — create and edit JSON netlists."""

from __future__ import annotations

import copy
import os
from pathlib import Path

from PyQt6.QtCore import Qt
from PyQt6.QtGui import QKeySequence, QShortcut
from PyQt6.QtWidgets import (
    QDialog, QVBoxLayout, QHBoxLayout, QSplitter,
    QTreeWidget, QTreeWidgetItem, QPushButton,
    QLabel, QLineEdit, QSpinBox, QDoubleSpinBox,
    QCheckBox, QFileDialog, QMessageBox, QWidget,
    QFormLayout, QGroupBox, QTextEdit,
)

from core.netlist import Net, NetPin, Netlist, load_netlist, save_netlist, validate_netlist


class NetlistEditorDialog(QDialog):
    """Modal dialog for editing a Harness Tester netlist."""

    def __init__(self, parent=None, netlist: Netlist | None = None, path: str = ""):
        super().__init__(parent)
        self._original = netlist or Netlist()
        self._netlist = copy.deepcopy(self._original)
        self._path = path
        self._current_item: QTreeWidgetItem | None = None

        self.setWindowTitle("Netlist Editor")
        self.setMinimumSize(760, 520)
        self._build_ui()
        self._populate_tree()
        self._update_title()

    # ------------------------------------------------------------------
    # UI construction
    # ------------------------------------------------------------------

    def _build_ui(self) -> None:
        layout = QVBoxLayout(self)

        # Toolbar
        toolbar = QHBoxLayout()
        self._btn_new = QPushButton("New")
        self._btn_open = QPushButton("Open…")
        self._btn_save = QPushButton("Save")
        self._btn_save_as = QPushButton("Save As…")
        self._btn_validate = QPushButton("Validate")
        for btn in (self._btn_new, self._btn_open, self._btn_save,
                    self._btn_save_as, self._btn_validate):
            toolbar.addWidget(btn)
        toolbar.addStretch()
        layout.addLayout(toolbar)

        self._btn_new.clicked.connect(self._on_new)
        self._btn_open.clicked.connect(self._on_open)
        self._btn_save.clicked.connect(self._on_save)
        self._btn_save_as.clicked.connect(self._on_save_as)
        self._btn_validate.clicked.connect(self._on_validate)

        # Splitter: tree | editor
        splitter = QSplitter(Qt.Orientation.Horizontal)

        # Left: tree + add/remove buttons
        left = QWidget()
        left_layout = QVBoxLayout(left)
        left_layout.setContentsMargins(0, 0, 0, 0)

        self._tree = QTreeWidget()
        self._tree.setHeaderLabel("Nets and Pins")
        self._tree.setSelectionMode(QTreeWidget.SelectionMode.SingleSelection)
        self._tree.currentItemChanged.connect(self._on_tree_selection_changed)
        left_layout.addWidget(self._tree)

        tree_btns = QHBoxLayout()
        self._btn_add_net = QPushButton("+ Net")
        self._btn_add_pin = QPushButton("+ Pin")
        self._btn_remove = QPushButton("− Remove")
        tree_btns.addWidget(self._btn_add_net)
        tree_btns.addWidget(self._btn_add_pin)
        tree_btns.addWidget(self._btn_remove)
        left_layout.addLayout(tree_btns)

        self._btn_add_net.clicked.connect(self._on_add_net)
        self._btn_add_pin.clicked.connect(self._on_add_pin)
        self._btn_remove.clicked.connect(self._on_remove)

        splitter.addWidget(left)

        # Right: properties editor
        right = QWidget()
        right_layout = QVBoxLayout(right)
        right_layout.setContentsMargins(0, 0, 0, 0)

        # Netlist-level fields
        netlist_group = QGroupBox("Netlist")
        netlist_form = QFormLayout(netlist_group)
        self._edit_harness_id = QLineEdit()
        netlist_form.addRow("Harness ID:", self._edit_harness_id)
        right_layout.addWidget(netlist_group)

        # Net-level fields
        net_group = QGroupBox("Net Properties")
        net_form = QFormLayout(net_group)
        self._edit_net_name = QLineEdit()
        self._edit_net_name.textChanged.connect(self._on_field_changed)
        net_form.addRow("Name:", self._edit_net_name)

        self._edit_connector_id = QLineEdit()
        self._edit_connector_id.textChanged.connect(self._on_field_changed)
        net_form.addRow("Source Conn ID:", self._edit_connector_id)

        self._edit_connector_id_b = QLineEdit()
        self._edit_connector_id_b.textChanged.connect(self._on_field_changed)
        net_form.addRow("Dest Conn ID:", self._edit_connector_id_b)

        self._edit_connector_detail = QLineEdit()
        self._edit_connector_detail.textChanged.connect(self._on_field_changed)
        net_form.addRow("Connector Detail:", self._edit_connector_detail)

        self._edit_connector_part_number = QLineEdit()
        self._edit_connector_part_number.textChanged.connect(self._on_field_changed)
        net_form.addRow("Source Part #:", self._edit_connector_part_number)

        self._edit_connector_part_number_b = QLineEdit()
        self._edit_connector_part_number_b.textChanged.connect(self._on_field_changed)
        net_form.addRow("Dest Part #:", self._edit_connector_part_number_b)

        self._edit_wire_colour = QLineEdit()
        self._edit_wire_colour.textChanged.connect(self._on_field_changed)
        net_form.addRow("Colour:", self._edit_wire_colour)

        self._edit_awg = QLineEdit()
        self._edit_awg.textChanged.connect(self._on_field_changed)
        net_form.addRow("AWG:", self._edit_awg)

        self._edit_length = QLineEdit()
        self._edit_length.textChanged.connect(self._on_field_changed)
        net_form.addRow("Length:", self._edit_length)

        self._edit_harness_no = QLineEdit()
        self._edit_harness_no.textChanged.connect(self._on_field_changed)
        net_form.addRow("Harness No:", self._edit_harness_no)

        self._edit_source = QLineEdit()
        self._edit_source.textChanged.connect(self._on_field_changed)
        net_form.addRow("Source:", self._edit_source)

        self._edit_destination = QLineEdit()
        self._edit_destination.textChanged.connect(self._on_field_changed)
        net_form.addRow("Destination:", self._edit_destination)

        self._spin_r_min = QDoubleSpinBox()
        self._spin_r_min.setRange(0, 99999)
        self._spin_r_min.valueChanged.connect(self._on_field_changed)
        net_form.addRow("R Min (mΩ):", self._spin_r_min)

        self._spin_r_max = QDoubleSpinBox()
        self._spin_r_max.setRange(0, 99999)
        self._spin_r_max.valueChanged.connect(self._on_field_changed)
        net_form.addRow("R Max (mΩ):", self._spin_r_max)

        self._chk_hv = QCheckBox("Enable HV insulation test")
        self._chk_hv.stateChanged.connect(self._on_field_changed)
        net_form.addRow(self._chk_hv)

        self._spin_hv_v = QSpinBox()
        self._spin_hv_v.setRange(100, 1000)
        self._spin_hv_v.valueChanged.connect(self._on_field_changed)
        net_form.addRow("HV Voltage (V):", self._spin_hv_v)

        self._spin_hv_soak = QSpinBox()
        self._spin_hv_soak.setRange(100, 60000)
        self._spin_hv_soak.valueChanged.connect(self._on_field_changed)
        net_form.addRow("HV Soak (ms):", self._spin_hv_soak)

        self._spin_hv_ir = QDoubleSpinBox()
        self._spin_hv_ir.setRange(0, 999999)
        self._spin_hv_ir.valueChanged.connect(self._on_field_changed)
        net_form.addRow("HV Min IR (MΩ):", self._spin_hv_ir)

        right_layout.addWidget(net_group)

        # Pin-level fields
        pin_group = QGroupBox("Pin Properties")
        pin_form = QFormLayout(pin_group)
        self._spin_pin_num = QSpinBox()
        self._spin_pin_num.setRange(1, 256)
        self._spin_pin_num.valueChanged.connect(self._on_field_changed)
        pin_form.addRow("Pin Number:", self._spin_pin_num)

        self._edit_pin_name = QLineEdit()
        self._edit_pin_name.textChanged.connect(self._on_field_changed)
        pin_form.addRow("Pin Label:", self._edit_pin_name)

        right_layout.addWidget(pin_group)

        # Validation output
        self._lbl_status = QLabel("Ready")
        self._lbl_status.setStyleSheet("color: #888;")
        right_layout.addWidget(self._lbl_status)

        splitter.addWidget(right)
        splitter.setSizes([280, 460])
        layout.addWidget(splitter)

        # Shortcuts
        QShortcut(QKeySequence("Ctrl+S"), self).activated.connect(self._on_save)

        self._update_editor_enabled()

    # ------------------------------------------------------------------
    # Data model helpers
    # ------------------------------------------------------------------

    def _item_type(self, item: QTreeWidgetItem | None) -> str:
        if item is None:
            return "none"
        data = item.data(0, Qt.ItemDataRole.UserRole)
        if data is None:
            return "none"
        return data.get("type", "none")

    def _item_index(self, item: QTreeWidgetItem | None) -> int:
        if item is None:
            return -1
        data = item.data(0, Qt.ItemDataRole.UserRole)
        if data is None:
            return -1
        return data.get("index", -1)

    def _item_pin_index(self, item: QTreeWidgetItem | None) -> int:
        data = item.data(0, Qt.ItemDataRole.UserRole) if item else None
        return data.get("pin_index", -1) if data else -1

    # ------------------------------------------------------------------
    # Populate / sync
    # ------------------------------------------------------------------

    def _update_title(self) -> None:
        name = Path(self._path).name if self._path else "Untitled"
        self.setWindowTitle(f"Netlist Editor — {name}")

    def _populate_tree(self) -> None:
        self._tree.clear()
        self._edit_harness_id.setText(self._netlist.harness_id)

        for i, net in enumerate(self._netlist.nets):
            net_item = QTreeWidgetItem([net.name or f"NET {i + 1}"])
            net_item.setData(0, Qt.ItemDataRole.UserRole, {"type": "net", "index": i})
            for j, pin in enumerate(net.pins):
                pin_item = QTreeWidgetItem([f"Pin {pin.number}" + (f" — {pin.name}" if pin.name else "")])
                pin_item.setData(0, Qt.ItemDataRole.UserRole,
                                 {"type": "pin", "index": i, "pin_index": j})
                net_item.addChild(pin_item)
            self._tree.addTopLevelItem(net_item)
            net_item.setExpanded(True)

    def _sync_netlist_from_fields(self) -> None:
        self._netlist.harness_id = self._edit_harness_id.text().strip()

        item = self._current_item
        itype = self._item_type(item)

        if itype == "net":
            net = self._netlist.nets[self._item_index(item)]
            net.name = self._edit_net_name.text().strip()
            net.connector_id = self._edit_connector_id.text().strip()
            net.connector_id_b = self._edit_connector_id_b.text().strip()
            net.connector_detail = self._edit_connector_detail.text().strip()
            net.connector_part_number = self._edit_connector_part_number.text().strip()
            net.connector_part_number_b = self._edit_connector_part_number_b.text().strip()
            net.wire_colour = self._edit_wire_colour.text().strip()
            net.awg = self._edit_awg.text().strip()
            net.length = self._edit_length.text().strip()
            net.harness_no = self._edit_harness_no.text().strip()
            net.source = self._edit_source.text().strip()
            net.destination = self._edit_destination.text().strip()
            net.r_min_mohm = self._spin_r_min.value()
            net.r_max_mohm = self._spin_r_max.value()
            net.hv_enabled = self._chk_hv.isChecked()
            net.hv_voltage_v = self._spin_hv_v.value()
            net.hv_soak_ms = self._spin_hv_soak.value()
            net.hv_min_ir_mohm = self._spin_hv_ir.value()
            item.setText(0, net.name or "(unnamed net)")

        elif itype == "pin":
            net = self._netlist.nets[self._item_index(item)]
            pin = net.pins[self._item_pin_index(item)]
            pin.number = self._spin_pin_num.value()
            pin.name = self._edit_pin_name.text().strip()
            item.setText(0, f"Pin {pin.number}" + (f" — {pin.name}" if pin.name else ""))

    def _on_tree_selection_changed(self) -> None:
        # Save previous selection first
        self._sync_netlist_from_fields()
        self._current_item = self._tree.currentItem()
        self._load_fields_for_selection()
        self._update_editor_enabled()

    def _load_fields_for_selection(self) -> None:
        item = self._current_item
        itype = self._item_type(item)

        if itype == "net":
            net = self._netlist.nets[self._item_index(item)]
            self._edit_net_name.setText(net.name)
            self._edit_connector_id.setText(net.connector_id)
            self._edit_connector_id_b.setText(net.connector_id_b)
            self._edit_connector_detail.setText(net.connector_detail)
            self._edit_connector_part_number.setText(net.connector_part_number)
            self._edit_connector_part_number_b.setText(net.connector_part_number_b)
            self._edit_wire_colour.setText(net.wire_colour)
            self._edit_awg.setText(net.awg)
            self._edit_length.setText(net.length)
            self._edit_harness_no.setText(net.harness_no)
            self._edit_source.setText(net.source)
            self._edit_destination.setText(net.destination)
            self._spin_r_min.setValue(net.r_min_mohm)
            self._spin_r_max.setValue(net.r_max_mohm)
            self._chk_hv.setChecked(net.hv_enabled)
            self._spin_hv_v.setValue(net.hv_voltage_v)
            self._spin_hv_soak.setValue(net.hv_soak_ms)
            self._spin_hv_ir.setValue(net.hv_min_ir_mohm)
        elif itype == "pin":
            net = self._netlist.nets[self._item_index(item)]
            pin = net.pins[self._item_pin_index(item)]
            self._spin_pin_num.setValue(pin.number)
            self._edit_pin_name.setText(pin.name)

    def _update_editor_enabled(self) -> None:
        itype = self._item_type(self._current_item)
        net_enabled = itype == "net"
        pin_enabled = itype == "pin"

        self._edit_net_name.setEnabled(net_enabled)
        self._edit_connector_id.setEnabled(net_enabled)
        self._edit_connector_id_b.setEnabled(net_enabled)
        self._edit_connector_detail.setEnabled(net_enabled)
        self._edit_connector_part_number.setEnabled(net_enabled)
        self._edit_connector_part_number_b.setEnabled(net_enabled)
        for w in (self._edit_wire_colour, self._edit_awg,
                  self._edit_length, self._edit_harness_no):
            w.setEnabled(net_enabled)
        self._edit_source.setEnabled(net_enabled)
        self._edit_destination.setEnabled(net_enabled)
        self._spin_r_min.setEnabled(net_enabled)
        self._spin_r_max.setEnabled(net_enabled)
        self._chk_hv.setEnabled(net_enabled)
        self._spin_hv_v.setEnabled(net_enabled)
        self._spin_hv_soak.setEnabled(net_enabled)
        self._spin_hv_ir.setEnabled(net_enabled)

        self._spin_pin_num.setEnabled(pin_enabled)
        self._edit_pin_name.setEnabled(pin_enabled)

        if not net_enabled and not pin_enabled:
            for w in (self._edit_net_name, self._edit_connector_id,
                      self._edit_connector_id_b,
                      self._edit_connector_detail,
                      self._edit_connector_part_number,
                      self._edit_connector_part_number_b,
                      self._edit_wire_colour, self._edit_awg,
                      self._edit_length, self._edit_harness_no,
                      self._edit_source,
                      self._edit_destination, self._edit_pin_name):
                w.clear()
            self._spin_r_min.setValue(0)
            self._spin_r_max.setValue(500)
            self._chk_hv.setChecked(False)
            self._spin_hv_v.setValue(500)
            self._spin_hv_soak.setValue(1000)
            self._spin_hv_ir.setValue(100)
            self._spin_pin_num.setValue(1)

    def _on_field_changed(self) -> None:
        self._sync_netlist_from_fields()

    # ------------------------------------------------------------------
    # Tree mutations
    # ------------------------------------------------------------------

    def _on_add_net(self) -> None:
        self._sync_netlist_from_fields()
        name = f"NET_{len(self._netlist.nets) + 1}"
        net = Net(name=name, pins=[NetPin(1), NetPin(2)])
        self._netlist.nets.append(net)

        net_item = QTreeWidgetItem([name])
        idx = len(self._netlist.nets) - 1
        net_item.setData(0, Qt.ItemDataRole.UserRole, {"type": "net", "index": idx})
        for j, pin in enumerate(net.pins):
            pin_item = QTreeWidgetItem([f"Pin {pin.number}"])
            pin_item.setData(0, Qt.ItemDataRole.UserRole,
                             {"type": "pin", "index": idx, "pin_index": j})
            net_item.addChild(pin_item)
        self._tree.addTopLevelItem(net_item)
        net_item.setExpanded(True)
        self._tree.setCurrentItem(net_item)

    def _on_add_pin(self) -> None:
        item = self._tree.currentItem()
        if self._item_type(item) == "pin":
            item = item.parent()
        if self._item_type(item) != "net":
            QMessageBox.information(self, "Select Net", "Select a net to add a pin to.")
            return

        self._sync_netlist_from_fields()
        net_idx = self._item_index(item)
        net = self._netlist.nets[net_idx]
        # Pick next unused pin number in this net
        used = {p.number for p in net.pins}
        new_num = 1
        while new_num in used and new_num <= 256:
            new_num += 1
        pin = NetPin(new_num)
        net.pins.append(pin)

        pin_item = QTreeWidgetItem([f"Pin {pin.number}"])
        pin_item.setData(0, Qt.ItemDataRole.UserRole,
                         {"type": "pin", "index": net_idx, "pin_index": len(net.pins) - 1})
        item.addChild(pin_item)
        item.setExpanded(True)
        self._tree.setCurrentItem(pin_item)

    def _on_remove(self) -> None:
        item = self._tree.currentItem()
        itype = self._item_type(item)
        if itype == "net":
            idx = self._item_index(item)
            del self._netlist.nets[idx]
        elif itype == "pin":
            net_idx = self._item_index(item)
            pin_idx = self._item_pin_index(item)
            del self._netlist.nets[net_idx].pins[pin_idx]
        else:
            return

        # Rebuild tree because indices changed
        current = self._current_item
        self._populate_tree()
        self._current_item = None
        self._tree.setCurrentItem(None)
        self._update_editor_enabled()

    # ------------------------------------------------------------------
    # Persistence
    # ------------------------------------------------------------------

    def _on_new(self) -> None:
        self._netlist = Netlist()
        self._path = ""
        self._populate_tree()
        self._update_title()
        self._lbl_status.setText("New netlist created")
        self._lbl_status.setStyleSheet("color: #888;")

    def _on_open(self) -> None:
        path, _ = QFileDialog.getOpenFileName(
            self, "Open Netlist", "",
            "Netlist files (*.json *.xlsx *.csv);;JSON (*.json);;All files (*)"
        )
        if not path:
            return
        try:
            self._netlist = load_netlist(path)
            self._path = path
            self._populate_tree()
            self._update_title()
            self._lbl_status.setText("Netlist loaded")
            self._lbl_status.setStyleSheet("color: #28a745;")
        except Exception as exc:
            QMessageBox.critical(self, "Open Error", str(exc))

    def _on_save(self) -> None:
        self._sync_netlist_from_fields()
        if not self._path:
            self._on_save_as()
            return
        self._do_save(self._path)

    def _on_save_as(self) -> None:
        self._sync_netlist_from_fields()
        default = self._path or "netlist.json"
        path, _ = QFileDialog.getSaveFileName(
            self, "Save Netlist", default,
            "JSON (*.json);;All files (*)"
        )
        if not path:
            return
        if not path.lower().endswith(".json"):
            path += ".json"
        if self._do_save(path):
            self._path = path
            self._update_title()

    def _do_save(self, path: str) -> bool:
        errors = validate_netlist(self._netlist)
        if errors:
            QMessageBox.warning(self, "Validation Failed", "\n".join(errors))
            self._lbl_status.setText("Validation failed")
            self._lbl_status.setStyleSheet("color: #dc3545;")
            return False
        try:
            save_netlist(self._netlist, path)
            self._lbl_status.setText(f"Saved: {Path(path).name}")
            self._lbl_status.setStyleSheet("color: #28a745;")
            return True
        except OSError as exc:
            QMessageBox.critical(self, "Save Error", str(exc))
            return False

    def _on_validate(self) -> None:
        self._sync_netlist_from_fields()
        errors = validate_netlist(self._netlist)
        if errors:
            QMessageBox.warning(self, "Validation Issues", "\n".join(errors))
            self._lbl_status.setText(f"Validation failed: {len(errors)} issue(s)")
            self._lbl_status.setStyleSheet("color: #dc3545;")
        else:
            QMessageBox.information(self, "Validation OK", "Netlist is valid.")
            self._lbl_status.setText("Netlist is valid")
            self._lbl_status.setStyleSheet("color: #28a745;")

    def netlist_path(self) -> str:
        """Return the path of the saved netlist, or empty if not saved."""
        return self._path

    def netlist(self) -> Netlist:
        """Return the edited netlist."""
        return self._netlist
