# Package

version       = "0.11.0"
author        = "Wesley Kerfoot"
description   = "Turn Your Tweets Into Blog Posts"
license       = "MIT"
srcDir        = "src"
installExt    = @["nim"]
bin           = @["game"]

# Dependencies
requires "nim >= 1.0"
requires "https://github.com/GULPF/timezones"
requires "https://github.com/cheatfate/nimcrypto"

task bookmark, "Builds the minified bookmarklet":
  "echo -n 'javascript:' > ./bookmarklet.min.js".exec
  "uglifyjs bookmarklet.js >> ./bookmarklet.min.js".exec
