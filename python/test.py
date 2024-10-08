from sdfgen import SystemDescription, ProtectionDomain, Sddf, DeviceTree

if __name__ == '__main__':
    sdf = SystemDescription()
    sddf = Sddf("/Users/ivanv/ts/lionsos_tutorial/lionsos/dep/sddf")

    with open("/Users/ivanv/ts/lionsos_tutorial/qemu_virt_aarch64.dtb", "rb") as f:
        dtb = DeviceTree(f.read())

    i2c_reactor_client = ProtectionDomain("i2c_reactor_client", "reactor_client.elf", priority=198)
    i2c_virt = ProtectionDomain("i2c_virt", "i2c_virt.elf", priority=199)
    i2c_reactor_driver = ProtectionDomain("i2c_reactor_driver", "reactor_driver.elf", priority=200)

    blk_driver = ProtectionDomain("blk_driver", "driver_blk_virtio.elf", priority=200)
    blk_virt = ProtectionDomain("blk_virt", "blk_virt.elf", priority=200)

    # Device is part of the driver, so we pass None
    i2c_system = Sddf.I2c(sdf, None, i2c_reactor_driver, i2c_virt)
    i2c_system.add_client(i2c_reactor_client)

    blk_system = Sddf.Block(sdf, dtb.node("virtio_mmio@a003e00"), blk_driver, blk_virt)
    blk_system.add_client(i2c_reactor_client)

    pds = [
        i2c_reactor_client,
        i2c_virt,
        i2c_reactor_driver,
        blk_driver,
        blk_virt
    ]
    for pd in pds:
        sdf.add_pd(pd)

    i2c_system.connect()
    blk_system.connect()

    print(sdf.xml())
