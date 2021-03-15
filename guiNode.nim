import strformat, strutils, times,json,os, streams, 
      sequtils, sugar, sets, tables, osproc, re, mimetypes, deques
import system/ansi_c
import unicode except strip

import libp2p/daemon/daemonapi
import libp2p/daemon/transpool
import wNim ,chronos, nimcrypto
import wNim/private/winimx
import wNim/private/wBase
import miniblink
import stew/shims/net

import i18n
import os
import winim/[winstr, utils], winim/inc/[winuser, shellapi]

import wNim/[wApp, wMacros, wStaticText, wFont, wCursor]
import winim

when not(compileOption("threads")):
  {.fatal: "Please, compile this program with the --threads:on option!".}

type
  FileStatus = enum
    Stopped, Running

  FileInfo = ref object
    url*: string
    like*: uint
    status*: FileStatus

  Node = ref object
    stop: bool
    globalDomain: string
    topDomain: string
    consoleString: string
    peerFilter: string #节点过滤
    api: DaemonAPI
    messageChan: Channel[string]  #消息通道
    fileChan: Channel[string] #Shell执行打开文件的通道
    hyperlinkChan: Channel[string] #创建超链接通道
    remotes: OrderedTable[string, OrderedTable[string, P2PStream]] #节点-协议-流映射
    chatOutputTable: OrderedTable[string, wTypes.wTextCtrl] #对话框输出面板
    peerInfoTable: OrderedTable[string, tuple[info:PeerInfo, item: wTreeItem]] #节点信息表，包含基本信息和节点列表中对应的GUI元素
    domainPeerTable : OrderedTable[string,string] #记录域名与节点编号的对应关系
    fileTable: OrderedTable[string, FileInfo] #分享的文件信息表

type
  MenuID = enum
    idOpen, idExit,idenUS, idzhCN, idGoForward,idGoBack, idCopy, idCheck, idChat, idWatch, idClose, idSend, 
    idCreateHyperlink, idHyperlinkCheck, idHyperlinkRun,idHyperlinkStop, idHyperlinkLike, idCreateChatFrame

type
  wMyLinkEvent = ref object of wCommandEvent

type
  wHyperlink* = ref object of wStaticText
    mUrl*: string
    mMarkedColor: wColor
    mVisitedColor: wColor
    mNormalColor: wColor
    mHoverFont: wFont
    mNormalFont: wFont
    mIsMouseHover: bool
    mIsPressed: bool
    mIsVisited: bool

const
  ChatProtocol = "/lingX-chat-stream"
  RequestProtocol = "/lingX-request-stream"
  SendProtocol = "/lingX-send-stream"
  LikeProtocol = "/lingX-like-stream"

  ServerProtocols = @[ChatProtocol,RequestProtocol,SendProtocol,LikeProtocol]

const timeFormat = initTimeFormat("yyyy-MM-dd HH:mm:ss")

var tempDir = getTempDir()

const extensions = collect(newSeq):
  for (k,v) in mimes:
    k

var node = new Node
node.messageChan.open()
node.fileChan.open()
node.hyperlinkChan.open()

wEventRegister(wMyLinkEvent):
  wEvent_OpenUrl

var searchTextCtrl: wTextCtrl

var hyperlinks: OrderedTable[string, wHyperlink]

template loadHtmlOrRequestOthers() {.dirty.} =
  var (path, name, ext) = splitFile(self.mUrl)
  if ext == ".html":
    searchTextCtrl.add self.mUrl
    discard winim.PostMessage(searchTextCtrl.mHwnd, wEvent_TextEnter, 0, 0)
  else:
    path = path.replace("ipfs://","")
    var peer = node.domainPeerTable[path]
    var req = strformat.`&`"/request {peer} {self.mUrl}"
    echo "req:", req
    node.messageChan.send req

let app = App()
let frame = Frame(title="灵犀", size=(1024, 600))

frame.dpiAutoScale:
  frame.size = (1024, 600)
  frame.minSize = (1024, 600)

var panel = Panel(frame)
let splitter1 = Splitter(panel, style = wSpVertical, size=(1, 1))
let console = TextCtrl(splitter1.panel2, style = wTeRich or wTeMultiLine or wVScroll  or wTeReadOnly or wTeDontWrap)
console.setMargin(10,0)

proc runNim(link: wHyperlink) {.async.} =
  {.gcsafe.}:
    var (path, name, ext) = splitFile(link.mUrl)
    if ext == ".nim":
      var
        p = startProcess("nim r --hints:off --warnings:off " & link.mUrl , options = {poStdErrToStdOut, poUsePath, poEvalCommand})
        outp = p.outputStream()
        line = ""
      while true:
        if outp.readLine(line):
          console.add line & "\r\n"
        elif not p.running():
          break
        elif node.fileTable[link.label].status == Stopped: 
          p.kill()
          break
          

wClass(wHyperlink of wStaticText):
  proc getVisitedOrNormalColor(self: wHyperlink): wColor {.validate, property.} =
    result = if self.mIsVisited: self.mVisitedColor else: self.mNormalColor

  proc setFont*(self: wHyperlink, font: wFont) {.validate, property.} =
    self.wWindow.setFont(font)
    self.mNormalFont = font
    self.fit()

  proc getHoverFont*(self: wHyperlink): wFont {.validate, property.} =
    result = self.mHoverFont

  proc setHoverFont*(self: wHyperlink, font: wFont) {.validate, property.} =
    self.mHoverFont = font
    if self.mIsMouseHover:
      self.wWindow.setFont(self.mHoverFont)
      self.fit()

  proc getMarkedColor*(self: wHyperlink): wColor {.validate, property.} =
    result = self.mMarkedColor

  proc setMarkedColor*(self: wHyperlink, color: wColor) {.validate, property.} =
    self.mMarkedColor = color
    if self.mIsPressed:
      self.setForegroundColor(self.mMarkedColor)
      self.refresh()

  proc getNormalColor*(self: wHyperlink): wColor {.validate, property.} =
    result = self.mNormalColor

  proc setNormalColor*(self: wHyperlink, color: wColor) {.validate, property.} =
    self.mNormalColor = color
    if not self.mIsPressed:
      self.setForegroundColor(self.visitedOrNormalColor)
      self.refresh()

  proc getVisitedColor*(self: wHyperlink): wColor {.validate, property.} =
    result = self.mVisitedColor

  proc setVisitedColor*(self: wHyperlink, color: wColor) {.validate, property.} =
    self.mVisitedColor = color
    if not self.mIsPressed:
      self.setForegroundColor(self.visitedOrNormalColor)
      self.refresh()

  proc getUrl*(self: wHyperlink): string {.validate, property.} =
    result = self.mUrl

  proc setUrl*(self: wHyperlink, url: string) {.validate, property.} =
    self.mUrl = url

  proc setVisited*(self: wHyperlink, isVisited = true) {.validate, property.} =
    self.mIsVisited = isVisited

  proc getVisited*(self: wHyperlink): bool {.validate, property.} =
    result = self.mIsVisited

  proc init*(self: wHyperlink, parent: wWindow, id = wDefaultID, label: string,
      url: string, pos = wDefaultPoint, size = wDefaultSize, style: wStyle = 0) =

    self.wStaticText.init(parent, id, label, pos, size, style)
    self.mUrl = url
    self.mMarkedColor = wRed
    self.mVisitedColor = 0x8B1A55
    self.mNormalColor = wBlue
    self.mIsMouseHover = false
    self.mIsPressed = false
    self.mIsVisited = false

    self.fit()
    self.setCursor(wHandCursor)
    self.setForegroundColor(self.mNormalColor)

    self.mNormalFont = self.getFont()
    self.mHoverFont = Font(self.mNormalFont)
    self.mHoverFont.underlined = true

    self.wEvent_MouseEnter do ():
      self.mIsMouseHover = true
      self.wWindow.setFont(self.mHoverFont)
      if self.mIsPressed:
        self.setForegroundColor(self.mMarkedColor)
      else:
        self.setForegroundColor(self.visitedOrNormalColor)
      self.fit()
      self.refresh()

    self.wEvent_MouseLeave do ():
      self.mIsMouseHover = false
      self.wWindow.setFont(self.mNormalFont)
      self.setForegroundColor(self.visitedOrNormalColor)
      self.fit()
      self.refresh()

    self.wEvent_LeftDown do ():
      self.mIsPressed = true
      self.captureMouse()
      self.setForegroundColor(self.mMarkedColor)
      self.refresh()

    self.wEvent_LeftUp do ():
      let isPressed = self.mIsPressed
      self.mIsPressed = false
      self.releaseMouse()
      self.setForegroundColor(self.visitedOrNormalColor)
      self.refresh()

      if self.mIsMouseHover and isPressed:
        if self.mUrl.len != 0:
          let event = Event(window=self, msg=wEvent_OpenUrl)
          if not self.processEvent(event) or event.isAllowed:
            var (_, name, ext) = self.mUrl.splitFile()
            if fileExists(self.mUrl):
              shellapi.ShellExecute(0, "open", self.mUrl, nil, nil, winim.SW_SHOW)
            elif fileExists(tempDir / name & ext):
              shellapi.ShellExecute(0, "open", tempDir / name & ext, nil, nil, winim.SW_SHOW)
            else:
              loadHtmlOrRequestOthers()
              
        self.mIsVisited = true
    #超链接右键菜单事件
    self.wEvent_ContextMenu do(event: wEvent):
      let hyperlinkMenu = Menu()
      hyperlinkMenu.append(idHyperlinkLike, fanyi"Like")
      hyperlinkMenu.append(idHyperlinkLike, $node.fileTable[self.label].like).disable()
      var (_, name, ext) = self.mUrl.splitFile()
      if ext == ".nim":
        hyperlinkMenu.append(idHyperlinkCheck, fanyi"Check")
        hyperlinkMenu.append(idHyperlinkRun, fanyi"Run")
        if node.fileTable[self.label].status == Running:
          hyperlinkMenu.append(idHyperlinkStop, fanyi"Stop")

      self.popupMenu(hyperlinkMenu)
      
      proc rightClickHyperlink(event: wEvent) =
        case event.id
        of idHyperlinkCheck: 
          if fileExists(self.mUrl):
            shellapi.ShellExecute(0, "open", self.mUrl, nil, nil, winim.SW_SHOW)
          elif fileExists(tempDir / name & ext):
            shellapi.ShellExecute(0, "open", tempDir / name & ext, nil, nil, winim.SW_SHOW)
        of idHyperlinkRun:
          # echo toSeq node.fileTable.keys
          # echo self.mUrl
          if node.fileTable.hasKey(self.label) and fileExists(self.mUrl):
            var req = "/run " & self.label
            echo req
            node.messageChan.send req
          else:
            loadHtmlOrRequestOthers()

        of idHyperlinkStop:
          node.fileTable[self.label].status = Stopped
        of idHyperlinkLike:
          if node.fileTable.hasKey(self.label):
            node.fileTable[self.label].like.inc
            if node.fileTable[self.label].url == self.mUrl:
              var d = self.mUrl.replace("ipfs://","").splitFile[0]
              if node.domainPeerTable.hasKey d:
                var peer = node.domainPeerTable[d]
                var peerId = PeerID.init(peer).value
                var address = MultiAddress.init("/p2p-circuit/p2p/" & $peerId).value
                waitFor node.api.connect(peerId, @[address], 30)
                var stream = waitFor node.api.openStream(peerId, @[LikeProtocol])
                discard waitFor stream.transp.write(self.mUrl & "\r\n")
                var likes = waitFor stream.transp.readLine()
                node.fileTable[self.label].like = uint likes.parseInt  
        else: discard
      self.connect(wEvent_Menu, rightClickHyperlink)

var fontHeight:int
var fontWidth:int
var defaultLineHeight = console.getDefaultSize().height div 3
var fontMarginLeft = console.getMargin().left

template setChatFrame(peer: string):untyped {.dirty.} =
  var title = "与" & peer & "的对话"
  var chatFrame = Frame(owner=frame, title=title, style=wDefaultFrameStyle)
  chatFrame.wEvent_Close do ():
    node.chatOutputTable.del peer
    chatFrame.delete()

  let size = chatFrame.clientSize

  let chatSplitter = Splitter(chatFrame, style = wSpHorizontal , size=(1, 1))
  var chatSplitterPos: wPoint = (size.width * 4 div 5 , size.height * 4 div 5)
  chatSplitter.move(chatSplitterPos.x, chatSplitterPos.y)

  let chatOutput = TextCtrl(chatSplitter.panel1, style = wTeRich or wTeMultiLine or wVScroll  or wTeReadOnly or wTeDontWrap)
  chatOutput.setMargin(10,0)
  let chatInput = TextCtrl(chatSplitter.panel2, style= wTeRich or wTeMultiLine or wVScroll)
  chatInput.setFocus()
  chatInput.setMargin(10,0)
  chatInput.wEvent_TextEnter do():
      var line = strip chatInput.getValue()
      var message = strformat.`&`"{node.globalDomain} {$now().format(timeFormat)}\r\n{line}\r\n"
      node.messageChan.send line
      chatOutput.add message
      chatInput.clear

  proc chatSplitterPanle1Layout() = 
    chatSplitter.panel1.autolayout """
    HV:|[chatOutput]|""""

  proc chatSplitterPanle2Layout() = 
    chatSplitter.panel2.autolayout """
    HV:|[chatInput]|""""

  chatFrame.wEvent_Size do():
    chatSplitterPanle1Layout()
    chatSplitterPanle2Layout()

  chatSplitterPanle1Layout()
  chatSplitterPanle2Layout()
  node.chatOutputTable[peer] = chatOutput
  chatFrame.center()
  chatFrame.show()

proc frameMenu(event: wEvent) = 
  case event.id
  of idExit:
    frame.close()
  of idOpen:  
    var files = FileDialog(frame, style=wFdOpen or wFdFileMustExist).display()
    if files.len != 0:
      var (path,name,ext) = splitFile(files[0])
      var label = "ipfs://" & node.globalDomain & "/" & name & ext
      waitFor node.api.pubsubPublish(node.topDomain, label)
      node.fileTable[label] = FileInfo(url:files[0], like:0, status: Stopped)
  of idenUS:
    if currentLanguage != "enUS":
      setCurrentLanguage "enUS"
  of idzhCN:
    if currentLanguage != "zhCN":
      setCurrentLanguage "zhCN"
  of idCreateHyperlink:
    for file in hyperlinks.keys:
      if hyperlinks[file] == nil:
        var (path, name, ext) = file.splitFile()
        var lastPosition = console.getLastPosition()
        var insertionPoint = console.getInsertionPoint()
        let pos = console.positionToXY(lastPosition)
        let x = fontWidth * pos.x + fontMarginLeft
        let y = (fontHeight) * (pos.y)
        var hyperlink = Hyperlink(console, label = file, url = node.fileTable[file].url , pos = (x,y))
        hyperlinks[file] = hyperlink
  of idCreateChatFrame:
    var peer = cast[cstring](event.mLparam)
    setChatFrame($peer)
  else:
    echo "unknown event"
    discard

frame.connect(wEvent_Menu,frameMenu)

#创建域名对话框
proc domainDialog(owner: wWindow): string =
  let dialog = Frame(owner=owner, size=(320, 200), style=wCaption)
  let dialogPanel = Panel(dialog)

  var nameDomain = fanyi"Enter the domain:" & "如Nim中文社区/小明"
  let statictext = StaticText(dialogPanel, label = nameDomain, pos=(10, 10))
  let textctrl = TextCtrl(dialogPanel, pos=(20, 50), size=(270, 30), style=wBorderSunken)
  let buttonOk = Button(dialogPanel, label= fanyi"OK", size=(90, 30), pos=(100, 120))
  let buttonCancel = Button(dialogPanel, label= fanyi"Cancel", size=(90, 30), pos=(200, 120))

  buttonOk.setDefault()
  dialog.wIdDelete do ():
    textctrl.clear()
  dialog.wEvent_Close do ():
    dialog.endModal()
  buttonOk.wEvent_Button do ():
    node.globalDomain = textctrl.value
    dialog.close()
  buttonCancel.wEvent_Button do ():
    dialog.close()
    quit()
  dialog.shortcut(wAccelNormal, wKey_Esc) do ():
    buttonCancel.click()
  dialog.center()
  dialog.showModal()
  dialog.delete()
  result = node.globalDomain

proc initDomain() = 
  node.globalDomain = config["domain"].getStr
  while node.globalDomain == "":
    node.globalDomain = domainDialog(frame)
    var parts = node.globalDomain.split("/")
    if parts.len < 2 or parts[0] == "":
      MessageDialog(frame, "格式不正确", style = wOk or wIconInformation).display()
      node.globalDomain.reset
      continue

  config["domain"] = %node.globalDomain
  writeFile("config.json", $config)
  node.topDomain = node.globalDomain.rsplit("/",1)[0]

  node.consoleString = fanyi"Domain: " & node.globalDomain & "\r\n" 
  console.add node.consoleString
  node.consoleString = fanyi"ID: " & config["id"].getStr & "\r\n"
  console.add node.consoleString

  for line in console.getTitle().splitLines:
    var fontSize = getTextFontSize(line, console.mFont.mHandle, console.mHwnd)
    fontHeight = fontSize.height
    fontWidth = fontSize.width div line.runeLen
    break
  
var wv: wkeWebView

let peerboard = TreeCtrl(splitter1.panel1, style= wTrLinesAtRoot or wTrHasLines or wTrTwistButtons or wTrNoHScroll or wTrSingleExpand)
# peerboard.font = Font(9, encoding=wFontEncodingCp936)

#关闭窗口事件
frame.wEvent_Close do():
  node.stop = true
  node.fileChan.send "stop"
  node.messageChan.send "stop"
  for peer,streams in node.remotes:
    for protocol, stream in streams:
      asyncCheck stream.transp.write("stop\r\n")
  for peer, _ in node.peerInfoTable:
    waitFor node.api.disconnect(PeerID.init(peer).get)
  waitFor node.api.close
  node.messageChan.close
  node.fileChan.close
  node.hyperlinkChan.close

let rebar = Rebar(frame)
let toolbar = ToolBar(rebar)
let imgGoBack = Image(Icon("shell32.dll,137")).scale(12, 12)
let imgGoForward = Image(Icon("shell32.dll,137")).scale(12, 12)
imgGoBack.rotateFlip(wImageRotateNoneFlipX)

toolbar.addTool(idGoBack, "", Bitmap(imgGoBack), longHelp="后退")
toolbar.addTool(idGoForward, "", Bitmap(imgGoForward), longHelp="前进")
toolbar.disableTool(idGoBack)
toolbar.disableTool(idGoForward)
rebar.addControl(toolbar)

searchTextCtrl = TextCtrl(rebar, value="ipfs://", style = wBorderSunken)

# searchTextCtrl.font = Font(12, faceName="Consolas", encoding=wFontEncodingCp1252)
searchTextCtrl.wEvent_SetFocus do (event: wEvent):
  searchTextCtrl.selectAll()
  event.skip

rebar.addControl(searchTextCtrl)
rebar.minimize(0)

#状态栏
let statusBar = StatusBar(frame)
#菜单栏
let menuBar = MenuBar(frame)
let menuFile = Menu(menuBar, fanyi"File")
menuFile.append(idOpen, fanyi"Open", "Open a file")
menuFile.appendSeparator()
menuFile.append(idExit, fanyi"Exit", "Exit the program")

let menuLang = Menu(menuBar, fanyi"Language")
if currentLanguage == "enUS":
  menuLang.appendRadioItem(idenUS, "enUS").check()
  menuLang.appendRadioItem(idzhCN, "zhCN")
else:
  menuLang.appendRadioItem(idenUS, "enUS")
  menuLang.appendRadioItem(idzhCN, "zhCN").check()

proc wkeOnPaintUpdatedCallback(webView: wkeWebView, param: pointer, hdc, x, y, cx, cy: int) {.cdecl.} =
  discard

proc wkeDocumentReadyCallback(webView: wkeWebView, param: pointer) {.cdecl.} =
  echo "wkeDocumentReadyCallback"

proc wkeOnTitleChangedCallBack(webView: wkeWebView, param: pointer, title: wkeString) {.cdecl.} =
  frame.title = $webView.wkeGetTitle()

proc wkeOnNavigationCallback(webView: wkeWebView, param: pointer, navigationType: wkeNavigationType, url: wkeString): bool {.cdecl.} =
  case $url.wkeGetString()
  of "xcm:close":
    wv.wkeDestroyWebWindow()
    frame.close()
    return false
  else: 
    return true

proc wkeURLChangedCallback(webView: wkeWebView, param: pointer, url: wkeString) {.cdecl.} =
  toolBar.enableTool(idGoForward, wv.wkeCanGoForward)
  var urlStr = $url.wkeGetString()
  if not urlStr.startsWith("file://"):
    searchTextCtrl.setValue urlStr

let searchPeer = TextCtrl(splitter1.panel1, style = wBorderSunken)

let domainButton = Button(splitter1.panel1, label = "搜索", style=wBuNoBorder)
domainButton.wEvent_Button do():
  node.messageChan.send "/search " & searchPeer.getValue().strip()

searchPeer.wEvent_Text do():
  node.peerFilter = searchPeer.getValue()

#搜索栏输入回车
searchTextCtrl.wEvent_TextEnter do():
  wkeInitialize()
  var wkeWindowStyle = WKE_WINDOW_TYPE_CONTROL
  var size = frame.clientSize()
  var toolSize = toolbar.getToolSize()
  wv = wkeCreateWebWindow(wkeWindowStyle, frame.mHwnd, 0,toolSize.height, size.width, size.height ,"浏览器")
  var url = strip searchTextCtrl.getValue
  if url == "ipfs://": return

  elif node.fileTable.hasKey url:
      url = node.fileTable[url].url
      wv.wkeLoadFile(url)
  elif url.startsWith("ipfs://"):
      url = url.replace("ipfs","http")
      wv.wkeLoadUrl(url)
  elif fileExists(url):
      wv.wkeLoadFile(url)
  else:
    node.messageChan.send url
    return
  panel.hide()
  toolBar.enableTool(idGoBack, true)
  wv.wkeShowWindow(true)
  wv.wkeOnPaintUpdated(wkeOnPaintUpdatedCallback, cast[pointer](frame))
  wv.wkeOnDocumentReady(wkeDocumentReadyCallback, cast[pointer](frame))
  wv.wkeOnTitleChanged(wkeOnTitleChangedCallBack, cast[pointer](frame))
  wv.wkeOnNavigation(wkeOnNavigationCallback, cast[pointer](frame))
  wv.wkeOnURLChanged(wkeURLChangedCallback, cast[pointer](frame))

  proc webViewResize(event: wEvent) =
    var frameSize = frame.clientSize()
    panel.setSize(frameSize.width, frameSize.height)
    wv.wkeResize(frameSize.width, frameSize.height)
  frame.connect(wEvent_Size, webViewResize)
  #工具栏/菜单事件
  frame.wEvent_Tool do (event: wEvent):
    case event.id
    of idGoBack: 
      if wv.wkeCanGoBack() == false:
        panel.show()
        frame.disconnect(wEvent_Size, webViewResize)
        wv.wkeDestroyWebWindow()
        toolbar.disableTool(idGoBack)
        toolbar.disableTool(idGoForward)
        searchTextCtrl.setValue "ipfs://"
      else:
        discard wv.wkeGoBack()
    of idGoForward: 
      discard wv.wkeGoForward()
    else: 
      event.skip

#节点列表右键菜单事件
peerboard.wEvent_ContextMenu do(event: wEvent):
  var (item,flag) = peerboard.hitTest(event.getMousePos())
  var d = item.getText().strip().split(" ")[0]
  var peer = if node.domainPeerTable.hasKey(d): node.domainPeerTable[d] else: d
  let peerMenu = Menu()
  peerMenu.append(idCheck, fanyi"Check")
  peerMenu.append(idCopy, fanyi"Copy")
  if d != node.globalDomain:
    peerMenu.append(idChat, fanyi"Chat")
    peerMenu.append(idSend, fanyi"Send")
    peerMenu.append(idWatch, fanyi"Watch")
    peerMenu.append(idClose, fanyi"Close")
  peerboard.popupMenu(peerMenu)

  proc rightClickPeer(event: wEvent) =
    case event.id
    of idCheck: 
      var title = strformat.`&`("{d}的信息")
      let checkFrame = Frame(owner=frame, title=title, style=wDefaultDialogStyle)
      checkFrame.wEvent_Close do ():
        checkFrame.delete()

      let peerInfo = TextCtrl(checkFrame, style = wTeRich or wTeMultiLine or wVScroll  or wTeReadOnly or wTeDontWrap)
      peerInfo.setMargin(10,0)
      proc checkFrameLayout() =
        checkFrame.autolayout"""
        HV:|[peerInfo]|"""
        
      var peerId = PeerID.init(peer).value
      var id = waitFor node.api.dhtFindPeer(peerId)
      node.consoleString = "ID:" & $peerId & "\r\n"
      peerInfo.add node.consoleString
      for item in id.addresses:
        node.consoleString = $item & "\r\n"
        peerInfo.add node.consoleString
      peerInfo.add "历史记录:\r\n"

      checkFrameLayout()
      checkFrame.center()
      checkFrame.show()

    of idCopy: 
      wSetClipboard(DataObject d)
    of idChat: 
      var req = "/chat " & d 
      node.messageChan.send req

      setChatFrame(peer)
    of idWatch: 
      var topic = peer
      proc callback(api: DaemonAPI,ticket: PubsubTicket,message: PubSubMessage): Future[bool] = 
        result = newFuture[bool]()
        result.complete true
      var ticket = waitFor node.api.pubsubSubscribe(topic,callback)
      node.consoleString = fanyi"watched: " & $node.peerInfoTable[ticket.topic].info.domain & "\r\n"
      console.add node.consoleString
    of idSend:
      var files = FileDialog(frame, style=wFdOpen or wFdFileMustExist).display()
      if files.len != 0:
        var req = strformat.`&`"/send {d} {files[0]}"
        echo "req:", req
        node.messageChan.send req
    of idClose:
      waitFor node.api.disconnect(PeerID.init(peer).get)
      delete(item)
    else: discard
  peerboard.connect(wEvent_Menu, rightClickPeer)

#苹果公司可视化格式语言https://developer.apple.com/library/archive/documentation/UserExperience/Conceptual/AutolayoutPG/VisualFormatLanguage.html
#左边框布局
proc splitter1Panle1Layout() = 
  splitter1.panel1.autolayout """
  spacing:1
  H:|-[searchPeer]-10-[domainButton(50)]-|
  H:|-[peerboard]-|
  V:|-[searchPeer]-[peerboard]-|
  V:|-[domainButton]-[peerboard]-|
  """

#右边框布局用console填充
proc splitter1Panle2Layout() = 
  splitter1.panel2.autolayout """
  HV:|[console]|""""

proc frameLayout() = 
  frame.autolayout"""
  HV:|[panel]|
  """
frameLayout()
splitter1Panle1Layout()

proc panelLayout() = 
  frameLayout()
  splitter1Panle1Layout()
  splitter1Panle2Layout()
panelLayout()

#窗口尺寸事件的处理方法
splitter1.panel1.wEvent_Size do():
  splitter1Panle1Layout()
splitter1.panel2.wEvent_Size do():
  splitter1Panle2Layout()

let size = panel.clientSize
#设置分隔栏初始位置，垂直分隔栏在中间，水平分隔栏在屏幕左上角向下2/3高度
var splitter1Pos: wPoint = (size.width div 2, size.height div 2)
#将分隔栏移动到指定位置
splitter1.move(splitter1Pos.x, splitter1Pos.y)

# #记录分隔栏移动的位置
splitter1.wEvent_Splitter do():
  splitter1Pos = splitter1.getPosition()

panel.wEvent_Size do():
  var size = panel.clientSize
  if size.width > 0 and size.height > 0:
    splitter1.move(size.width div 2, size.height div 2)
  else:
    splitter1.move(splitter1Pos.x, splitter1Pos.y)

proc startDaemon() = 
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

  when defined(windows):
    const daemon = "p2pd.exe"
  else:
    const daemon = "./p2pd"

  #使用config.json文件配置的引导节点
  var bootstrapNodes = config["bootstrapNodes"].mapIt(it.getStr)
  node.api = waitFor newDaemonApi({DHTFull, PSGossipSub, Bootstrap, AutoRelay}, id="key", 
    bootstrapNodes = bootstrapNodes, daemon=daemon, hostAddresses=hostAddresses)

  var id = $(waitFor node.api.identity()).peer
  var domainPub = fmt"/pub 域名系统 " & $ %*{config["domain"].getStr: $id}
  echo domainPub
  node.messageChan.send(domainPub)
  if config["id"].getStr != id:
    config["id"] = % $id
    writeFile("config.json", $config)



template getPeerId(): untyped =
  if node.domainPeerTable.hasKey(parts[1]):
      node.domainPeerTable[parts[1]]
  elif parts[1].len == 46 or parts[1].len == 52: 
    parts[1] 
  else: continue


proc callback(api: DaemonAPI,ticket: PubsubTicket,message: PubSubMessage): Future[bool] = 
  {.gcsafe.}:
    result = newFuture[bool]()
    if message.data.contains("ipfs://"):
      var file = message.data
      console.add "\r\n" 
      hyperlinks[file] = nil
      if not node.fileTable.hasKey(file):
        var (path,name,ext) = splitFile(file)
        node.fileTable[file] = FileInfo(url:file , like:0 , status: Stopped)
      discard winim.PostMessage(frame.mHwnd, wEvent_Menu, WPARAM idCreateHyperlink, LPARAM idCreateHyperlink)
    else:
      echo message.data
    result.complete true

proc execute() {.thread.} =
  {.gcsafe.}:
    while true:
      var file = node.fileChan.recv()
      if file == "stop": break
      var (path,name,ext) = file.splitFile()
      var tempFile = tempDir / name & ext
      if fileExists(tempFile):
        shellapi.ShellExecute(0, "open", tempFile , nil, nil, winim.SW_SHOW)
      hyperlinks[file].setCursor(Cursor(wCursorHand))

var shellOpen: Thread[void]
shellOpen.createThread(execute)


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
            if node.remotes.hasKey(peer) and node.remotes[peer].len != 0:
              node.remotes[peer][ChatProtocol] = stream
            else:
              node.remotes[peer] = {ChatProtocol: stream}.toOrderedTable
            var line = await stream.transp.readLine()
            if line == "" or line == "stop":
              break
            if not node.chatOutputTable.hasKey(peer):
              var res = winim.SendMessage(frame.mHwnd, wEvent_Menu, WPARAM idCreateChatFrame, cast[LPARAM](&peer.cstring))
              if res != 0:
                continue
            var message = strformat.`&`"{node.peerInfoTable[peer].info.domain} {$now().format(timeFormat)}\r\n{line}\r\n"
            node.chatOutputTable[peer].add message
              
          of SendProtocol:
            if node.remotes.hasKey(peer) and node.remotes[peer].len != 0:
              node.remotes[peer][SendProtocol] = stream
            else:
              node.remotes[peer] = {SendProtocol: stream}.toOrderedTable
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
                s = await node.api.openStream(peerId, @[SendProtocol])

            if f.getFileSize == sendContentLength:
              discard await stream.transp.write "\r\n"
            else:
              discard await stream.transp.write($f.getFileSize & "\r\n")
            f.close()
            sendContentLength = 0
            sendFileName = ""

          of RequestProtocol:
            var fileWithEof = 0
            if node.remotes.hasKey(peer) and node.remotes[peer].len != 0:
              node.remotes[peer][RequestProtocol] = stream
            else:
              node.remotes[peer] = {RequestProtocol: stream}.toOrderedTable
            var line = strip await stream.transp.readLine()
            if line == "" or line == "stop": break
            if line.contains(":"):
              var parts = line.rsplit(":",1)
              line = parts[0]
              fileWithEof = parts[1].parseInt
            if node.fileTable.hasKey line:
              var content = readFile(node.fileTable[line].url)
              if fileWithEof == 0:
                discard await stream.transp.write $content.len & "\r\n"
                discard await stream.transp.write content
              else:
                discard await stream.transp.write content[fileWithEof..^1]

          of LikeProtocol:
            var line = await stream.transp.readLine()
            if line == "" or line == "stop": break
            node.fileTable[line].like.inc
            discard await stream.transp.write($node.fileTable[line].like & "\r\n")

            if node.remotes.hasKey(peer) and node.remotes[peer].len != 0:
              node.remotes[peer][LikeProtocol] = stream
            else:
              node.remotes[peer] = {LikeProtocol: stream}.toOrderedTable
            node.consoleString = $node.peerInfoTable[$stream.peer].info.domain & strformat.`&` "赞\r\n{line}\r\n"
            console.add node.consoleString
          else:
            break

    await node.api.addHandler(ServerProtocols, streamHandler)

    var newConnectedPeers, previousConnectedPeers: HashSet[string]
    var peerRootTable: OrderedTable[string, wTreeItem]

    while true:
      if node.stop: break
      var peers = await node.api.listPeers()
      peers.insert PeerInfo(peer: PeerId.init(config["id"].getStr).get, domain: node.globalDomain)
      var id = config["id"].getStr
      for info in peers.mitems:
        if info.domain == "": info.domain = "IPFS/" & $info.peer
        if not node.peerInfoTable.hasKey $info.peer:
          node.peerInfoTable[$info.peer] = (info:info, item: peerboard.TreeItem(0))
        else:
          node.peerInfoTable[$info.peer].info = info
        
        if info.domain != "":
          node.domainPeerTable[info.domain] = $info.peer

        if info.domain.contains(node.peerFilter):
          newConnectedPeers.incl $info.peer
          var peerDomain = info.domain.split("/")
          if not peerRootTable.hasKey(peerDomain[0]):
            peerRootTable[peerDomain[0]] = peerboard.addRoot(peerDomain[0])

        getLatencyAndUnit()
                     
        var peer = if info.domain != "": info.domain else: $info.peer
        var formatItem = strformat.`&`"{peer} {info.transport} {unitLatency}{unit}"
        var old = node.peerInfoTable[$info.peer].item.getText
        var oldParent = node.peerInfoTable[$info.peer].item.getParent.getText
        if not info.domain.startsWith(oldParent):
            delete node.peerInfoTable[$info.peer].item
            node.peerInfoTable[$info.peer] = (info: info,item: peerboard.appendItem(peerRootTable[info.domain.split("/")[0]], formatItem & "\r\n"))
        if old != formatItem:
          node.peerInfoTable[$info.peer].item.setText formatItem 
      
      var offLine = previousConnectedPeers - newConnectedPeers
      for p in offLine:
        delete node.peerInfoTable[p].item
        node.peerInfoTable.del p

      var roots = toSeq peerRootTable.keys
      # echo "roots:%s",roots

      var onlinePeers = newConnectedPeers - previousConnectedPeers
      for id in onlinePeers:
        var info = node.peerInfoTable[id].info
        getLatencyAndUnit()
        var peer = if info.domain != "": info.domain else: $info.peer
        var formatItem = strformat.`&`"{peer} {info.transport} {unitLatency}{unit}"
        if node.peerInfoTable[$info.peer].item.handle == 0:
          var domain = info.domain.split("/")[0] 
          node.peerInfoTable[$info.peer].item = peerboard.appendItem(peerRootTable[domain], formatItem & "\r\n")
      if node.peerFilter == "":
        previousConnectedPeers = newConnectedPeers
        newConnectedPeers.clear
      else:
        previousConnectedPeers.clear

      var connected = fanyi"nodes connected"
      statusBar.setStatusText(strformat.`&`"{peerboard.len - 1}:{peers.len} {connected} 上线: {onlinePeers.len} 离线: {offLine.len}\r\n")
      await sleepAsync(1000)

proc remoteReader(peer: string) {.async.} =
  {.gcsafe.}:
    while true:
      if node.remotes.hasKey(peer) and node.remotes[peer].hasKey(ChatProtocol):
        var line = await node.remotes[peer][ChatProtocol].transp.readLine()
        if line == "" or line == "stop":
          break
        if not node.chatOutputTable.hasKey(peer):
          var res = winim.SendMessage(frame.mHwnd, wEvent_Menu, WPARAM idCreateChatFrame, cast[LPARAM](&peer.cstring))
          if res != 0:
            continue
        var message = strformat.`&`"{node.peerInfoTable[peer].info.domain} {$now().format(timeFormat)}\r\n{line}\r\n"
        node.chatOutputTable[peer].add message
      else:
        break

proc serveThread() {.async.} =
  {.gcsafe.}:
    while true:
      try:
        if node.stop :break
        var (available,line) = node.messageChan.tryRecv()
        if not available: 
          await sleepAsync(100)
          continue
        if not line.startsWith("/") and line.len == 46 or line.len == 52:
          var peerId = PeerID.init(line).value
          node.consoleString = fanyi"Searching for" & line & "\r\n"
          console.add node.consoleString
          var id = await node.api.dhtFindPeer(peerId)

          var foundInPeerBoard: bool
          for i in peerboard.allItems:
            var item = i.getText().strip()
            if item.contains(line) or node.peerInfoTable.hasKey(line) and item.contains($node.peerInfoTable[line].info.domain):
              scrollTo i
              select i
              foundInPeerBoard = true
              node.consoleString = fanyi"in peerboard " & node.peerInfoTable[line].info.domain & "\r\n"
              console.add node.consoleString
              break
          if not foundInPeerBoard:
            node.consoleString = fanyi"not in peerboard" & "\r\n"
            console.add node.consoleString
        elif line.startsWith("/chat"):
          var parts = line.split(" ")
          if len(parts) == 2:
            var peer = getPeerId()
            var peerId = PeerID.init(peer).value
            var stream = await node.api.openStream(peerId, @[ChatProtocol])
            if node.remotes.hasKey(peer) and node.remotes[peer].len != 0:
              node.remotes[peer][ChatProtocol] = stream
            else:
              node.remotes[peer] = {ChatProtocol: stream}.toOrderedTable
            asyncCheck remoteReader(peer)

        elif line.startsWith("/search"):
          var parts = line.split(" ")
          if len(parts) == 2:
            var peer = getPeerId()
            var peerId = PeerID.init(peer).value
            var id = await node.api.dhtFindPeer(peerId)
            for item in id.addresses:
              node.consoleString = $item & "\r\n"
              console.add node.consoleString
        elif line.startsWith("/pub"):
          var parts = line.split(" ")
          if len(parts) == 3:
            var topic = parts[1]
            var message = parts[2]
            await node.api.pubsubPublish(topic, message)
        elif line.startsWith("/listpeers"):
          var parts = line.split(" ")
          if len(parts) == 2:
            var topic = parts[1]
            var peers = await node.api.pubsubListPeers(topic)
            echo peers
        elif line.startsWith("/gettopics"):
            var topics = await node.api.pubsubGetTopics()
            echo topics
        elif line.startsWith("/sub"):
          var parts = line.split(" ")
          if len(parts) == 2:
            var topic = parts[1]
            var ticket = await node.api.pubsubSubscribe(topic, callback)
            node.consoleString = fanyi"joined: " & ticket.topic & "\r\n"
            console.add node.consoleString 
        elif line.startsWith("/request"):
          var parts = line.split(" ")
          if len(parts) == 3:
            var stream: P2PStream
            var peer: string
            if not node.remotes.hasKey(peer):
              peer = getPeerId()
              var peerId = PeerID.init(peer).value
              var address = MultiAddress.init("/p2p-circuit/p2p/" & $peerId).value
              await node.api.connect(peerId, @[address], 30)
              stream = await node.api.openStream(peerId, @[RequestProtocol])
              if node.remotes.hasKey(peer) and node.remotes[peer].len != 0:
                node.remotes[peer][RequestProtocol] = stream
              else:
                node.remotes[peer] = {RequestProtocol:stream}.toOrderedTable
            else:
              stream = node.remotes[peer][RequestProtocol]
            var start ,eof = 0
            var fileWithEof = strformat.`&`("{parts[2]}:{eof}\r\n")
            discard await stream.transp.write(fileWithEof)
            var (path,name,ext) = parts[2].splitFile
            var file = name & ext
            var length = await stream.transp.readLine()
            var totalLength = length.parseInt
            echo "requested length:", totalLength
            hyperlinks[parts[2]].setCursor(Cursor(wCursorWait))

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
                stream = await node.api.openStream(peerId, @[RequestProtocol])
                fileWithEof = strformat.`&`("{parts[2]}:{f.getFilePos}\r\n")
                discard await stream.transp.write(fileWithEof)
            f.close()
            var duration = (now() - startTime).inMilliseconds()
            node.consoleString = strformat.`&`"用时{duration}ms" & "\r\n"
            console.add node.consoleString

            var tempFile = tempDir / name & ext
            if fileExists(tempFile):
              shellapi.ShellExecute(0, "open", tempFile , nil, nil, winim.SW_SHOW)
            hyperlinks[file].setCursor(Cursor(wCursorHand))

            # node.fileChan.send parts[2]

        elif line.startsWith "/send":
          var parts = line.split(" ")
          if len(parts) == 3:
            var stream: P2PStream
            var peer: string
            if not node.remotes.hasKey(peer):
              peer = getPeerId()
              var peerId = PeerID.init(peer).value
              var address = MultiAddress.init("/p2p-circuit/p2p/" & $peerId).value
              await node.api.connect(peerId, @[address], 30)
              stream  = await node.api.openStream(peerId, @[SendProtocol])
              if node.remotes.hasKey(peer) and node.remotes[peer].len != 0:
                node.remotes[peer][SendProtocol] = stream
              else:
                node.remotes[peer] = {SendProtocol:stream}.toOrderedTable
            else:
              stream = node.remotes[peer][SendProtocol]
            var (_,name,ext) = splitFile(parts[2])
            var content = readFile(parts[2])
            var file = name & ext
            var header = strformat.`&`"{file}:{content.len}\r\n"
            discard await stream.transp.write(header)

            node.consoleString = strformat.`&`"发送 {file} {content.len}字节" & "\r\n"
            console.add node.consoleString
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
            node.consoleString = strformat.`&`"{parts[1]}:用时{duration} ms" & "\r\n"
            console.add node.consoleString

        elif line.startsWith("/exit"):
          break
        elif line.startsWith("/run"):
          var parts = line.split(" ")
          if len(parts) == 2:
            await runNim(hyperlinks[parts[1]])
        else:
            var msg = line & "\r\n"
            var pending = newSeq[Future[int]]()
            for peer,streams in node.remotes:
                pending.add(streams[ChatProtocol].transp.write(msg))
            if len(pending) > 0:
                await allFutures(pending)
      except:
        var exceptionFrame = Frame(owner=frame, title="Error", style=wDefaultFrameStyle)
        var exception = TextCtrl(exceptionFrame, style = wTeRich or wTeMultiLine or wVScroll  or wTeReadOnly or wTeDontWrap)
        var e = getCurrentException()
        exception.add e.getStackTrace & "\r\n"

initDomain()
startDaemon()

proc wait() {.thread.} =
  waitFor all [serveThread(), status()]

var waitThread: Thread[void]
waitThread.createThread(wait)

node.messageChan.send("/sub " & node.topDomain)
node.messageChan.send("/sub 域名系统")

frame.center()
frame.show()
app.mainLoop()

waitThread.joinThread
shellOpen.joinThread