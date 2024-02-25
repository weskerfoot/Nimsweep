# Package

version       = "0.11.0"
author        = "Wesley Kerfoot"
description   = "Minesweeper"
license       = "MIT"
srcDir        = "src"
installExt    = @["nim"]
bin           = @["game"]

# Dependencies
requires "nim >= 1.0"
requires "https://github.com/GULPF/timezones"
requires "https://github.com/cheatfate/nimcrypto"
