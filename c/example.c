#include <stdio.h>
#include <sdfgen.h>

int main() {
    sdfgen_sddf_init("/Users/ivanv/ts/lionsos_tutorial/lionsos/dep/sddf");

    void *sdf = sdfgen_create();
    void *i2c_reactor_client = sdfgen_pd_create("i2c_reactor_client", "reactor_client.elf");
    void *i2c_virt = sdfgen_pd_create("i2c_virt", "i2c_virt.elf");
    void *i2c_reactor_driver = sdfgen_pd_create("i2c_reactor_driver", "reactor_driver.elf");

    void *i2c_system = sdfgen_sddf_i2c(sdf, NULL, i2c_reactor_driver, i2c_virt);
    sdfgen_sddf_i2c_add_client(i2c_system, i2c_reactor_client);

    sdfgen_sddf_i2c_connect(i2c_system);

    sdfgen_pd_set_priority(i2c_reactor_driver, 200);
    sdfgen_pd_set_priority(i2c_virt, 199);
    sdfgen_pd_set_priority(i2c_reactor_client, 198);

    sdfgen_pd_add(sdf, i2c_reactor_client);
    sdfgen_pd_add(sdf, i2c_virt);
    sdfgen_pd_add(sdf, i2c_reactor_driver);

    char *xml = sdfgen_to_xml(sdf);
    printf("%s", xml);
}
