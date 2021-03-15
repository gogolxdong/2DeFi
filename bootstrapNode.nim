import chronos, nimcrypto, strutils,os, sequtils,json, tables,sets
import strformat, posix

import libp2p/daemon/daemonapi
import libp2p/daemon/transpool
import system/ansi_c
import i18n
import terminal

const
  ChatProtocol = "/lingX-chat-stream"
  RequestProtocol = "/lingX-request-stream"
  SendProtocol = "/lingX-send-stream"
  LikeProtocol = "/lingX-like-stream"

  ServerProtocols = @[ChatProtocol,RequestProtocol,SendProtocol,LikeProtocol]

var tempDir = getTempDir()

type
  CustomData = ref object
    api: DaemonAPI
    remotes: OrderedTable[string, OrderedTable[string,P2PStream]]
    consoleFd: AsyncFD

var data = new CustomData

var stop = false

var messageChan: Channel[string]
messageChan.open()

const ip4DNS = "114.114.114.114"
var ip4 = getPrimaryIPAddr(parseIpAddress(ip4DNS))
var multiTCPAddr4 = MultiAddress.init(strformat.`&`"/ip4/{ip4}/tcp/5001").get()
var multiUDPAddr4 = MultiAddress.init(strformat.`&`"/ip4/{ip4}/udp/5001/quic").get()
var hostAddresses: seq[MultiAddress] = @[multiTCPAddr4, multiUDPAddr4]

try:
  const aliIp6DNS = "2400:3200::1"
  var ip6 = getPrimaryIPAddr(parseIpAddress(aliIp6DNS))
  var multiTCPAddr6 = MultiAddress.init(strformat.`&`"/ip6/{ip6}/tcp/5001").get()
  hostAddresses.add multiTCPAddr6
  var multiUDPAddr6 = MultiAddress.init(strformat.`&`"/ip6/{ip6}/udp/5001/quic").get()
  hostAddresses.add multiUDPAddr6
except:
  echo getCurrentExceptionMsg()
when defined(windows):
  const daemon = "p2pd.exe"
else:
  const daemon = "./p2pd"

var peerDomainTable: OrderedTable[string,string]
var domainPeerTable: OrderedTable[string,string]

var domain = config["domain"].getStr
if domain == "":
  echo "Please create a domain"
  if domain != "":
    config["domain"] = %domain

template getPeerId(domain:string): untyped =
  if domainPeerTable.hasKey(parts[1]):
      domainPeerTable[parts[1]]
  elif parts[1].len == 46 or parts[1].len == 52: 
    parts[1] 
  else: continue
  

if not fileExists("key"):
  var rng = newRng()
  var keyPair = KeyPair.random(PKScheme.Ed25519, rng[]).get()
  var privKey = keyPair.secKey.edkey.data
  var buf = initProtoBuffer()
  buf.write(1, 1.uint)
  buf.write(2, privKey)
  buf.finish()
  writeFile("key", buf.toOpenArray)

data.api = waitFor newDaemonApi(flags = {DHTServer, PSGossipSub, AutoRelay, RelayHop}, id="key",
  daemon = daemon, patternSock="/unix/tmp/p2pd.sock",hostAddresses=hostAddresses)

var id = $(waitFor data.api.identity()).peer
if config["id"].getStr != id:
  config["id"] = % $id
  writeFile("config.json", $config)

proc status() {.async.} =
  {.gcsafe.}:
    var domains: HashSet[string]
    while true:
      if stop: break
      var peers = await data.api.listPeers()
      for info in peers:
        domains.incl info.domain
      c_printf "\r" & $peers.len & "nodes connected:" & $domains
      await sleepAsync(1000)

#处理Ctrl+C信号
var sa: Sigaction
{.push stackTrace: off.}
proc sigTernimalHandler(sig: cint, y: ptr SigInfo, z: pointer) {.noconv.} =
  var exception = getCurrentExceptionMsg()
  styledWriteLine(stderr, fgRed, "正在关闭", resetStyle, exception)
  stop = true
  waitFor data.api.close()
  quit(1)
{.pop.}
discard sigemptyset(sa.sa_mask)
sa.sa_sigaction = sigTernimalHandler
sa.sa_flags = SA_SIGINFO or SA_NODEFER
discard sigaction(posix.SIGINT, sa)

waitFor status()
