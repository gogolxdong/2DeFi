import languages
import tables, strutils,os,json

var config* = if fileExists("config.json"): parseFile("config.json") else: %* {"domain":"","id":"","language":"zhCN","bootstrapNodes": 
        ["/ip4/158.247.214.165/udp/5001/quic/p2p/12D3KooW9rYLwLMUS7A7up4CZ3UdmNRkX8ybMxdEiWPSRLd7s5uS",
        "/ip4/104.131.131.82/tcp/4001/p2p/QmaCpDMGvV2BGHeYERUEnRQAwe3N8SzbUtfsmvsqQLuvuJ",
        "/ip4/104.131.131.82/udp/4001/quic/p2p/QmaCpDMGvV2BGHeYERUEnRQAwe3N8SzbUtfsmvsqQLuvuJ"]
        }

var currentLanguage* = config["language"].getStr

proc setCurrentLanguage*(newLanguage: string) =
  currentLanguage = newLanguage
  config["language"] = %newLanguage
  writeFile("config.json", $config)

proc getCurrentLanguage*(): string = currentLanguage
type Translation* = OrderedTable[string, string]


var translations: OrderedTable[string, Translation] = initOrderedTable[string, Translation]()

proc registerTranslation*(lang: string; t: Translation) = translations[lang] = t

proc addT*(lang: string; key, val: string) =
  if translations.hasKey lang:
      translations[lang][key] = val
  else: 
    translations[lang] = initOrderedTable[string,string]()

proc fanyi*(x: string): string =  
  let y = translations[currentLanguage]
  if y.hasKey(x):
    result = y[x]
  else:
    result = x

proc raiseInvalidFormat(errmsg: string) =
  raise newException(ValueError, errmsg)

proc parseChoice(f: string; i, choice: int, r: var seq[char]) =
  var i = i
  while i < f.len:
    var n = 0
    let oldI = i
    var toAdd = false
    while i < f.len and f[i] >= '0' and f[i] <= '9':
      n = n * 10 + ord(f[i]) - ord('0')
      inc i
    if oldI != i:
      if f[i] == ':':
        inc i
      else:
        raiseInvalidFormat"':' after number expected"
      toAdd = choice == n
    else:
      # an else section does not start with a number:
      toAdd = true
    while i < f.len and f[i] != ']' and f[i] != '|':
      if toAdd: r.add f[i]
      inc i
    if toAdd: break
    inc i

proc `%`*(formatString: string; args: openArray[string]): string =
  let f = string(formatString)
  var i = 0
  var num = 0
  var r = newSeq[char]()
  while i < f.len:
    if f[i] == '$' and i+1 < f.len:
      inc i
      case f[i]
      of '#':
        r.add args[num]
        inc i
        inc num
      of '1'..'9', '-':
        var j = 0
        var negative = f[i] == '-'
        if negative: inc i
        while f[i] >= '0' and f[i] <= '9':
          j = j * 10 + ord(f[i]) - ord('0')
          inc i
        let idx = if not negative: j-1 else: args.len-j
        r.add args[idx]
      of '$':
        inc(i)
        r.add '$'
      of '[':
        let start = i+1
        while i < f.len and f[i] != ']': inc i
        inc i
        if i >= f.len: raiseInvalidFormat"']' expected"
        case f[i]
        of '#':
          parseChoice(f, start, parseInt args[num], r)
          inc i
          inc num
        of '1'..'9', '-':
          var j = 0
          var negative = f[i] == '-'
          if negative: inc i
          while f[i] >= '0' and f[i] <= '9':
            j = j * 10 + ord(f[i]) - ord('0')
            inc i
          let idx = if not negative: j-1 else: args.len-j
          parseChoice(f, start, parseInt args[idx], r)
        else: raiseInvalidFormat"argument index expected after ']'"
      else:
        raiseInvalidFormat("'#', '$', or number expected")
      if i < f.len and f[i] == '$': inc i
    else:
      r.add f[i]
      inc i
  result = join(r)

addT("enUS", "OK", "OK")
addT("enUS", "Cancel", "Cancel")
addT("enUS", "File", "File")
addT("enUS", "Open", "Open")
addT("enUS", "Exit", "Exit")
addT("enUS", "Layout", "Layout")
addT("enUS", "Horizontal", "Horizontal")
addT("enUS", "Vertical", "Vertical")
addT("enUS", "Language", "Language")
addT("enUS", "nodes connected", "nodes connected")
addT("enUS", "shared", "shared")
addT("enUS", "Alias: ", "Alias: ")
addT("enUS", "Searching for", "Searching for ")
addT("enUS", "Connecting to", "Connecting to ")
addT("enUS", "Copy", "Copy")
addT("zhCN", "Check", "Check")
addT("enUS", "Chat", "Chat")
addT("enUS", "Watch", "Watch")
addT("enUS", "Search", "Search")
addT("enUS", "Delete", "Delete")
addT("enUS", "Send", "Send")
addT("enUS", "joined: ", "joined: ")
addT("enUS", "Run", "Run")
addT("enUS", "Like", "Like")
addT("enUS", "Close", "Close")
addT("enUS", "in peerboard ", "in peerboard")
addT("enUS", "not in peerboard", "not in peerboard")

addT("zhCN", "OK", "确认")
addT("zhCN", "Cancel", "取消")
addT("zhCN", "File", "文件")
addT("zhCN", "Open", "打开")
addT("zhCN", "Exit", "退出")
addT("zhCN", "Layout", "布局")
addT("zhCN", "Horizontal", "水平")
addT("zhCN", "Vertical", "垂直")
addT("zhCN", "Language", "语言")
addT("zhCN", "nodes connected", "个节点已连接")
addT("zhCN", "shared", "分享了")
addT("zhCN", "Domain: ", "域名: ")
addT("zhCN", "Searching for", "搜索")
addT("zhCN", "Connecting to", "连接")
addT("zhCN", "Enter the domain", "输入域名")
addT("zhCN", "Connected to peer chat ", "连接到点对点对话")
addT("zhCN", "Copy", "复制")
addT("zhCN", "Check", "查看")
addT("zhCN", "Chat", "对话")
addT("zhCN", "Watch", "关注")
addT("zhCN", "watched: ", "已关注：")
addT("zhCN", "Search", "搜索")
addT("zhCN", "Delete", "移除")
addT("zhCN", "Send", "发送")
addT("zhCN", "joined: ", "已加入:")
addT("zhCN", "Run", "运行")
addT("zhCN", "Like", "点赞")
addT("zhCN", "Close", "关闭")
addT("zhCN", "in peerboard ", "在节点列表")
addT("zhCN", "not in peerboard", "不在节点列表")
