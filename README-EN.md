# 2DeFi-Deduplicated and Decentralized File system
- Leverage idle storage and bandwith resource to share files and get sharing reward.
- Obtain storage reward for supplying reliable storage space.
- File shared/stored with deterministic ownership/copyright/privacy.
- File opened with builtin application owns auto-load-balancing, cache strategy, supports main-stream file types including audio/video/picture/text/staic Html
- Storage commitment and shared files are recorded on blockchain, to implement ownership confirmation/tranformation and tracable.  

# Current Functionality:

- p2pd.exe is prebuilt which is required to get DHT to work, you can build it by yourself from [go-libp2p-daemon](https://github.com/libp2p/go-libp2p-daemon)

1. Connect a node and start to chat(Chinese supported):

- `/connect QmQx4FvYELrxrB7cPtwowpZbRAmNytitVPZCT6dGaJZScj`

2. Search a node, which could penetrate NAT and establish connection with Internet:

- `/search 12D3KooWFu9cU6GTbti1Xcqj9Z32dcpk5xwNzTriYYZzjKLTDAme`

3. Publish and subcription:

- `/sub 新闻`
- `/pub 新闻 "今日热点" `

1. Use guiNode for Windows，clientNode for Unix-like system, bootstrapNode for bootstrap node.

# TODO:

- [X] Peer ID alias
- [X] Gossip pub/sub
- [X] File sharing publish
- [X] Open hyperlink with default system application 
- [ ] Record storage commitment and shared file information on blockchain
- [ ] Open hyperlink with builtin application, including audio/video/picture/static Web 
- [ ] Implement libp2p multiaddr and pub/sub protocol in Nim 
- [ ] Ownership/Copyright fingerprint
- [ ] Cross platform GUI including Linux/MacOS/Mobile phone
