# Third-Party Notices

## Qt6

Calc-U-59's Qt6 desktop app (`Qt6/`, the Windows and Linux builds) is built on
[Qt6](https://www.qt.io/), (c) The Qt Company Ltd and other contributors. It
uses the Qt Widgets module and its dependencies (QtCore, QtGui and the
platform-integration plugins).

Qt6 is used under the **GNU Lesser General Public License, version 3**
(LGPLv3) — see [licenses/LGPL-3.0.txt](licenses/LGPL-3.0.txt), which
incorporates the [GNU General Public License, version 3](licenses/GPL-3.0.txt)
by reference. Qt is linked dynamically (shared libraries) and unmodified.

Complete corresponding source for the Qt6 version used in each release is
available free of charge from The Qt Company:

- <https://www.qt.io/download-open-source>
- <https://download.qt.io/official_releases/qt/>

The builds published by this project's CI record the exact Qt version in the
GitHub Actions run log (`.github/workflows/build.yml`).

The Swift app for macOS and iOS does not use Qt.

## ROM images

The ROM images under `roms/` are third-party copyrighted firmware belonging
to Texas Instruments. They are **not** covered by this project's GPLv3
license — see [LICENSE](LICENSE) for Calc-U-59's own code, and treat
`roms/` as a separate, unlicensed-by-us inclusion.
