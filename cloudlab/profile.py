"""CloudLab profile for TCP vs Homa datacenter benchmark.

Creates N nodes connected to a single LAN on c6525-25g hardware.
Node-0 acts as the receiver/server, remaining nodes are senders/clients.

Instructions:
  1. Go to CloudLab -> Experiments -> Create Experiment Profile
  2. Paste this file as the profile source
  3. Instantiate with desired node count
"""

import geni.portal as portal
import geni.rspec.pg as pg

pc = portal.Context()

pc.defineParameter("node_count", "Number of nodes (1 server + N-1 clients)",
                   portal.ParameterType.INTEGER, 5)
pc.defineParameter("hw_type", "Hardware type",
                   portal.ParameterType.STRING, "c6525-25g",
                   longDescription="c6525-25g = AMD EPYC 7302, 128GB RAM, 25GbE ConnectX-5")
pc.defineParameter("os_image", "OS Image",
                   portal.ParameterType.STRING,
                   "urn:publicid:IDN+emulab.net+image+emulab-ops//UBUNTU20-64-STD")

params = pc.bindParameters()

rspec = pg.Request()

lan = pg.LAN("bench-lan")
lan.best_effort = True
lan.vlan_tagging = True
lan.link_multiplexing = True

for i in range(params.node_count):
    name = "node-%d" % i
    node = pg.RawPC(name)
    node.hardware_type = params.hw_type
    node.disk_image = params.os_image

    node.addService(pg.Execute(
        shell="bash",
        command="sudo apt-get update -qq && sudo apt-get install -y -qq "
                "build-essential cmake git linux-headers-$(uname -r) "
                "python3 python3-pip htop iperf3 ethtool"
    ))

    iface = node.addInterface("if1")
    iface.addAddress(pg.IPv4Address("10.10.1.%d" % (i + 1), "255.255.255.0"))
    lan.addInterface(iface)
    rspec.addResource(node)

rspec.addResource(lan)

pc.printRequestRSpec(rspec)
