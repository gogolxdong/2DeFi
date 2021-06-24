# 灵犀2DeFi-Deduplicated and Decentralized File system

## 在IPFS网络上构建自治的域名系统

将节点域名内联在和IPFS节点标识同一级别，以在合适的时候切换到域名寻址。域名系统对社会活动中的基本单元进行了抽象，例如一个企业，一场活动，一群功能设备...

- 同一域名前缀的节点归纳在相同域名下，相同域名下的节点自动订阅该域名内的消息
- 同级域名下的节点相互同步，形成不少于两个副本的备份
- 应用访问具有域名前缀的文件，实现负载均衡

## 点对点加密传输

- 选项1：使用IPFS公共引导节点，手动搜索目标节点
- 选项2：使用私有引导节点实现自动连接带有域名的节点

- 如`/connect Nim中文社区/Sheldon`或`/connect 12D3KooWAzLnKu4y96AAdtV68EGCVngEpPM1euNJB3WNr9ru4xu9`

- 在对话框输入内容，开始对话
  
## 分享文件
- 在菜单栏界面上点击文件->打开->选择需要分享的文件，同一域名下和订阅节点将收到分享链接，点击链接使用系统默认应用打开

## 内置miniblink浏览器

- 在搜索栏输入网址浏览Web网站

- 在搜索栏输入本地HTML文件地址进行浏览

## 发布和订阅

- 打开文件会在节点所在域名内自动发布文件链接，该域名下的节点和订阅节点将收到分享的文件链接：

### 手动发布和订阅消息

- `/sub 新闻`
- `/pub 新闻 "今日热点"`

## 提供多系统支持

- Windows系统使用具有用户图形界面的guiNode，类Unix系统使用命令行客户端clientNode，预编译的可执行文件架构为x86_64

- 引导节点使用bootstrapNode，引导节点至少需要具有公网ipv4地址

# 编译指南：

```shell
cd go-libp2p-daemon/p2pd
(linux) go build -mod=vendor . && cp p2pd ../..
(windows cmd) go build -mod=vendor . && copy p2pd.exe ..\.. /B/Y
nim c -r guiNode.nim
```

# TODO:

- [X] 节点域名
- [X] Gossip协议的发布/订阅
- [X] 分享文件发布
- [X] 分享文件链接使用内置应用打开
- [X] 分享文件链接使用系统默认应用打开
- [ ] 内存持久化存储
- [ ] 备份与负载均衡
- [ ] 文件所有权/版权/隐私
- [ ] 存储贡献和分享的文件信息存储在区块链上
- [ ] 用Nim定制libp2p多地址和发布订阅协议
- [ ] Linux/MacOS/手机端跨平台GUI

