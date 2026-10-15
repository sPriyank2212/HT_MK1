# tools/

## `7zsd_LZMA2_x64.sfx`

The self-extracting stub `build_exe.cmd` prepends to the packaged app.

It comes from **7-Zip SFX-Modified** (<https://github.com/chrislake/7zsfxmm>),
release 1.7.1.3901, file `7zsd_extra_171_3901.7z`. LGPL — see the project for
the full licence and sources.

It is vendored rather than downloaded at build time so a build is reproducible
without network access, and so the packaging cannot silently change under a new
upstream release.

### Why not the stock 7-Zip module

7-Zip ships `7z.sfx` and `7zCon.sfx`, both extract-only: they ask the user for a
destination and stop. Running the app afterwards needs the `RunProgram` config
key, which only the installer-style modules support. Those used to live in
`7zXXXX-extra.7z`, but current releases (checked at 26.02) no longer include
them — hence the third-party module.

### Why an SFX at all

Flutter Windows has no one-file mode. `HT_MK1_GUI.exe` from
`flutter build windows --release` is a ~90 KB launcher; the app is
`flutter_windows.dll` (~20 MB) plus `data\app.so`, and the `data\` tree has to
keep its layout. Anything claiming to be a single file has to unpack somewhere
first.

If a portable single file is not actually needed, ship
`build\windows\x64\runner\Release\` as a folder or a zip instead — it is the
same bits, launches instantly, and needs none of this.
