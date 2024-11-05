from sdfgen import SystemDescription, ProtectionDomain, Sddf, DeviceTree, LionsOS, Channel

SDDF_PATH = "/Users/ivanv/ts/lionsos_tutorial/lionsos/dep/sddf"
DTB_PATH = "/Users/ivanv/ts/lionsos_tutorial/qemu_virt_aarch64.dtb"

# TODO: temporary
PADDR_TOP = 0xa_000_000

if __name__ == '__main__':
    sdf = SystemDescription(PADDR_TOP)
    sddf = Sddf(SDDF_PATH)

    with open(DTB_PATH, "rb") as f:
        dtb = DeviceTree(f.read())

    reactor_client = ProtectionDomain("reactor_client", "reactor_client.elf", priority=2)

    i2c_reactor_driver = ProtectionDomain("i2c_reactor_driver", "reactor_driver.elf", priority=200)
    i2c_virt = ProtectionDomain("i2c_virt", "i2c_virt.elf", priority=199)

    blk_driver = ProtectionDomain("blk_driver", "blk_driver.elf", priority=200)
    blk_virt = ProtectionDomain("blk_virt", "blk_virt.elf", priority=199)

    net_driver = ProtectionDomain("net_driver", "eth_driver.elf")
    net_virt_rx = ProtectionDomain("net_virt_rx", "network_virt_rx.elf")
    net_virt_tx = ProtectionDomain("net_virt_tx", "network_virt_tx.elf")

    timer_driver = ProtectionDomain("timer_driver", "timer_driver.elf")

    net_mp_copier = ProtectionDomain("net_copy_mp", "copy.elf")

    micropython = ProtectionDomain("micropython", "micropython.elf", priority=1)

    # For our I2C system, we don't actually have a device used by the driver, since it's all emulated
    # in software, so we pass None as the device parameter
    i2c_system = Sddf.I2c(sdf, None, i2c_reactor_driver, i2c_virt)
    i2c_system.add_client(reactor_client)

    fatfs = ProtectionDomain("fatfs", "fat.elf", priority=198)
    web_fatfs = ProtectionDomain("web_fatfs", "fat.elf")

    blk_node = dtb.node("virtio_mmio@a003e00")
    assert blk_node is not None
    blk_system = Sddf.Block(sdf, blk_node, blk_driver, blk_virt)
    blk_system.add_client(fatfs)
    blk_system.add_client(web_fatfs)

    timer_system = Sddf.Timer(sdf, dtb.node("timer"), timer_driver)
    timer_system.add_client(reactor_client)
    timer_system.add_client(micropython)

    net_node = dtb.node("virtio_mmio@a003c00")
    assert net_node is not None
    net_system = Sddf.Network(sdf, net_node, net_driver, net_virt_rx, net_virt_tx)
    net_system.add_client_with_copier(micropython, net_mp_copier)

    fs = LionsOS.FileSystem(sdf, fatfs, reactor_client)

    web_fs = LionsOS.FileSystem(sdf, web_fatfs, micropython)

    pds = [
        reactor_client,
        i2c_virt,
        i2c_reactor_driver,
        timer_driver,
        fatfs,
        web_fatfs,
        blk_driver,
        blk_virt,
        net_virt_rx,
        net_virt_tx,
        net_driver,
        micropython,
        net_mp_copier,
    ]
    for pd in pds:
        sdf.add_pd(pd)

    i2c_system.connect()
    timer_system.connect()
    blk_system.connect()
    net_system.connect()
    fs.connect()
    web_fs.connect()

    sdf.add_channel(Channel(reactor_client, micropython))

    print(sdf.xml())
