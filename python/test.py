from sdfgen import SystemDescription, ProtectionDomain, Sddf

if __name__ == '__main__':
    sdf = SystemDescription()
    sddf = Sddf("/Users/ivanv/ts/lionsos_tutorial/lionsos/dep/sddf")

    i2c_reactor_client = ProtectionDomain("i2c_reactor_client", "i2c_reactor_client.elf")
    i2c_virt = ProtectionDomain("i2c_virt", "i2c_virt.elf")
    i2c_reactor_driver = ProtectionDomain("i2c_reactor_driver", "i2c_reactor_driver.elf")

    i2c_system = Sddf.I2c(sdf, i2c_reactor_driver, i2c_virt)
    i2c_system.add_client(i2c_reactor_client)

    sdf.add_pd(i2c_reactor_client)
    sdf.add_pd(i2c_virt)
    sdf.add_pd(i2c_reactor_driver)

    i2c_system.connect()

    print(sdf.xml())
