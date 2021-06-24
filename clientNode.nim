import strformat, strutils, times,json,os, streams, 
      sequtils, sugar, sets, tables, osproc, re, mimetypes, deques
import system/ansi_c
import unicode except strip

import libp2p/daemon/daemonapi
import libp2p/daemon/transpool
import chronos, nimcrypto
import stew/shims/net

import i18n
import os, terminal, posix


when not(compileOption("threads")):
  {.fatal: "Please, compile this program with the --threads:on option!".}

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

var messageChan: Channel[string]
messageChan.open()


type
  MenuID = enum
    idOpen, idExit,idenUS, idzhCN, idGoForward,idGoBack, idCopy, idCheck, idChat, idWatch, idClose, idSend, 
    idCreateHyperlink, idHyperlinkCheck, idHyperlinkRun,idHyperlinkStop, idHyperlinkLike, idCreateChatFrame

type FileState = enum
  Stopped, Running

type FileInfo = ref object
  url*: string
  like*: uint
  state*: FileState

var stop: bool
var consoleString = ""

var peerInfoTable : OrderedTable[string, PeerInfo]
var domainPeerTable : OrderedTable[string,string]

var fileTable = newOrderedTable[string, FileInfo]()

var domain = config["domain"].getStr
while domain == "":
  echo "请输入域名：如Nim中文社区/xxx"
  domain = readLine(stdin)
  if domain.split("/").len < 2:
    echo "格式错误"
    domain.reset
    continue
  config["domain"] = %domain

var topDomain = domain.split("/")[0]
const timeFormat = initTimeFormat("yyyy-MM-dd HH:mm:ss")

template loadHtmlOrRequestOthers() {.dirty.} =
    path = path.replace("ipfs://","")
    var peer = domainPeerTable[path]
    var req = strformat.`&`"/request {peer} {self.mUrl}"
    messageChan.send req

consoleString = fanyi"Domain: " & domain & "\r\n" 
echo consoleString

#如果不存在key文件，则用IPFS当前默认的Ed25519公钥生成
if not fileExists("key"):
  var rng = newRng()
  var keyPair = KeyPair.random(PKScheme.Ed25519, rng[]).get()
  var privKey = keyPair.secKey.edkey.data
  var buf = initProtoBuffer()
  buf.write(1, 1.uint)
  buf.write(2, privKey)
  buf.finish()
  writeFile("key", buf.toOpenArray)

#用ipv4 DNS获取当前的ip地址，并分别监听在tcp/udp 5001端口上
const ip4DNS = "114.114.114.114"
var ip4 = getPrimaryIPAddr(parseIpAddress(ip4DNS))
var multiTCPAddr4 = MultiAddress.init(strformat.`&`"/ip4/{ip4}/tcp/5001").get()
var multiUDPAddr4 = MultiAddress.init(strformat.`&`"/ip4/{ip4}/udp/5001/quic").get()
var hostAddresses: seq[MultiAddress] = @[multiTCPAddr4, multiUDPAddr4]

#尝试获取机器的ipv6地址
try:
  const aliIp6DNS = "2400:3200::1"
  var ip6 = getPrimaryIPAddr(parseIpAddress(aliIp6DNS))
  var multiTCPAddr6 = MultiAddress.init(strformat.`&`"/ip6/{ip6}/tcp/5001").get()
  hostAddresses.add multiTCPAddr6
  var multiUDPAddr6 = MultiAddress.init(strformat.`&`"/ip6/{ip6}/udp/5001/quic").get()
  hostAddresses.add multiUDPAddr6
except:
  discard

#windows
when defined(windows):
  const daemon = "p2pd.exe"
else:
  const daemon = "./p2pd"

#使用config.json文件配置的引导节点
var bootstrapNodes = config["bootstrapNodes"].mapIt(it.getStr)
data.api = waitFor newDaemonApi({DHTFull, PSGossipSub, Bootstrap, AutoRelay}, id="key", 
  bootstrapNodes = bootstrapNodes, daemon=daemon, hostAddresses=hostAddresses)

var id = $(waitFor data.api.identity()).peer
if config["id"].getStr != id:
  config["id"] = % $id
  writeFile("config.json", $config)

var extensions = collect(newSeq):
  for (k,v) in mimes:
    k

template getPeerId(): untyped =
  if domainPeerTable.hasKey(parts[1]):
      domainPeerTable[parts[1]]
  elif parts[1].len == 46 or parts[1].len == 52: 
    parts[1] 
  else: continue

proc callback(api: DaemonAPI,ticket: PubsubTicket,message: PubSubMessage): Future[bool] = 
  {.gcsafe.}:
    result = newFuture[bool]()
    var data = cast[string](message.data)
    if data.contains("/"):
      var file = data
      echo "\r\n" 
      if not fileTable.hasKey(file):
        var (path,name,ext) = splitFile(file)
        fileTable[file] = FileInfo(url:file , like:0 , state: Stopped)
    result.complete true

template getLatencyAndUnit(): untyped {.dirty.} =
  var unitLatency = int info.latency div 1000_000
  var unit = "ms"
  if unitLatency in 0..1:
    unitLatency = int info.latency div 1000
    unit = "us"
  if unitLatency in 0..1:
    unitLatency = int info.latency
    unit = "ns"

proc status() {.async.} = 
  {.gcsafe.}:
    proc streamHandler(api: DaemonAPI, stream: P2PStream) {.async.} =
      {.gcsafe.}:
        var sendFileName = ""
        var peer = $stream.peer
        var sendContentLength = 0
        while true:
          case stream.protocol
          of ChatProtocol:
            if data.remotes.hasKey(peer) and data.remotes[peer].len != 0:
              data.remotes[peer][ChatProtocol] = stream
            else:
              data.remotes[peer] = {ChatProtocol: stream}.toOrderedTable
            var line = await stream.transp.readLine()
            if line == "" or line == "stop":
              break

            var message = strformat.`&`"{peerInfoTable[peer].domainName} {$now().format(timeFormat)}\r\n{line}\r\n"
            echo message
              
          of SendProtocol:
            if data.remotes.hasKey(peer) and data.remotes[peer].len != 0:
              data.remotes[peer][SendProtocol] = stream
            else:
              data.remotes[peer] = {SendProtocol: stream}.toOrderedTable
            var line = "0"
            if sendContentLength == 0:
              line = await stream.transp.readLine()
              if line == "" or line == "stop": break
              var parts = line.split(":",1)
              sendFileName = parts[0]
              sendContentLength = parts[1].parseInt

            var f = open(sendFileName, fmAppend)
            if fileExists(sendFileName):
              if f.getFileSize == sendContentLength:
                f.close()
                discard await stream.transp.write "\r\n"
                continue
            else:
              f.setFilePos 0
            var s = stream
            while f.getFilePos < sendContentLength:
              var chunk = await s.transp.read(sendContentLength - f.getFilePos.int)
              if chunk.len > 0:
                f.write cast[string](chunk)
              if s.transp.atEof:
                echo "streamHandler SendProtocol atEof"
                var peerId = PeerID.init(peer).value
                s = await data.api.openStream(peerId, @[SendProtocol])

            if f.getFileSize == sendContentLength:
              discard await stream.transp.write "\r\n"
            else:
              discard await stream.transp.write($f.getFileSize & "\r\n")
            f.close()
            sendContentLength = 0
            sendFileName = ""

          of RequestProtocol:
            var fileWithEof = 0
            if data.remotes.hasKey(peer) and data.remotes[peer].len != 0:
              data.remotes[peer][RequestProtocol] = stream
            else:
              data.remotes[peer] = {RequestProtocol: stream}.toOrderedTable
            var line = strip await stream.transp.readLine()
            if line == "" or line == "stop": break
            if line.contains(":"):
              var parts = line.rsplit(":",1)
              line = parts[0]
              fileWithEof = parts[1].parseInt
            if fileTable.hasKey line:
              var content = readFile(fileTable[line].url)
              if fileWithEof == 0:
                discard await stream.transp.write $content.len & "\r\n"
                discard await stream.transp.write content
              else:
                discard await stream.transp.write content[fileWithEof..^1]

          of LikeProtocol:
            var line = await stream.transp.readLine()
            if line == "" or line == "stop": break
            fileTable[line].like.inc
            discard await stream.transp.write($fileTable[line].like & "\r\n")

            if data.remotes.hasKey(peer) and data.remotes[peer].len != 0:
              data.remotes[peer][LikeProtocol] = stream
            else:
              data.remotes[peer] = {LikeProtocol: stream}.toOrderedTable
            consoleString = $peerInfoTable[$stream.peer].domainName & strformat.`&` "点赞了\r\n{line}\r\n"
            echo consoleString
          else:
            break

    await data.api.addHandler(ServerProtocols, streamHandler)

    var newConnectedPeers, previousConnectedPeers: HashSet[string]

    while true:
      if stop: break
      var peers = await data.api.listPeers()
      for info in peers:
        newConnectedPeers.incl $info.peer
      var offLine = previousConnectedPeers - newConnectedPeers
      var onlinePeers = newConnectedPeers - previousConnectedPeers
      previousConnectedPeers = newConnectedPeers
      newConnectedPeers.clear
      var connected = fanyi"nodes connected"
      c_printf "\r" &  strformat.`&`"{peers.len} {connected} 上线: {onlinePeers.len} 离线: {offLine.len}\r\n"
      await sleepAsync(5000)

proc serveThread() {.async.} =
  # asyncCheck status()
  proc remoteReader(peer: string) {.async.} =
    {.gcsafe.}:
      while true:
        if data.remotes.hasKey(peer) and data.remotes[peer].hasKey(ChatProtocol):
          var line = await data.remotes[peer][ChatProtocol].transp.readLine()
          if line == "" or line == "stop":
            break
          
          var message = strformat.`&`"{peer} {$now().format(timeFormat)}\r\n{line}\r\n"
          echo message
        else:
          break
  {.gcsafe.}:
    while true:
      try:
        if stop :break
        var (available,line) = messageChan.tryRecv()
        if not available: 
          await sleepAsync(100)
          continue
        if not line.startsWith("/") and line.len == 46 or line.len == 52:
          var peerId = PeerID.init(line).value
          consoleString = fanyi"Searching for" & line & "\r\n"
          echo consoleString
          var id = await data.api.dhtFindPeer(peerId)

        elif line.startsWith("/chat"):
          var parts = line.split(" ")
          if len(parts) == 2:
            var peer = getPeerId()
            var peerId = PeerID.init(peer).value
            var stream = await data.api.openStream(peerId, @[ChatProtocol])
            if data.remotes.hasKey(peer) and data.remotes[peer].len != 0:
              data.remotes[peer][ChatProtocol] = stream
            else:
              data.remotes[peer] = {ChatProtocol: stream}.toOrderedTable
            asyncCheck remoteReader(peer)

        elif line.startsWith("/search"):
          var parts = line.split(" ")
          if len(parts) == 2:
            var peer = getPeerId()
            var peerId = PeerID.init(peer).value
            var id = await data.api.dhtFindPeer(peerId)
            for item in id.addresses:
              consoleString = $item & "\r\n"
              echo consoleString
        elif line.startsWith("/pub"):
          var parts = line.split(" ")
          if len(parts) == 3:
            var topic = parts[1]
            var message = parts[2]
            await data.api.pubsubPublish(topic, cast[seq[byte]](message))
        elif line.startsWith("/listpeers"):
          var parts = line.split(" ")
          if len(parts) == 2:
            var topic = parts[1]
            var peers = await data.api.pubsubListPeers(topic)
            echo peers
        elif line.startsWith("/gettopics"):
            var topics = await data.api.pubsubGetTopics()
            echo topics
        elif line.startsWith("/sub"):
          var parts = line.split(" ")
          if len(parts) == 2:
            var topic = parts[1]
            var ticket = await data.api.pubsubSubscribe(topic, callback)
            consoleString = fanyi"subscribed: " & ticket.topic & "\r\n"
            echo consoleString 
        elif line.startsWith("/request"):
          var parts = line.split(" ")
          if len(parts) == 3:
            var stream: P2PStream
            var peer: string
            if not data.remotes.hasKey(peer):
              peer = getPeerId()
              var peerId = PeerID.init(peer).value
              var address = MultiAddress.init("/p2p-circuit/p2p/" & $peerId).value
              await data.api.connect(peerId, @[address], 30)
              stream = await data.api.openStream(peerId, @[RequestProtocol])
              if data.remotes.hasKey(peer) and data.remotes[peer].len != 0:
                data.remotes[peer][RequestProtocol] = stream
              else:
                data.remotes[peer] = {RequestProtocol:stream}.toOrderedTable
            else:
              stream = data.remotes[peer][RequestProtocol]
            var start ,eof = 0
            var fileWithEof = strformat.`&`("{parts[2]}:{eof}\r\n")
            discard await stream.transp.write(fileWithEof)
            var (path,name,ext) = parts[2].splitFile
            var file = name & ext
            var length = await stream.transp.readLine()
            var totalLength = length.parseInt
            echo "请求文件长度:", totalLength

            var startTime = now()
            var f = open(tempDir / file, fmAppend)
            f.setFilePos 0
            while f.getFilePos != totalLength:
              var chunk = await stream.transp.read(totalLength - f.getFilePos.int)
              f.write cast[string](chunk)
              if stream.transp.atEof:
                echo "request atEof"
                await stream.close()
                var peerId = PeerID.init(peer).value
                stream = await data.api.openStream(peerId, @[RequestProtocol])
                fileWithEof = strformat.`&`("{parts[2]}:{f.getFilePos}\r\n")
                discard await stream.transp.write(fileWithEof)
            f.close()
            var duration = (now() - startTime).inMilliseconds()
            consoleString = strformat.`&`"打开用时{duration}ms" & "\r\n"
            echo consoleString

        elif line.startsWith "/send":
          var parts = line.split(" ")
          if len(parts) == 3:
            var stream: P2PStream
            var peer: string
            if not data.remotes.hasKey(peer):
              peer = getPeerId()
              var peerId = PeerID.init(peer).value
              var address = MultiAddress.init("/p2p-circuit/p2p/" & $peerId).value
              await data.api.connect(peerId, @[address], 30)
              stream  = await data.api.openStream(peerId, @[SendProtocol])
              if data.remotes.hasKey(peer) and data.remotes[peer].len != 0:
                data.remotes[peer][SendProtocol] = stream
              else:
                data.remotes[peer] = {SendProtocol:stream}.toOrderedTable
            else:
              stream = data.remotes[peer][SendProtocol]
            var (_,name,ext) = splitFile(parts[2])
            var content = readFile(parts[2])
            var file = name & ext
            var header = strformat.`&`"{file}:{content.len}\r\n"
            discard await stream.transp.write(header)

            consoleString = strformat.`&`"发送 {file} 长度 {content.len}字节" & "\r\n"
            echo consoleString
            var start = now()
            var written = 0
            var unexpectedlines = content.count("\r\n")
            if unexpectedlines != 0:
              discard await stream.transp.write(content)

            var response = ""
            while true:
              response = await stream.transp.readLine()
              if response == "":
                break
              else:
                continue
            var duration = (now() - start).inMilliseconds()
            consoleString = strformat.`&`"{parts[1]}:用时{duration} ms" & "\r\n"
            echo consoleString

        elif line.startsWith("/exit"):
          break
        else:
            var msg = line & "\r\n"
            var pending = newSeq[Future[int]]()
            for peer,streams in data.remotes:
                pending.add(streams[ChatProtocol].transp.write(msg))
            if len(pending) > 0:
                await allFutures(pending)
      except:
        var e = getCurrentException()
        echo e.getStackTrace

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


messageChan.send("/sub " & topDomain)
messageChan.send("/sub " & topDomain)

waitFor serveThread()
