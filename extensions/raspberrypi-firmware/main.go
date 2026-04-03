package main

import (
	"log"
	"net"
	"os"
	"os/exec"
	"time"

	"github.com/vishvananda/netlink"
)

const (
	ifaceName = "wlx88a29e5f7528"
	ipAddress = "192.168.1.100/24"
	gateway   = "192.168.1.254"
)

func main() {
	log.Printf("Starting WiFi Manager for %s", ifaceName)

	// 1. Start wpa_supplicant in the background
	go runWpaSupplicant()

	// 2. Monitoring loop
	for {
		ensureNetworkConfig()
		time.Sleep(10 * time.Second)
	}
}

func runWpaSupplicant() {
	for {
		log.Printf("Launching wpa_supplicant...")
		cmd := exec.Command("/usr/sbin/wpa_supplicant", "-i", ifaceName, "-c", "/etc/wpa_supplicant.conf")
		cmd.Stdout = os.Stdout
		cmd.Stderr = os.Stderr
		
		if err := cmd.Run(); err != nil {
			log.Printf("wpa_supplicant exited with error: %v. Restarting in 5s...", err)
		}
		time.Sleep(5 * time.Second)
	}
}

func ensureNetworkConfig() {
	link, err := netlink.LinkByName(ifaceName)
	if err != nil {
		log.Printf("Waiting for interface %s...", ifaceName)
		return
	}

	// 1. Force Link Up
	if link.Attrs().Flags&net.FlagUp == 0 {
		log.Printf("Setting %s UP", ifaceName)
		_ = netlink.LinkSetUp(link)
	}

	// 2. Ensure IP is assigned (Mandatory for the route to exist)
	addr, _ := netlink.ParseAddr(ipAddress)
	// AddrReplace is idempotent; it won't spam if the IP is already there
	if err := netlink.AddrReplace(link, addr); err != nil {
		log.Printf("Error ensuring IP: %v", err)
	}

	// 3. Check for the Default Route
	routes, err := netlink.RouteList(link, netlink.FAMILY_V4)
	if err != nil {
		return
	}

	gwIP := net.ParseIP(gateway)
	hasRoute := false
	for _, r := range routes {
		// A default route has a nil Dst or 0.0.0.0/0
		isDefault := r.Dst == nil || r.Dst.IP.IsUnspecified()
		
		// Match gateway and ensure it's on our specific link
		if isDefault && r.Gw != nil && r.Gw.Equal(gwIP) {
			hasRoute = true
			break
		}
	}

	if !hasRoute {
		log.Printf("Route not found. Adding default route via %s (Onlink=true)", gateway)
		
		err := netlink.RouteReplace(&netlink.Route{
			LinkIndex: link.Attrs().Index,
			Gw:        gwIP,
			Dst:       nil,
			// Flags: netlink.FLAG_ONLINK is crucial here. 
			// It tells the kernel to ignore the fact that the carrier is "down".
			Flags:     int(netlink.FLAG_ONLINK), 
		})
		
		if err != nil {
			log.Printf("Error adding route: %v", err)
		}
	}
}
