# The Shared I2C Bus, and How the Card-Enable Lines Fix It

Plain-English write-up of a hardware finding from 2026-08-11 and the firmware fix that went with
it. See the diagram at the top of this session's artifact link for the picture version of the
same thing. Related: `PROJECT_LOG.md` HW-12, HW-15 (HW-09 is superseded by it).

## 1. The problem, in one sentence

The Matrix Card and every HV card use the same eight I2C addresses (0x20–0x27) for their internal
chips, and they can end up on the same physical bus — so if two of them are switched on at the
same time, they both try to answer the same message.

## 2. Why that's true

Every "card" in this instrument — the Matrix Card, and each of up to four HV cards — has its own
set of small chips (MCP23017 GPIO expanders, mostly) that drive relays or multiplexers. Every one
of those chips is wired up the same way: its address is set by three strap pins (A0/A1/A2), and
every card uses the same straps, 0–7, giving the same eight I2C addresses, 0x20 through 0x27.

That's completely normal *if* each card is the only thing plugged into its own private wire pair.
But on this board, the Control Card's isolated I2C bus (I2C2) is wired out to all four HV card
connectors (J1–J4) as one shared set of wires, not four separate ones. So if two cards are
switched on together, whichever one is "card A" and whichever is "card B" both hear the same
0x20–0x27 messages and both try to answer. That's a bus collision, not a subtle bug — it corrupts
whichever card's expander wasn't meant to be talked to.

## 3. What stops that from happening: the enable lines

Each HV card slot has its own dedicated on/off line — `HV_Card_EN1`, `EN2`, `EN3`, `EN4` — one per
connector (J1–J4). These come from four plain MCU pins (PC5, PC6, PA10, PA9), each going through
its own isolator chip before reaching the card. Think of it as a gate on each card's segment of
the bus: when a card's EN line is off (the default), that card's chips are cut off from the shared
bus and can't answer anything, no matter what address is on the wire. When its EN line is turned
on, and *only* that one card's EN line is on, its chips are the only ones that can hear or answer.

So the rule the firmware now follows is simple: **before talking to any HV card's relay chips,
turn on that one card's EN line and make sure it's the only one on; turn it back off the moment
you're done.**

The Matrix Card doesn't have an EN line of its own — its chips are wired straight onto the shared
bus with no gate. That's fine as long as no HV card's EN line is on while the Matrix Card is being
talked to, which the firmware now guarantees by keeping every HV card's EN line off except for the
brief moment it's actually being used.

## 4. What was actually broken before this fix

Nothing in the firmware ever touched the four EN pins. CubeMX (the tool that generates the pin
setup code) still had them wired up under an old name (`HV_CARD_DT_3_0`, `_3_1`, `_4_0`, `_4_1`)
left over from an earlier version of the schematic, configured as plain, unused *inputs* — not
outputs, and not connected to anything in the driver code at all. So even with just one real HV
card plugged in, if firmware ever tried to talk to it while the Matrix Card was also doing
something, the two would have collided on the bus, with no code anywhere preventing it.

## 5. What changed, in plain terms

- **The four pins got their real names back and were switched to outputs.** They're now called
  `HV_CARD_EN1`–`EN4` everywhere (the `.ioc` project file, `main.h`, and `gpio.c`), configured as
  outputs that start off (disabled) at boot — matching how every other "keep this off until we
  need it" line in this codebase already works.
- **`hv_card.c` now turns a card's EN line on right before touching its relay chips, and off
  again right after** — for every operation that does so: bringing the card up at startup,
  opening every relay, and closing a single relay on either side. Every one of those returns
  through the same "turn it back off" step even if something went wrong partway through, so a
  card is never left switched onto the bus by accident.
- **Board index maps to the physical connector.** *(Superseded 2026-11-13 — see §7.)* This originally put the
  first HV card on J2/`EN2`, treating J1 as the Matrix Card's alone. The hardware owner has since decided that
  **J1 is shared by the Matrix Card and HV card 1**, so HV card N is on J*N*/`EN`*N* and up to four cards fit.

## 6. The Matrix Card turned out to be on the same bus too

Section 6 originally flagged this as unconfirmed. It's since been confirmed directly: the Matrix
Card's own onboard chips (the ones that drive its multiplexers and read its ADC) are on the same
shared bus as HV Card 1. The one thing that stays separate is the single chip on the Control Card
that generates the mux-select signals sent out to the Matrix Card (U21/U20) — that one really is
on its own bus (I2C3) and never shares an address with anything, so it needed no change.

That meant fixing one more thing: the Matrix Card has its *own*, smaller version of the exact
same problem, one level in. It has nine chips of its own but only eight addresses to give them, so
it already reuses the same eight addresses twice — once for the chips that do "force" routing,
once for the chips that do "sense" routing plus its ADC — switching between the two internally.
That inner switch already existed before this session. What was missing was the *outer* switch:
nothing stopped the Matrix Card's chips (either half) from answering at the same time as an HV
card's chips, because the Matrix Card had no on/off line of its own onto the shared bus. It uses
`HV_Card_EN1` for that now — the same kind of line each HV card uses, just for the connector (J1)
that turned out to be the Matrix Card's own.

So the full picture, four cards deep: turn on `HV_Card_EN1` (and only that line) to reach the
Matrix Card; while it's on, its own internal switch picks force-routing chips or sense-routing
chips; turn `HV_Card_EN1` back off before letting any HV card's line come on.

## 7. Where to look in the code

| What | File |
|---|---|
| Per-HV-card enable pin, added to the card's config | `Core/Inc/cards/hv_card.h` |
| The HV card's "turn on, do the I2C work, turn off" logic | `Core/Src/cards/hv_card.c` (`hv_bus_claim`/`hv_bus_release`) |
| The Matrix Card's own version of the same claim/release | `Core/Inc/cards/matrix_card.h`, `Core/Src/cards/matrix_card.c` (`MatrixCard_BusClaim`/`BusRelease`) |
| Which physical pin is which card's enable line, and the split I2C3 (U21 only) vs I2C2 (everything else) bus assignment | `Core/Src/bsp/board.c` |
| The pins themselves, renamed and switched to outputs | `Core/Inc/main.h`, `Core/Src/gpio.c`, `HT_MK1.ioc` |

## 7. HV card 1 shares EN1 with the Matrix Card (HW-15, decided 2026-11-13)

**The mapping.** Control Card J1 (the Matrix Card's J101) carries both the Matrix Card and HV card 1. HV card 2
is on J2, HV card 3 on J3, HV card 4 on J4. So `HV_Card_EN1` (PC5) gates the Matrix Card **and** HV card 1;
`EN2`/`EN3`/`EN4` (PC6, PA10, PA9) gate HV cards 2, 3, 4.

**Why that needs care.** Both cards strap their expanders to the same 0x20–0x27, so with EN1 high both answer.
Worse, the two cards use the *same bits for opposite meanings*: the Matrix's mux enables are active-low, so its
"all off" word is `0xFFFF`; to an HV relay expander `0xFFFF` means *close all 16 relays*.

**What the firmware does about it.**
- Before it raises EN1 for HV card 1, it switches **both Matrix I2C segments off the shared bus**
  (`MatrixCard_Deselect()`, called through `HvCardCfg_t.pre_enable`, installed automatically for any slot whose
  enable equals the Matrix's). If that fails, EN is not raised and the access fails — it never leaves two cards
  answering the same address. The Matrix re-selects its segment on its next access (every Matrix path claims the
  bus, selects a segment, releases).
- This covers boot (`HvCard_Init`), the idle rail monitor, `BUS SCAN` and every insulation sequence.

**What it cannot do.** While the Matrix is being accessed (EN1 high, one Matrix segment selected), **HV card 1's
expanders are on the bus as well**, because they are gated by the same line. Matrix writes then also reach HV
card 1. This is a property of the wiring, not something the firmware can change. It is checked on the real unit
by BU-17 (`Doc/hardware_test_plan_2026-11-13.md` §2): a known loopback must read the same with and without HV
card 1 fitted. If it does not, HV card 1 needs its own enable line (a harness change); in firmware that is the
one-line slot map in `board_init_hv()`.

**HW-09 (a fifth HV connector)** was only needed while J1 was reserved for the Matrix; with four slots holding
four HV cards it is superseded.
