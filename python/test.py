from sdfgen import SystemDescription, ProtectionDomain, Sddf, DeviceTree

SDDF_PATH = "/Users/ivanv/ts/lionsos_tutorial/lionsos/dep/sddf"
DTB_PATH = "/Users/ivanv/ts/lionsos_tutorial/qemu_virt_aarch64.dtb"

if __name__ == '__main__':
    sdf = SystemDescription()
    sddf = Sddf(SDDF_PATH)

    with open(DTB_PATH, "rb") as f:
        dtb = DeviceTree(f.read())

    i2c_reactor_client = ProtectionDomain("i2c_reactor_client", "reactor_client.elf", priority=198)

    i2c_reactor_driver = ProtectionDomain("i2c_reactor_driver", "reactor_driver.elf", priority=200)
    i2c_virt = ProtectionDomain("i2c_virt", "i2c_virt.elf", priority=199)

    blk_driver = ProtectionDomain("blk_driver", "driver_blk_virtio.elf", priority=200)
    blk_virt = ProtectionDomain("blk_virt", "blk_virt.elf", priority=199)

    net_driver = ProtectionDomain("net_driver", "driver_net_virtio.elf", priority=200)
    net_virt_rx = ProtectionDomain("net_virt", "net_virt_rx.elf", priority=199)
    net_virt_tx = ProtectionDomain("net_virt", "net_virt_tx.elf", priority=199)

    timer_driver = ProtectionDomain("timer_driver", "driver_timer_arm.elf", priority=220)

    # net_micropython_copier = ProtectionDomain("net_micropython_copier", "net_micropython_copier.elf", priority=199)

    # micropython = ProtectionDomain("micropython", "micropython.elf", priority=100)

    # For our I2C system, we don't actually have a device used by the driver, since it's all emulated
    # in software, so we pass None as the device parameter
    i2c_system = Sddf.I2c(sdf, None, i2c_reactor_driver, i2c_virt)
    i2c_system.add_client(i2c_reactor_client)

    blk_node = dtb.node("virtio_mmio@a003e00")
    assert blk_node is not None
    blk_system = Sddf.Block(sdf, blk_node, blk_driver, blk_virt)
    blk_system.add_client(i2c_reactor_client)

    timer_system = Sddf.Timer(sdf, dtb.node("timer"), timer_driver)
    print("heree")
    timer_system.add_client(i2c_reactor_client)

    # net_node = dtb.node("virtio_mmio@a003c00")
    # assert net_node is not None
    # net_system = Sddf.Network(sdf, net_node, net_driver, net_virt_rx, net_virt_tx)
    # net_system.add_client_with_copier(micropython, net_micropython_copier)

    pds = [
        i2c_reactor_client,
        i2c_virt,
        i2c_reactor_driver,
        blk_driver,
        blk_virt,
        timer_driver,
        # net_driver,
        # net_virt_rx,
        # net_virt_tx,
        # net_micropython_copier,
        # micropython
    ]
    for pd in pds:
        sdf.add_pd(pd)

    i2c_system.connect()
    blk_system.connect()
    # net_system.connect()
    timer_system.connect()

    print(sdf.xml())
