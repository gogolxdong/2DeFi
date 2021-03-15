package p2pd

import (
	"context"
	"errors"
	"github.com/libp2p/go-libp2p-core/network"
	dht "github.com/libp2p/go-libp2p-kad-dht"
	pstore "github.com/libp2p/go-libp2p-peerstore"
	"math/rand"
	"time"
)

var BootstrapPeers = dht.DefaultBootstrapPeers

const BootstrapConnections = 1

func bootstrapPeerInfo() ([]*pstore.PeerInfo, error) {
	pis := make([]*pstore.PeerInfo, 0, len(BootstrapPeers))
	for _, a := range BootstrapPeers {
		pi, err := pstore.InfoFromP2pAddr(a)
		if err != nil {
			return nil, err
		}
		pis = append(pis, pi)
	}
	return pis, nil
}

func shufflePeerInfos(peers []*pstore.PeerInfo) {
	for i := range peers {
		j := rand.Intn(i + 1)
		peers[i], peers[j] = peers[j], peers[i]
	}
}

func (d *Daemon) Bootstrap() error {
	pis, err := bootstrapPeerInfo()
	if err != nil {
		return err
	}

	for _, pi := range pis {
		d.host.Peerstore().AddAddrs(pi.ID, pi.Addrs, pstore.PermanentAddrTTL)
	}

	count := d.connectBootstrapPeers(pis, len(pis))
	if count == 0 {
		return errors.New("Failed to connect to bootstrap peers")
	}

	go d.keepBootstrapConnections(pis)

	if d.dht != nil {
		return d.dht.Bootstrap(d.ctx)
	}

	return nil
}

func (d *Daemon) connectBootstrapPeers(pis []*pstore.PeerInfo, toconnect int) int {
	count := 0
	//shufflePeerInfos(pis)

	ctx, cancel := context.WithTimeout(d.ctx, 60*time.Second)
	defer cancel()

	for _, pi := range pis {
		if d.host.Network().Connectedness(pi.ID) == network.Connected {
			continue
		}
		err := d.host.Connect(ctx, *pi)
		if err != nil {
			log.Debugw("Error connecting to bootstrap peer", "peer", pi.ID, "error", err)
		} else {
			d.host.ConnManager().TagPeer(pi.ID, "bootstrap", 1)
			count++
			toconnect--
		}
		if toconnect == 0 {
			break
		}
	}
	return count

}

func (d *Daemon) keepBootstrapConnections(pis []*pstore.PeerInfo) {
	ticker := time.NewTicker(1 * time.Second)

	for {
		<-ticker.C
		d.connectBootstrapPeers(pis, len(pis))

		conns := d.host.Network().Conns()
		if len(conns) >= BootstrapConnections {
			continue
		}

		toconnect := BootstrapConnections - len(conns)
		d.connectBootstrapPeers(pis, toconnect)

	}
}
