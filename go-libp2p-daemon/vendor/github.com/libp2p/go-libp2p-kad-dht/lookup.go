package dht

import (
	"context"
	"fmt"
	"time"

	"github.com/libp2p/go-libp2p-core/peer"
	"github.com/libp2p/go-libp2p-core/routing"

	pb "github.com/libp2p/go-libp2p-kad-dht/pb"
	kb "github.com/libp2p/go-libp2p-kbucket"
	"github.com/libp2p/go-libp2p-core/network"
	//ma "github.com/multiformats/go-multiaddr"

)

// GetClosestPeers is a Kademlia 'node lookup' operation. Returns a channel of
// the K closest peers to the given key.
//
// If the context is canceled, this function will return the context error along
// with the closest K peers it has found so far.
func (dht *IpfsDHT) GetClosestPeers(ctx context.Context, key string) (<-chan peer.ID, error) {
	if key == "" {
		return nil, fmt.Errorf("can't lookup empty key")
	}
	//TODO: I can break the interface! return []peer.ID
	lookupRes, err := dht.runLookupWithFollowup(ctx, key,
		func(ctx context.Context, p peer.ID) ([]*peer.AddrInfo, error) {
			// For DHT query commanddoStreamOpen

			routing.PublishQueryEvent(ctx, &routing.QueryEvent{
				Type: routing.SendingQuery,
				ID:   p,
			})

			pmes, err := dht.findPeerSingle(ctx, p, peer.ID(key))
			if err != nil {
				logger.Debugf("error getting closer peers: %s", err)
				return nil, err
			}
			peers := pb.PBPeersToPeerInfos(pmes.GetCloserPeers())

			// For DHT query command
			//bootstrapAddr := dht.bootstrapPeers[0].Addrs[0].String()
			bootstrapId := dht.bootstrapPeers[0].ID
			bootstrapConnectness := dht.host.Network().Connectedness(bootstrapId)
			if bootstrapConnectness == network.Connected{
				//addr := fmt.Sprintf("%s/p2p/%s/p2p-circuit",bootstrapAddr, bootstrapId.String())

				for _, p := range peers {
					//addr,_ := ma.NewMultiaddr("/p2p-circuit/p2p/" + p.ID.String())
					//p.Addrs = append(p.Addrs, addr)
					connectness := dht.host.Network().Connectedness(p.ID)
					if connectness == network.NotConnected{
						//addr, _ := ma.NewMultiaddr(addr)
						d,_:=dht.host.Peerstore().Get(p.ID,"Domain")
						domain,_ := d.(string)
						info := peer.AddrInfo{p.ID, p.Addrs, domain}
						//if info.Domain != ""{
						//	fmt.Println("connecting:", info.String())
							if err := dht.host.Connect(ctx, info); err != nil {
								continue
							}
						//}
					}
				}
			}

			routing.PublishQueryEvent(ctx, &routing.QueryEvent{
				Type:      routing.PeerResponse,
				ID:        p,
				Responses: peers,
			})
			return peers, err
		},
		func() bool { return false },
	)

	if err != nil {
		return nil, err
	}

	out := make(chan peer.ID, dht.bucketSize)
	defer close(out)
	for _, p := range lookupRes.peers {
		out <- p
	}

	if ctx.Err() == nil && lookupRes.completed {
		// refresh the cpl for this key as the query was successful
		dht.routingTable.ResetCplRefreshedAtForID(kb.ConvertKey(key), time.Now())
	}

	return out, ctx.Err()
}
