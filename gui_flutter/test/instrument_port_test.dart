import 'package:flutter_test/flutter_test.dart';
import 'package:ht_mk1_gui/htproto/serial_transport.dart';

void main() {
  group('isInstrumentPort (--serial auto)', () {
    test('MCP2221A USB-UART is recognised by Microchip vendor id', () {
      // Windows names the MCP2221A "USB Serial Device", so the VID is what
      // identifies it.
      expect(isInstrumentPort(const PortInfo('COM5', 'USB Serial Device', 0x04D8)),
          isTrue);
    });

    test('MCP2221A is recognised by description when no vendor id is reported',
        () {
      expect(
          isInstrumentPort(const PortInfo('/dev/ttyACM0', 'MCP2221 USB Serial Port Emulator')),
          isTrue);
    });

    test('Nucleo ST-LINK VCP is still recognised', () {
      expect(isInstrumentPort(const PortInfo('COM7', 'STMicroelectronics STLink Virtual COM Port')),
          isTrue);
      expect(isInstrumentPort(const PortInfo('COM8', 'anything', 0x0483)), isTrue);
    });

    test('an unrelated serial adapter is not picked', () {
      expect(isInstrumentPort(const PortInfo('COM3', 'Prolific USB-to-Serial', 0x067B)),
          isFalse);
      expect(isInstrumentPort(const PortInfo('COM1', 'Communications Port')),
          isFalse);
    });
  });
}
