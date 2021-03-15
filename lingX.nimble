version       = "0.1.4"
author        = "Sheldon"
description   = "Deduplicated and Decentralized File system"
license       = "MIT"
skipDirs      = @["go-libp2p-daemon", "libp2p", "wNim","lingX_arc_x86_64","."]
skipFiles     = @["key","bootstrapNode","clientNode","lingX_arc_x86_64.rar"]
skipExt       = @["exe","json","dll","md","nim","nims"]

requires "nim >= 1.2.8", "winim >= 3.6.0", "chronos >= 2.5.2", "nimcrypto >= 0.5.4", "chronicles >= 0.10.0", "secp256k1 >= 0.5.1", "bearssl >= 0.1.5", "faststreams >= 0.2.0"
